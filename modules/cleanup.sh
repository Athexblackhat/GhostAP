#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Cleanup & Restoration Module
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Graceful shutdown — kills processes, restores iptables,
#               disables monitor mode, restarts networking
# ======================================================================

# source dependencies
SCRIPT_DIR_CLEANUP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${SCRIPT_DIR_CLEANUP}/config/colors.sh" 2>/dev/null
source "${SCRIPT_DIR_CLEANUP}/config/settings.conf" 2>/dev/null
source "${SCRIPT_DIR_CLEANUP}/lib/logger.sh" 2>/dev/null

# ======================================================================
#  KILL ALL ATTACK-RELATED PROCESSES
# ======================================================================
kill_attack_processes() {
    log_info "Terminating attack processes..."

    local killed=0

    # hostapd (fake AP)
    if pgrep -x "hostapd" &>/dev/null; then
        pkill -x "hostapd" 2>/dev/null
        sleep 0.3
        pkill -9 -x "hostapd" 2>/dev/null
        killed=$((killed + 1))
        log_debug "Killed: hostapd"
    fi

    # dnsmasq (DHCP/DNS)
    if pgrep -x "dnsmasq" &>/dev/null; then
        pkill -x "dnsmasq" 2>/dev/null
        sleep 0.3
        pkill -9 -x "dnsmasq" 2>/dev/null
        killed=$((killed + 1))
        log_debug "Killed: dnsmasq"
    fi

    # aireplay-ng (deauth)
    if pgrep -x "aireplay-ng" &>/dev/null; then
        pkill -x "aireplay-ng" 2>/dev/null
        sleep 0.3
        pkill -9 -x "aireplay-ng" 2>/dev/null
        killed=$((killed + 1))
        log_debug "Killed: aireplay-ng"
    fi

    # airodump-ng (scanner)
    if pgrep -x "airodump-ng" &>/dev/null; then
        pkill -x "airodump-ng" 2>/dev/null
        sleep 0.3
        pkill -9 -x "airodump-ng" 2>/dev/null
        killed=$((killed + 1))
        log_debug "Killed: airodump-ng"
    fi

    # flask/python captive portal
    if pgrep -f "ghostap_portal.py" &>/dev/null; then
        pkill -f "ghostap_portal.py" 2>/dev/null
        sleep 0.3
        pkill -9 -f "ghostap_portal.py" 2>/dev/null
        killed=$((killed + 1))
        log_debug "Killed: ghostap_portal.py"
    fi

    # xterm windows spawned by GhostAP
    if pgrep -f "GhostAP" &>/dev/null; then
        pkill -f "GhostAP" 2>/dev/null
        sleep 0.2
        pkill -9 -f "GhostAP" 2>/dev/null
        killed=$((killed + 1))
        log_debug "Killed: GhostAP xterm(s)"
    fi

    # dhclient (may have been spawned)
    if pgrep -x "dhclient" &>/dev/null; then
        pkill -x "dhclient" 2>/dev/null
        sleep 0.2
        pkill -9 -x "dhclient" 2>/dev/null
        killed=$((killed + 1))
        log_debug "Killed: dhclient"
    fi

    if [[ "$killed" -gt 0 ]]; then
        log_success "Terminated ${killed} attack process(es)."
    else
        log_info "No attack processes found running."
    fi
}

# ======================================================================
#  RESTORE IPTABLES
# ======================================================================
restore_iptables() {
    log_info "Restoring iptables..."

    # flush all rules
    iptables --flush 2>/dev/null
    iptables --table nat --flush 2>/dev/null
    iptables --table mangle --flush 2>/dev/null
    iptables --table raw --flush 2>/dev/null

    # delete user-defined chains
    iptables --delete-chain 2>/dev/null
    iptables --table nat --delete-chain 2>/dev/null
    iptables --table mangle --delete-chain 2>/dev/null
    iptables --table raw --delete-chain 2>/dev/null

    # restore default policies
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null

    # disable IP forwarding
    echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null

    log_success "iptables restored to defaults."
}

# ======================================================================
#  RESTORE WIRELESS INTERFACE
# ======================================================================
restore_interface() {
    log_info "Restoring wireless interface..."

    # stop monitor mode if active
    if [[ -n "$MON_IFACE" ]]; then
        if iwconfig "$MON_IFACE" 2>/dev/null | grep -q "Mode:Monitor"; then
            airmon-ng stop "$MON_IFACE" 2>/dev/null
            sleep 1
        fi

        # force managed mode if still in monitor
        if iwconfig "$MON_IFACE" 2>/dev/null | grep -q "Mode:Monitor"; then
            ip link set "$MON_IFACE" down 2>/dev/null
            iw dev "$MON_IFACE" set type managed 2>/dev/null
            ip link set "$MON_IFACE" up 2>/dev/null
        fi
    fi

    # also try to restore original managed interface
    if [[ -n "$MANAGED_IFACE" ]]; then
        if iwconfig "$MANAGED_IFACE" 2>/dev/null | grep -q "Mode:Monitor"; then
            ip link set "$MANAGED_IFACE" down 2>/dev/null
            iw dev "$MANAGED_IFACE" set type managed 2>/dev/null
            ip link set "$MANAGED_IFACE" up 2>/dev/null
        fi
    fi

    log_success "Wireless interface restored."
}

# ======================================================================
#  RESTART NETWORK MANAGER
# ======================================================================
restart_network_manager() {
    log_info "Restarting NetworkManager..."

    # re-enable wifi radio
    nmcli radio wifi on 2>/dev/null

    # restart the service
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        systemctl restart NetworkManager 2>/dev/null &
        sleep 2
        log_success "NetworkManager restarted."
    else
        # try starting it
        systemctl start NetworkManager 2>/dev/null &
        sleep 2
        if systemctl is-active --quiet NetworkManager 2>/dev/null; then
            log_success "NetworkManager started."
        else
            log_warn "NetworkManager could not be started. You may need to reconnect manually."
        fi
    fi
}

# ======================================================================
#  CLEAN TEMPORARY FILES
# ======================================================================
clean_temp_files() {
    log_info "Cleaning temporary files..."

    local temp_patterns=(
        "/tmp/ghostap_*"
        "/tmp/evil_twin_*"
        "/tmp/*.csv"
        "/tmp/*.cap"
        "/tmp/*.netxml"
    )

    local removed=0
    for pattern in "${temp_patterns[@]}"; do
        # shellcheck disable=SC2086
        for file in $pattern; do
            if [[ -f "$file" ]] && [[ "$file" != *"*"* ]]; then
                rm -f "$file" 2>/dev/null
                removed=$((removed + 1))
            fi
        done
    done

    if [[ "$removed" -gt 0 ]]; then
        log_success "Removed ${removed} temporary file(s)."
    else
        log_info "No temporary files to clean."
    fi
}

# ======================================================================
#  RELEASE DHCP LEASES
# ======================================================================
release_dhcp_leases() {
    if [[ -f /var/lib/misc/dnsmasq.leases ]]; then
        log_info "Releasing dnsmasq DHCP leases..."
        > /var/lib/misc/dnsmasq.leases 2>/dev/null
    fi
}

# ======================================================================
#  FULL CLEANUP (orchestrator)
# ======================================================================
full_cleanup() {
    local silent="${1:-false}"

    if [[ "$silent" != "true" ]]; then
        echo ""
        section "CLEANUP & RESTORATION"
    fi

    local start_time
    start_time=$(date +%s)

    # phase 1: kill processes
    kill_attack_processes

    # phase 2: restore firewall
    restore_iptables

    # phase 3: restore interface
    restore_interface

    # phase 4: release DHCP
    release_dhcp_leases

    # phase 5: restart networking
    if [[ "${AUTO_CLEANUP:-true}" == "true" ]]; then
        restart_network_manager
    else
        log_info "Skipping NetworkManager restart (AUTO_CLEANUP=false)."
    fi

    # phase 6: clean temps
    clean_temp_files

    # phase 7: log session end
    log_session_end 2>/dev/null

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ "$silent" != "true" ]]; then
        echo ""
        log_success "Cleanup complete in ${duration}s."
        echo -e "  ${GRAY}All processes killed, iptables restored, interface reset.${NC}"
        echo ""
    fi
}

# ======================================================================
#  EMERGENCY CLEANUP (called on trap)
#  Silent, fast, no-frills — just kill everything
# ======================================================================
emergency_cleanup() {
    # kill everything immediately
    pkill -9 -x "hostapd" 2>/dev/null
    pkill -9 -x "dnsmasq" 2>/dev/null
    pkill -9 -x "aireplay-ng" 2>/dev/null
    pkill -9 -x "airodump-ng" 2>/dev/null
    pkill -9 -f "ghostap_portal.py" 2>/dev/null

    # flush iptables
    iptables --flush 2>/dev/null
    iptables --table nat --flush 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null

    # disable IP forwarding
    echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null

    # stop monitor mode
    airmon-ng stop "${MON_IFACE:-wlan0mon}" 2>/dev/null
    airmon-ng stop "${MANAGED_IFACE:-wlan0}" 2>/dev/null

    # restart network manager silently
    systemctl restart NetworkManager 2>/dev/null &

    # clean temp files
    rm -f /tmp/ghostap_* 2>/dev/null
    rm -f /tmp/evil_twin_* 2>/dev/null

    exit 0
}

# ======================================================================
#  CHECK CLEANUP STATUS
# ======================================================================
check_cleanup_status() {
    local issues=0

    echo ""
    echo -e "${CYAN}═══ Cleanup Status Check ═══${NC}"
    echo ""

    # check for lingering processes
    local lingering=()
    pgrep -x "hostapd" &>/dev/null && lingering+=("hostapd")
    pgrep -x "dnsmasq" &>/dev/null && lingering+=("dnsmasq")
    pgrep -x "aireplay-ng" &>/dev/null && lingering+=("aireplay-ng")
    pgrep -f "ghostap_portal.py" &>/dev/null && lingering+=("flask portal")

    if [[ ${#lingering[@]} -gt 0 ]]; then
        echo -e "  ${RED}✘${NC} Lingering processes: ${lingering[*]}"
        issues=$((issues + 1))
    else
        echo -e "  ${GREEN}✔${NC} No lingering processes"
    fi

    # check monitor mode
    local mon_ifaces
    mon_ifaces=$(iwconfig 2>/dev/null | grep -c "Mode:Monitor")
    if [[ "$mon_ifaces" -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠${NC} ${mon_ifaces} interface(s) still in monitor mode"
        issues=$((issues + 1))
    else
        echo -e "  ${GREEN}✔${NC} No monitor mode interfaces"
    fi

    # check iptables
    local ipt_rules
    ipt_rules=$(iptables -L -n 2>/dev/null | wc -l)
    if [[ "$ipt_rules" -gt 8 ]]; then
        echo -e "  ${YELLOW}⚠${NC} iptables has custom rules (${ipt_rules} lines)"
        issues=$((issues + 1))
    else
        echo -e "  ${GREEN}✔${NC} iptables looks clean"
    fi

    # check network manager
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        echo -e "  ${GREEN}✔${NC} NetworkManager is running"
    else
        echo -e "  ${RED}✘${NC} NetworkManager is NOT running"
        issues=$((issues + 1))
    fi

    echo ""
    if [[ "$issues" -eq 0 ]]; then
        log_success "System is clean. No issues detected."
    else
        log_warn "${issues} issue(s) found. Run full cleanup to fix."
    fi
}

# ======================================================================
#  END OF CLEANUP MODULE
# ======================================================================