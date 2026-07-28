#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Wireless Interface Management Library
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Detect, configure, and manage wireless interfaces
# ======================================================================

# source colors if not already loaded
[[ -z "$RED" ]] && source "${SCRIPT_DIR}/../config/colors.sh" 2>/dev/null

# ======================================================================
#  DETECT WIRELESS INTERFACE
#  Returns: sets MANAGED_IFACE globally, echoes interface name
# ======================================================================
detect_wlan() {
    local iface=""

    # priority 1: check config override
    if [[ -n "$DEFAULT_WLAN" ]]; then
        if iwconfig "$DEFAULT_WLAN" 2>/dev/null | grep -q "ESSID"; then
            export MANAGED_IFACE="$DEFAULT_WLAN"
            echo "$MANAGED_IFACE"
            return 0
        else
            msg_warn "Configured interface '$DEFAULT_WLAN' not found. Auto-detecting..."
        fi
    fi

    # priority 2: first wireless iface with ESSID support
    iface=$(iwconfig 2>/dev/null | grep -oP '^\w+' | head -1)

    if [[ -n "$iface" ]]; then
        export MANAGED_IFACE="$iface"
        echo "$MANAGED_IFACE"
        return 0
    fi

    # priority 3: check /sys/class/net for wireless devices
    for dev in /sys/class/net/*; do
        iface=$(basename "$dev")
        if [[ -d "/sys/class/net/$iface/wireless" ]]; then
            export MANAGED_IFACE="$iface"
            echo "$MANAGED_IFACE"
            return 0
        fi
    done

    # nothing found
    msg_error "No wireless interface detected. Is your adapter plugged in?"
    return 1
}

# ======================================================================
#  START MONITOR MODE
#  Args: $1 = interface name (optional, uses MANAGED_IFACE if empty)
#  Returns: sets MON_IFACE globally, echoes monitor interface name
# ======================================================================
start_monitor_mode() {
    local iface="${1:-$MANAGED_IFACE}"

    if [[ -z "$iface" ]]; then
        msg_error "No interface specified for monitor mode."
        return 1
    fi

    msg_info "Enabling monitor mode on $iface..."

    # kill interfering processes
    airmon-ng check kill 2>/dev/null

    # start monitor mode
    airmon-ng start "$iface" 2>/dev/null

    # wait for interface to stabilize
    sleep 1

    # detect the new monitor interface
    local mon_iface=""
    mon_iface=$(iwconfig 2>/dev/null | grep -oP '^\w+(?=.*Mode:Monitor)' | head -1)

    if [[ -z "$mon_iface" ]]; then
        # fallback: try standard naming convention
        mon_iface="${iface}${MON_IFACE_SUFFIX}"
        if ! iwconfig "$mon_iface" 2>/dev/null | grep -q "Mode:Monitor"; then
            msg_error "Failed to create monitor interface."
            return 1
        fi
    fi

    export MON_IFACE="$mon_iface"
    msg_success "Monitor mode active: $MON_IFACE"
    echo "$MON_IFACE"
    return 0
}

# ======================================================================
#  STOP MONITOR MODE
#  Restores interface to managed mode
# ======================================================================
stop_monitor_mode() {
    if [[ -z "$MON_IFACE" ]]; then
        msg_warn "No monitor interface to stop."
        return 0
    fi

    msg_info "Disabling monitor mode on $MON_IFACE..."

    if iwconfig "$MON_IFACE" 2>/dev/null | grep -q "Mode:Monitor"; then
        airmon-ng stop "$MON_IFACE" 2>/dev/null
        sleep 1
    fi

    # verify it's down
    if iwconfig "$MON_IFACE" 2>/dev/null | grep -q "Mode:Monitor"; then
        # force it down manually
        ip link set "$MON_IFACE" down 2>/dev/null
        iw dev "$MON_IFACE" set type managed 2>/dev/null
        ip link set "$MON_IFACE" up 2>/dev/null
    fi

    msg_success "Monitor mode disabled."
    export MON_IFACE=""
    return 0
}

# ======================================================================
#  SET CHANNEL
#  Args: $1 = channel number (1-14 for 2.4GHz, 36-165 for 5GHz)
#        $2 = interface (optional, uses MON_IFACE)
# ======================================================================
set_channel() {
    local channel="$1"
    local iface="${2:-$MON_IFACE}"

    if [[ -z "$channel" ]]; then
        msg_error "No channel specified."
        return 1
    fi

    if [[ -z "$iface" ]]; then
        msg_error "No interface available for channel change."
        return 1
    fi

    # validate channel range
    if [[ "$channel" -lt 1 ]] || [[ "$channel" -gt 165 ]]; then
        msg_error "Invalid channel: $channel (valid: 1-14, 36-165)"
        return 1
    fi

    iwconfig "$iface" channel "$channel" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        msg_info "Channel set to $channel on $iface"
        return 0
    else
        msg_error "Failed to set channel $channel on $iface"
        return 1
    fi
}

# ======================================================================
#  GET CURRENT CHANNEL
#  Args: $1 = interface (optional, uses MON_IFACE or MANAGED_IFACE)
#  Echoes: channel number
# ======================================================================
get_current_channel() {
    local iface="${1:-${MON_IFACE:-$MANAGED_IFACE}}"

    if [[ -z "$iface" ]]; then
        echo "0"
        return 1
    fi

    local channel
    channel=$(iwlist "$iface" channel 2>/dev/null | grep -oP '(?<=Channel )\d+' | head -1)

    if [[ -z "$channel" ]]; then
        # alternate method
        channel=$(iwconfig "$iface" 2>/dev/null | grep -oP '(?<=Channel=)\d+' | head -1)
    fi

    echo "${channel:-0}"
}

# ======================================================================
#  GET INTERFACE MAC ADDRESS
#  Args: $1 = interface name
#  Echoes: MAC address
# ======================================================================
get_mac() {
    local iface="$1"

    if [[ -z "$iface" ]]; then
        echo "00:00:00:00:00:00"
        return 1
    fi

    cat "/sys/class/net/$iface/address" 2>/dev/null || echo "00:00:00:00:00:00"
}

# ======================================================================
#  RANDOMIZE MAC ADDRESS
#  Args: $1 = interface name
#  Note: interface must be down before changing
# ======================================================================
randomize_mac() {
    local iface="$1"

    if [[ -z "$iface" ]]; then
        msg_error "No interface specified for MAC randomization."
        return 1
    fi

    if [[ "$MAC_CHANGER_ENABLED" != "true" ]]; then
        msg_info "MAC randomization disabled in config."
        return 0
    fi

    local old_mac
    old_mac=$(get_mac "$iface")

    msg_info "Randomizing MAC on $iface..."

    ip link set "$iface" down 2>/dev/null

    # generate random MAC with locally administered bit (x2:xx:xx...)
    local new_mac
    new_mac=$(printf '02:%02x:%02x:%02x:%02x:%02x\n' \
        $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) \
        $((RANDOM % 256)) $((RANDOM % 256)))

    ip link set "$iface" address "$new_mac" 2>/dev/null
    ip link set "$iface" up 2>/dev/null

    local verify_mac
    verify_mac=$(get_mac "$iface")

    if [[ "$verify_mac" == "$new_mac" ]]; then
        msg_success "MAC changed: $old_mac → $new_mac"
        return 0
    else
        msg_warn "MAC randomization may have failed. Old: $old_mac"
        return 1
    fi
}

# ======================================================================
#  GET INTERFACE CHIPset INFORMATION
#  Args: $1 = interface name
#  Echoes: chipset string
# ======================================================================
get_chipset() {
    local iface="$1"

    if [[ -z "$iface" ]]; then
        echo "Unknown"
        return 1
    fi

    local chipset
    chipset=$(ethtool -i "$iface" 2>/dev/null | grep -oP '(?<=driver: ).*' | head -1)

    if [[ -z "$chipset" ]]; then
        # try lsusb for USB adapters
        chipset=$(lsusb 2>/dev/null | grep -i "wireless\|wifi\|wlan" | head -1 | cut -d':' -f3 | xargs)
    fi

    echo "${chipset:-Unknown}"
}

# ======================================================================
#  CHECK IF INTERFACE SUPPORTS PACKET INJECTION
#  Returns: 0 if supported, 1 if not
# ======================================================================
check_injection_capable() {
    local iface="${1:-$MON_IFACE}"

    if [[ -z "$iface" ]]; then
        msg_error "No interface to test injection capability."
        return 1
    fi

    msg_info "Testing packet injection on $iface..."

    local result
    result=$(aireplay-ng --test "$iface" 2>/dev/null | grep -oP '\d+/\d+' | head -1)

    if [[ -n "$result" ]]; then
        msg_success "Injection working: $result packets"
        return 0
    else
        msg_warn "Injection test inconclusive. Adapter may still work."
        return 1
    fi
}

# ======================================================================
#  LIST ALL WIRELESS INTERFACES
#  Echoes: list of wireless interfaces with details
# ======================================================================
list_interfaces() {
    echo ""
    msg_info "Available Wireless Interfaces:"
    echo ""
    printf "  ${WHITE}%-12s %-20s %-8s %s${NC}\n" "IFACE" "MAC" "MODE" "CHIPSET"
    printf "  ${GRAY}%-12s %-20s %-8s %s${NC}\n" "────" "───" "────" "───────"

    for dev in /sys/class/net/*; do
        local iface
        iface=$(basename "$dev")

        if [[ -d "/sys/class/net/$iface/wireless" ]]; then
            local mac mode chipset
            mac=$(get_mac "$iface")
            mode=$(iwconfig "$iface" 2>/dev/null | grep -oP '(?<=Mode:)\w+' || echo "Unknown")
            chipset=$(get_chipset "$iface")

            printf "  ${GREEN}%-12s${NC} %-20s ${YELLOW}%-8s${NC} ${GRAY}%s${NC}\n" \
                "$iface" "$mac" "$mode" "$chipset"
        fi
    done
    echo ""
}

# ======================================================================
#  RESTORE NETWORK MANAGER
# ======================================================================
restore_network_manager() {
    msg_info "Restarting NetworkManager..."

    # re-enable wifi if it was disabled
    nmcli radio wifi on 2>/dev/null

    # restart the service
    systemctl restart NetworkManager 2>/dev/null &
    sleep 2

    msg_success "NetworkManager restored."
}

# ======================================================================
#  INIT — auto-detect on source
# ======================================================================
if [[ -z "$MANAGED_IFACE" ]]; then
    detect_wlan 2>/dev/null
fi

# ======================================================================
#  END OF INTERFACE LIBRARY
# ======================================================================