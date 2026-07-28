#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Network Scanner & Target Selection Module
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Scans for WiFi networks, displays results,
#               handles target selection via interactive menu
# ======================================================================

# source dependencies
SCRIPT_DIR_SCANNER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${SCRIPT_DIR_SCANNER}/config/colors.sh" 2>/dev/null
source "${SCRIPT_DIR_SCANNER}/config/settings.conf" 2>/dev/null
source "${SCRIPT_DIR_SCANNER}/lib/logger.sh" 2>/dev/null
source "${SCRIPT_DIR_SCANNER}/lib/interface.sh" 2>/dev/null
source "${SCRIPT_DIR_SCANNER}/lib/utils.sh" 2>/dev/null

# ======================================================================
#  GLOBAL VARIABLES
# ======================================================================
declare -a SCAN_BSSIDS
declare -a SCAN_CHANNELS
declare -a SCAN_ESSIDS
declare -a SCAN_ENCRYPTIONS
declare -a SCAN_POWERS
declare -a SCAN_CLIENTS
SCAN_COUNT=0
SCAN_CSV_FILE=""

# ======================================================================
#  PARSE AIRODUMP CSV OUTPUT
#  Extracts networks with clients into arrays
#  Args: $1 = path to CSV file
#  Returns: populates global arrays, sets SCAN_COUNT
# ======================================================================
parse_scan_results() {
    local csv_file="$1"

    if [[ ! -f "$csv_file" ]]; then
        log_error "Scan CSV file not found: $csv_file"
        return 1
    fi

    # reset arrays
    SCAN_BSSIDS=()
    SCAN_CHANNELS=()
    SCAN_ESSIDS=()
    SCAN_ENCRYPTIONS=()
    SCAN_POWERS=()
    SCAN_CLIENTS=()
    SCAN_COUNT=0

    local bssid first_seen last_seen channel speed privacy cipher auth power beacons iv lan_ip id_length essid key
    local in_ap_section=false
    local client_count=0

    while IFS=',' read -r bssid first_seen last_seen channel speed privacy cipher auth power beacons iv lan_ip id_length essid key; do

        # detect AP section start
        if [[ "$bssid" == "BSSID" ]]; then
            in_ap_section=true
            continue
        fi

        # detect client section (end of APs)
        if [[ "$bssid" == "Station MAC" ]]; then
            in_ap_section=false
            continue
        fi

        # skip empty or invalid lines
        if [[ -z "$bssid" ]] || [[ "$bssid" == " "* ]]; then
            continue
        fi

        if [[ "$in_ap_section" == true ]]; then
            # validate BSSID format
            if [[ "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                # trim whitespace
                essid=$(echo "$essid" | xargs)
                privacy=$(echo "$privacy" | xargs)
                power=$(echo "$power" | xargs)
                channel=$(echo "$channel" | xargs)

                # skip hidden SSIDs if configured
                if [[ -z "$essid" ]] && [[ "${SCAN_ONLY_ENCRYPTED:-false}" == "true" ]]; then
                    continue
                fi

                # skip open networks if configured
                if [[ "$privacy" == "OPN" ]] && [[ "${SCAN_ONLY_ENCRYPTED:-false}" == "true" ]]; then
                    continue
                fi

                # count clients for this BSSID later
                client_count=0

                SCAN_COUNT=$((SCAN_COUNT + 1))
                SCAN_BSSIDS[$SCAN_COUNT]="$bssid"
                SCAN_CHANNELS[$SCAN_COUNT]="${channel:-?}"
                SCAN_ESSIDS[$SCAN_COUNT]="${essid:-<Hidden>}"
                SCAN_ENCRYPTIONS[$SCAN_COUNT]="${privacy:-?}"
                SCAN_POWERS[$SCAN_COUNT]="${power:--}"
            fi
        else
            # client section — count clients per BSSID
            if [[ -n "$bssid" ]]; then
                local client_bssid
                client_bssid=$(echo "$bssid" | xargs | awk '{print $1}')
                # increment client count for matching BSSID
                for ((i = 1; i <= SCAN_COUNT; i++)); do
                    if [[ "${SCAN_BSSIDS[$i]}" == "$client_bssid" ]]; then
                        SCAN_CLIENTS[$i]=$((${SCAN_CLIENTS[$i]:-0} + 1))
                    fi
                done
            fi
        fi
    done < "$csv_file"

    if [[ $SCAN_COUNT -eq 0 ]]; then
        log_warn "No networks found in scan results."
        return 1
    fi

    log_success "Parsed ${SCAN_COUNT} network(s) from scan data."
    return 0
}

# ======================================================================
#  DISPLAY SCAN RESULTS — COLOR-CODED TABLE
# ======================================================================
display_scan_results() {
    echo ""
    echo -e "${CYAN}${BOLD}═══ Available Networks ═══${NC}"
    echo ""
    
    # header
    printf "  ${WHITE}${BOLD}%-4s %-20s %-4s %-7s %-5s %-4s %s${NC}\n" \
        "#" "BSSID" "CH" "ENC" "PWR" "CL" "ESSID"
    printf "  ${GRAY}%-4s %-20s %-4s %-7s %-5s %-4s %s${NC}\n" \
        "────" "────────────────────" "────" "───────" "─────" "────" "────────────────────────"

    for ((i = 1; i <= SCAN_COUNT; i++)); do
        local bssid="${SCAN_BSSIDS[$i]}"
        local channel="${SCAN_CHANNELS[$i]}"
        local essid="${SCAN_ESSIDS[$i]}"
        local encryption="${SCAN_ENCRYPTIONS[$i]}"
        local power="${SCAN_POWERS[$i]}"
        local clients="${SCAN_CLIENTS[$i]:-0}"

        # color code encryption
        local enc_color="$GRAY"
        case "$encryption" in
            "WPA2"|"WPA3"|"CCMP") enc_color="$GREEN" ;;
            "WPA"|"WPA1") enc_color="$YELLOW" ;;
            "WEP") enc_color="$RED" ;;
            "OPN") enc_color="$CYAN" ;;
        esac

        # color code power
        local pwr_color="$GRAY"
        if [[ "$power" =~ ^-?[0-9]+$ ]]; then
            if [[ "$power" -ge -40 ]]; then pwr_color="$GREEN"
            elif [[ "$power" -ge -60 ]]; then pwr_color="$YELLOW"
            elif [[ "$power" -ge -80 ]]; then pwr_color="$RED"
            else pwr_color="$GRAY"
            fi
        fi

        # color code clients
        local cl_color="$GRAY"
        if [[ "$clients" -gt 5 ]]; then cl_color="$GREEN"
        elif [[ "$clients" -gt 0 ]]; then cl_color="$YELLOW"
        fi

        # truncate long ESSIDs
        local display_essid="$essid"
        if [[ ${#display_essid} -gt 25 ]]; then
            display_essid="${display_essid:0:22}..."
        fi

        printf "  ${GREEN}%-4s${NC} ${WHITE}%-20s${NC} ${YELLOW}%-4s${NC} ${enc_color}%-7s${NC} ${pwr_color}%-5s${NC} ${cl_color}%-4s${NC} ${CYAN}%s${NC}\n" \
            "$i" "$bssid" "$channel" "$encryption" "$power" "$clients" "$display_essid"
    done

    echo ""
    echo -e "  ${GRAY}ENC: OPN=Open | WEP=Weak | WPA/WPA2/WPA3=Encrypted${NC}"
    echo -e "  ${GRAY}PWR: Signal strength (higher = closer) | CL: Connected clients${NC}"
    echo ""
}

# ======================================================================
#  SORT NETWORKS BY SIGNAL STRENGTH (descending)
# ======================================================================
sort_by_power() {
    # bubble sort by power (descending)
    for ((i = 1; i <= SCAN_COUNT; i++)); do
        for ((j = i + 1; j <= SCAN_COUNT; j++)); do
            local pwr_i="${SCAN_POWERS[$i]:--100}"
            local pwr_j="${SCAN_POWERS[$j]:--100}"
            if [[ "$pwr_j" -gt "$pwr_i" ]]; then
                # swap all arrays
                local tmp
                tmp="${SCAN_BSSIDS[$i]}"; SCAN_BSSIDS[$i]="${SCAN_BSSIDS[$j]}"; SCAN_BSSIDS[$j]="$tmp"
                tmp="${SCAN_CHANNELS[$i]}"; SCAN_CHANNELS[$i]="${SCAN_CHANNELS[$j]}"; SCAN_CHANNELS[$j]="$tmp"
                tmp="${SCAN_ESSIDS[$i]}"; SCAN_ESSIDS[$i]="${SCAN_ESSIDS[$j]}"; SCAN_ESSIDS[$j]="$tmp"
                tmp="${SCAN_ENCRYPTIONS[$i]}"; SCAN_ENCRYPTIONS[$i]="${SCAN_ENCRYPTIONS[$j]}"; SCAN_ENCRYPTIONS[$j]="$tmp"
                tmp="${SCAN_POWERS[$i]}"; SCAN_POWERS[$i]="${SCAN_POWERS[$j]}"; SCAN_POWERS[$j]="$tmp"
                tmp="${SCAN_CLIENTS[$i]}"; SCAN_CLIENTS[$i]="${SCAN_CLIENTS[$j]}"; SCAN_CLIENTS[$j]="$tmp"
            fi
        done
    done
}

# ======================================================================
#  AUTO-SELECT STRONGEST NETWORK WITH CLIENTS
#  Returns: sets TARGET_BSSID, TARGET_ESSID, TARGET_CHANNEL
# ======================================================================
auto_select_target() {
    log_info "Auto-selecting strongest network with clients..."

    for ((i = 1; i <= SCAN_COUNT; i++)); do
        local clients="${SCAN_CLIENTS[$i]:-0}"
        if [[ "$clients" -ge "${SCAN_MIN_CLIENTS:-1}" ]]; then
            export TARGET_BSSID="${SCAN_BSSIDS[$i]}"
            export TARGET_ESSID="${SCAN_ESSIDS[$i]}"
            export TARGET_CHANNEL="${SCAN_CHANNELS[$i]}"
            log_success "Auto-selected: ${TARGET_ESSID} (${TARGET_BSSID})"
            return 0
        fi
    done

    # fallback: first network
    if [[ $SCAN_COUNT -gt 0 ]]; then
        export TARGET_BSSID="${SCAN_BSSIDS[1]}"
        export TARGET_ESSID="${SCAN_ESSIDS[1]}"
        export TARGET_CHANNEL="${SCAN_CHANNELS[1]}"
        log_warn "No networks with clients. Selected first: ${TARGET_ESSID}"
        return 0
    fi

    log_error "No networks available for auto-select."
    return 1
}

# ======================================================================
#  INTERACTIVE TARGET SELECTION
#  Returns: sets TARGET_BSSID, TARGET_ESSID, TARGET_CHANNEL
# ======================================================================
select_target() {
    local choice

    while true; do
        echo ""
        read -p "$(echo -e "${CYAN}[?] Select target number (1-${SCAN_COUNT}) or 'r' to rescan, 'q' to quit: ${NC}")" choice

        case "$choice" in
            [Qq])
                log_info "Target selection cancelled by user."
                return 1
                ;;
            [Rr])
                return 2  # signal to rescan
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le $SCAN_COUNT ]]; then
                    export TARGET_BSSID="${SCAN_BSSIDS[$choice]}"
                    export TARGET_ESSID="${SCAN_ESSIDS[$choice]}"
                    export TARGET_CHANNEL="${SCAN_CHANNELS[$choice]}"

                    echo ""
                    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
                    echo -e "${GREEN}${BOLD}║         TARGET LOCKED                ║${NC}"
                    echo -e "${GREEN}${BOLD}╠══════════════════════════════════════╣${NC}"
                    echo -e "${GREEN}${BOLD}║${NC}  ESSID   : ${YELLOW}${TARGET_ESSID}${GREEN}"
                    echo -e "${GREEN}${BOLD}║${NC}  BSSID   : ${YELLOW}${TARGET_BSSID}${GREEN}"
                    echo -e "${GREEN}${BOLD}║${NC}  Channel : ${YELLOW}${TARGET_CHANNEL}${GREEN}"
                    echo -e "${GREEN}${BOLD}║${NC}  Encrypt : ${YELLOW}${SCAN_ENCRYPTIONS[$choice]}${GREEN}"
                    echo -e "${GREEN}${BOLD}║${NC}  Clients : ${YELLOW}${SCAN_CLIENTS[$choice]:-0}${GREEN}"
                    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
                    echo ""

                    return 0
                else
                    log_error "Invalid selection. Enter 1-${SCAN_COUNT}."
                fi
                ;;
        esac
    done
}

# ======================================================================
#  PERFORM NETWORK SCAN
#  Args: $1 = monitor interface
#        $2 = scan duration in seconds (optional, default from config)
#  Returns: CSV file path via SCAN_CSV_FILE
# ======================================================================
perform_scan() {
    local mon_iface="$1"
    local duration="${2:-${SCAN_DURATION:-30}}"
    local scan_prefix="/tmp/ghostap_scan"

    if [[ -z "$mon_iface" ]]; then
        log_error "No monitor interface for scanning."
        return 1
    fi

    # set to hopping mode (scan all channels)
    set_channel 1 "$mon_iface" 2>/dev/null  # start at channel 1, airodump will hop

    log_info "Scanning for ${duration} seconds..."
    log_info "Close the xterm window to stop early, or wait for auto-stop."

    # clean previous scans
    rm -f "${scan_prefix}"*.csv 2>/dev/null
    rm -f "${scan_prefix}"*.cap 2>/dev/null

    if [[ "${SHOW_XTERM_WINDOWS:-true}" == "true" ]]; then
        # show scan in xterm
        xterm -T "GhostAP — Scanner [${duration}s]" \
              -geometry 100x30+100+200 \
              -fg "#00ff88" \
              -e "airodump-ng --band ${SCAN_BAND:-abg} -w ${scan_prefix} --output-format csv ${mon_iface}" &
        local scan_pid=$!

        # countdown
        for ((sec = duration; sec > 0; sec--)); do
            printf "\r  ${CYAN}⏳${NC} Scanning... ${YELLOW}%02d${NC}s remaining " "$sec"
            sleep 1
            # check if user closed xterm early
            if ! kill -0 "$scan_pid" 2>/dev/null; then
                echo ""
                log_info "Scan window closed. Parsing results..."
                break
            fi
        done

        # kill scan if still running
        if kill -0 "$scan_pid" 2>/dev/null; then
            kill "$scan_pid" 2>/dev/null
            sleep 0.5
            kill -9 "$scan_pid" 2>/dev/null
        fi
    else
        # silent scan
        airodump-ng --band "${SCAN_BAND:-abg}" \
                    -w "$scan_prefix" \
                    --output-format csv \
                    "$mon_iface" &>/dev/null &
        local scan_pid=$!
        sleep "$duration"
        kill "$scan_pid" 2>/dev/null
    fi

    echo ""
    log_success "Scan complete."

    # find the generated CSV
    SCAN_CSV_FILE=$(ls "${scan_prefix}"-01.csv 2>/dev/null | head -1)

    if [[ -z "$SCAN_CSV_FILE" ]]; then
        log_error "No scan output found. Check adapter and try again."
        return 1
    fi

    log_debug "Scan CSV: $SCAN_CSV_FILE"
    return 0
}

# ======================================================================
#  SHOW TARGET DETAILS (expanded view)
# ======================================================================
show_target_details() {
    local index="$1"

    if [[ -z "$index" ]] || [[ "$index" -lt 1 ]] || [[ "$index" -gt $SCAN_COUNT ]]; then
        log_error "Invalid target index."
        return 1
    fi

    echo ""
    echo -e "${CYAN}${BOLD}═══ Target Details ═══${NC}"
    echo ""
    echo -e "  ${GRAY}ESSID       :${NC} ${YELLOW}${SCAN_ESSIDS[$index]}${NC}"
    echo -e "  ${GRAY}BSSID       :${NC} ${WHITE}${SCAN_BSSIDS[$index]}${NC}"
    echo -e "  ${GRAY}Channel     :${NC} ${WHITE}${SCAN_CHANNELS[$index]}${NC}"
    echo -e "  ${GRAY}Encryption  :${NC} ${WHITE}${SCAN_ENCRYPTIONS[$index]}${NC}"
    echo -e "  ${GRAY}Power       :${NC} ${WHITE}${SCAN_POWERS[$index]} dBm${NC}"
    echo -e "  ${GRAY}Clients     :${NC} ${WHITE}${SCAN_CLIENTS[$index]:-0}${NC}"
    echo ""

    # determine band from channel
    local channel="${SCAN_CHANNELS[$index]}"
    if [[ "$channel" -le 14 ]]; then
        echo -e "  ${GRAY}Band        :${NC} ${CYAN}2.4 GHz${NC}"
    else
        echo -e "  ${GRAY}Band        :${NC} ${MAGENTA}5 GHz${NC}"
    fi

    echo ""
}

# ======================================================================
#  RUN FULL SCANNER WORKFLOW
#  1. Start monitor mode
#  2. Scan networks
#  3. Parse results
#  4. Display and select target
#  5. Returns target via global vars
# ======================================================================
run_scanner() {
    echo ""
    section "NETWORK SCANNER"

    # --- step 1: ensure monitor mode ---
    if [[ -z "$MON_IFACE" ]]; then
        log_info "Starting monitor mode..."
        if ! start_monitor_mode "$MANAGED_IFACE"; then
            log_error "Failed to enter monitor mode."
            return 1
        fi
    fi

    local mon_iface="$MON_IFACE"
    log_info "Monitor interface: $mon_iface"

    # --- step 2: scan loop (allows rescan) ---
    local scan_result
    while true; do
        # perform scan
        if ! perform_scan "$mon_iface" "${SCAN_DURATION:-30}"; then
            return 1
        fi

        # parse results
        if ! parse_scan_results "$SCAN_CSV_FILE"; then
            log_error "Failed to parse scan results."
            return 1
        fi

        # sort by signal strength
        sort_by_power

        # display
        display_scan_results

        # show summary stats
        echo -e "  ${GRAY}Total: ${WHITE}${SCAN_COUNT}${NC} network(s) found"
        local networks_with_clients=0
        for ((i = 1; i <= SCAN_COUNT; i++)); do
            if [[ "${SCAN_CLIENTS[$i]:-0}" -gt 0 ]]; then
                networks_with_clients=$((networks_with_clients + 1))
            fi
        done
        echo -e "  ${GRAY}With clients: ${GREEN}${networks_with_clients}${NC}"
        echo ""

        # auto-select if configured
        if [[ "${SCAN_AUTO_SELECT:-false}" == "true" ]]; then
            auto_select_target
            return 0
        fi

        # interactive selection
        select_target
        scan_result=$?

        case $scan_result in
            0) return 0 ;;  # target selected
            1) return 1 ;;  # user quit
            2) continue ;;   # rescan
        esac
    done
}

# ======================================================================
#  QUICK SCAN (shorter duration, returns first match with clients)
# ======================================================================
quick_scan() {
    local mon_iface="${1:-$MON_IFACE}"
    local duration="${2:-15}"

    if [[ -z "$mon_iface" ]]; then
        start_monitor_mode "$MANAGED_IFACE"
        mon_iface="$MON_IFACE"
    fi

    log_info "Quick scan (${duration}s)..."

    perform_scan "$mon_iface" "$duration"
    parse_scan_results "$SCAN_CSV_FILE"
    sort_by_power
    auto_select_target

    if [[ -n "$TARGET_BSSID" ]]; then
        log_success "Quick target: $TARGET_ESSID"
        return 0
    fi

    return 1
}

# ======================================================================
#  END OF SCANNER MODULE
# ======================================================================