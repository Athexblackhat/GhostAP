#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Utility Functions Library
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Helper functions used across all modules
# ======================================================================

# source dependencies
[[ -z "$RED" ]] && source "${SCRIPT_DIR}/../config/colors.sh" 2>/dev/null
[[ -z "$LOG_DIR" ]] && source "${SCRIPT_DIR}/../config/settings.conf" 2>/dev/null

# ======================================================================
#  DISPLAY GHOSTAP BANNER
# ======================================================================
show_banner() {
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
     Developer : ${TOOL_DEV:-ATHEX BLACK HAT}
     Version   : ${TOOL_VERSION:-1.0.0}
    ═══════════════════════════════════════════════════════════

BANNER
}

# ======================================================================
#  ROOT PRIVILEGE CHECK
# ======================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo ""
        echo -e "${RED}${BOLD}╔══════════════════════════════════════╗${NC}"
        echo -e "${RED}${BOLD}║     ROOT PRIVILEGES REQUIRED         ║${NC}"
        echo -e "${RED}${BOLD}╠══════════════════════════════════════╣${NC}"
        echo -e "${RED}${BOLD}║${NC}  Run: ${YELLOW}sudo bash GhostAP.sh${RED}${BOLD}         ║${NC}"
        echo -e "${RED}${BOLD}╚══════════════════════════════════════╝${NC}"
        echo ""
        exit 1
    fi
}

# ======================================================================
#  DEPENDENCY CHECK (ALL)
# ======================================================================
check_dependencies() {
    local missing=()

    local required_system=(
        "airmon-ng"
        "airodump-ng"
        "aireplay-ng"
        "hostapd"
        "dnsmasq"
        "python3"
        "xterm"
        "iptables"
    )

    local required_python=(
        "flask"
    )

    echo ""
    log_info "Checking system dependencies..."

    for cmd in "${required_system[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd (apt)")
        fi
    done

    log_info "Checking Python dependencies..."
    for pkg in "${required_python[@]}"; do
        if ! python3 -c "import $pkg" 2>/dev/null; then
            missing+=("python3-$pkg (pip)")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_error "Missing dependencies detected:"
        for dep in "${missing[@]}"; do
            echo -e "  ${RED}✘${NC} $dep"
        done
        echo ""
        echo -e "${YELLOW}Install with:${NC}"
        echo -e "  ${GRAY}sudo apt install aircrack-ng hostapd dnsmasq python3 python3-pip xterm iptables -y${NC}"
        echo -e "  ${GRAY}pip3 install flask${NC}"
        echo ""
        return 1
    fi

    log_success "All dependencies satisfied."
    return 0
}

# ======================================================================
#  SINGLE TOOL CHECK
# ======================================================================
check_tool() {
    local tool="$1"
    local install_hint="${2:-apt install $tool}"

    if command -v "$tool" &>/dev/null; then
        log_success "$tool found: $(which $tool)"
        return 0
    else
        log_error "$tool not found. Install: $install_hint"
        return 1
    fi
}

# ======================================================================
#  SYSTEM INFORMATION
# ======================================================================
get_system_info() {
    local os kernel arch user hostname

    os=$(cat /etc/os-release 2>/dev/null | grep -oP '(?<=PRETTY_NAME=").*' | tr -d '"' || echo "Unknown OS")
    kernel=$(uname -r)
    arch=$(uname -m)
    user=$(whoami)
    hostname=$(hostname)

    echo ""
    echo -e "${CYAN}═══ System Information ═══${NC}"
    echo ""
    echo -e "  ${GRAY}OS      ${NC}: ${WHITE}${os}${NC}"
    echo -e "  ${GRAY}Kernel  ${NC}: ${WHITE}${kernel}${NC}"
    echo -e "  ${GRAY}Arch    ${NC}: ${WHITE}${arch}${NC}"
    echo -e "  ${GRAY}User    ${NC}: ${WHITE}${user}${NC}"
    echo -e "  ${GRAY}Host    ${NC}: ${WHITE}${hostname}${NC}"
    echo ""
}

# ======================================================================
#  TEMPORARY FILE MANAGEMENT
# ======================================================================
create_temp() {
    local prefix="${1:-ghostap}"
    local temp_file

    temp_file=$(mktemp "/tmp/${prefix}_XXXXXX")

    if [[ -z "$temp_file" ]]; then
        log_error "Failed to create temporary file."
        return 1
    fi

    echo "$temp_file"
    return 0
}

create_temp_dir() {
    local prefix="${1:-ghostap}"
    local temp_dir

    temp_dir=$(mktemp -d "/tmp/${prefix}_XXXXXX")

    if [[ -z "$temp_dir" ]]; then
        log_error "Failed to create temporary directory."
        return 1
    fi

    echo "$temp_dir"
    return 0
}

cleanup_temps() {
    local pattern="${1:-ghostap}"
    local count

    count=$(ls /tmp/${pattern}_* 2>/dev/null | wc -l)
    rm -f /tmp/${pattern}_* 2>/dev/null

    if [[ "$count" -gt 0 ]]; then
        log_info "Cleaned ${count} temporary file(s)."
    fi
}

# ======================================================================
#  USER INTERACTION HELPERS
# ======================================================================
confirm_action() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        read -p "$(echo -e "${YELLOW}[?] ${prompt} (Y/n): ${NC}")" CONFIRM
        [[ ! "$CONFIRM" =~ ^[Nn]$ ]]
    else
        read -p "$(echo -e "${YELLOW}[?] ${prompt} (y/N): ${NC}")" CONFIRM
        [[ "$CONFIRM" =~ ^[Yy]$ ]]
    fi

    return $?
}

press_enter_to_continue() {
    local msg="${1:-Press Enter to continue...}"
    echo ""
    read -p "$(echo -e "${CYAN}[?] ${msg}${NC}")" _
}

# ======================================================================
#  VALIDATION FUNCTIONS
# ======================================================================
is_valid_bssid() {
    local bssid="$1"
    [[ "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]
    return $?
}

is_valid_channel() {
    local channel="$1"
    [[ "$channel" =~ ^[0-9]+$ ]] && [[ "$channel" -ge 1 ]] && [[ "$channel" -le 165 ]]
    return $?
}

is_valid_essid() {
    local essid="$1"
    [[ -n "$essid" ]] && [[ ${#essid} -le 32 ]]
    return $?
}

is_monitor_mode() {
    local iface="${1:-$MON_IFACE}"
    iwconfig "$iface" 2>/dev/null | grep -q "Mode:Monitor"
    return $?
}

# ======================================================================
#  SPINNER (for long operations)
# ======================================================================
spinner() {
    local pid="$1"
    local message="${2:-Processing}"
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    while kill -0 "$pid" 2>/dev/null; do
        for ((i = 0; i < ${#spinstr}; i++)); do
            printf "\r  ${CYAN}%s${NC} ${GRAY}%s...${NC}" "${spinstr:$i:1}" "$message"
            sleep "$delay"
        done
    done
    printf "\r  ${GREEN}✔${NC} %s ${GREEN}Done${NC}\n" "$message"
}

# ======================================================================
#  PROGRESS BAR
# ======================================================================
progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-30}"
    local label="${4:-}"

    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r  ${GRAY}%s${NC} ${CYAN}[${NC}" "$label"
    printf "%${filled}s" '' | tr ' ' '█'
    printf "%${empty}s" '' | tr ' ' '░'
    printf "${CYAN}]${NC} ${WHITE}%3d%%${NC}" "$percent"

    if [[ "$current" -eq "$total" ]]; then
        echo ""
    fi
}

# ======================================================================
#  STRING MANIPULATION
# ======================================================================
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

urlencode() {
    local string="$*"
    local length="${#string}"
    for ((i = 0; i < length; i++)); do
        local c="${string:$i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "%s" "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

# ======================================================================
#  FILE HELPERS
# ======================================================================
file_exists() {
    [[ -f "$1" ]]
    return $?
}

dir_exists() {
    [[ -d "$1" ]]
    return $?
}

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_debug "Created directory: $dir"
            return 0
        else
            log_error "Failed to create directory: $dir"
            return 1
        fi
    fi
    return 0
}

# ======================================================================
#  NETWORK HELPERS
# ======================================================================
get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

get_gateway_ip() {
    ip route 2>/dev/null | grep default | awk '{print $3}' | head -1
}

# ======================================================================
#  PROCESS MANAGEMENT
# ======================================================================
kill_process_safe() {
    local pid="$1"
    local name="${2:-process}"

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        sleep 0.5
        # force kill if still alive
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
        fi
        log_debug "Killed $name (PID: $pid)"
        return 0
    fi
    return 1
}

wait_for_process() {
    local pid="$1"
    local timeout="${2:-30}"

    local count=0
    while kill -0 "$pid" 2>/dev/null && [[ "$count" -lt "$timeout" ]]; do
        sleep 1
        count=$((count + 1))
    done

    if [[ "$count" -ge "$timeout" ]]; then
        log_warn "Process $pid did not finish within ${timeout}s."
        return 1
    fi

    return 0
}

# ======================================================================
#  END OF UTILITY LIBRARY
# ======================================================================