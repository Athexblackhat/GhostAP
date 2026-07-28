#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Color Definitions Library
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Terminal color variables for consistent UI styling
# ======================================================================

# ======================================================================
#  REGULAR COLORS
# ======================================================================
export BLACK='\033[0;30m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[0;37m'
export GRAY='\033[0;90m'

# ======================================================================
#  BOLD COLORS
# ======================================================================
export BBLACK='\033[1;30m'
export BRED='\033[1;31m'
export BGREEN='\033[1;32m'
export BYELLOW='\033[1;33m'
export BBLUE='\033[1;34m'
export BMAGENTA='\033[1;35m'
export BCYAN='\033[1;36m'
export BWHITE='\033[1;37m'

# ======================================================================
#  UNDERLINE COLORS
# ======================================================================
export UBLACK='\033[4;30m'
export URED='\033[4;31m'
export UGREEN='\033[4;32m'
export UYELLOW='\033[4;33m'
export UBLUE='\033[4;34m'
export UMAGENTA='\033[4;35m'
export UCYAN='\033[4;36m'
export UWHITE='\033[4;37m'

# ======================================================================
#  BACKGROUND COLORS
# ======================================================================
export BG_BLACK='\033[40m'
export BG_RED='\033[41m'
export BG_GREEN='\033[42m'
export BG_YELLOW='\033[43m'
export BG_BLUE='\033[44m'
export BG_MAGENTA='\033[45m'
export BG_CYAN='\033[46m'
export BG_WHITE='\033[47m'
export BG_GRAY='\033[100m'

# ======================================================================
#  HIGH INTENSITY BACKGROUNDS
# ======================================================================
export BG_BRED='\033[101m'
export BG_BGREEN='\033[102m'
export BG_BYELLOW='\033[103m'
export BG_BBLUE='\033[104m'
export BG_BMAGENTA='\033[105m'
export BG_BCYAN='\033[106m'
export BG_BWHITE='\033[107m'

# ======================================================================
#  RESET
# ======================================================================
export NC='\033[0m'        # No Color / Reset All
export BOLD='\033[1m'      # Bold
export DIM='\033[2m'       # Dim
export UNDERLINE='\033[4m' # Underline
export BLINK='\033[5m'     # Blink
export REVERSE='\033[7m'   # Reverse / Invert
export HIDDEN='\033[8m'    # Hidden

# ======================================================================
#  STATUS PREFIX ICONS (colored)
# ======================================================================
export ICON_SUCCESS="${GREEN}[✔]${NC}"
export ICON_ERROR="${RED}[✘]${NC}"
export ICON_WARN="${YELLOW}[⚠]${NC}"
export ICON_INFO="${CYAN}[ℹ]${NC}"
export ICON_WAIT="${MAGENTA}[…]${NC}"
export ICON_LOCK="${RED}[🔒]${NC}"
export ICON_KEY="${YELLOW}[🔑]${NC}"
export ICON_TARGET="${RED}[◎]${NC}"
export ICON_GHOST="${WHITE}[👻]${NC}"

# ======================================================================
#  STYLED MESSAGE FUNCTIONS
# ======================================================================

# success message
msg_success() { echo -e "${ICON_SUCCESS} ${GREEN}$*${NC}"; }

# error message
msg_error() { echo -e "${ICON_ERROR} ${RED}$*${NC}"; }

# warning message
msg_warn() { echo -e "${ICON_WARN} ${YELLOW}$*${NC}"; }

# info message
msg_info() { echo -e "${ICON_INFO} ${CYAN}$*${NC}"; }

# highlight a value
highlight() { echo -e "${YELLOW}$*${NC}"; }

# banner text
banner_text() { echo -e "${BOLD}${WHITE}$*${NC}"; }

# ======================================================================
#  SPECIAL FORMATTING
# ======================================================================

# horizontal rule
hr() {
    printf "${GRAY}%*s${NC}\n" "$(tput cols)" '' | tr ' ' '─'
}

# section header
section() {
    echo ""
    echo -e "${BOLD}${WHITE}═══ $* ═══${NC}"
    echo ""
}

# key-value pair display
kv() {
    local key="$1"
    local value="$2"
    printf "  ${GRAY}%-14s${NC} ${WHITE}%s${NC}\n" "$key" "$value"
}

# ======================================================================
#  GHOSTAP THEME PRESETS
# ======================================================================
export THEME_PRIMARY="$CYAN"
export THEME_SECONDARY="$MAGENTA"
export THEME_ACCENT="$RED"
export THEME_SUCCESS="$GREEN"
export THEME_WARNING="$YELLOW"
export THEME_TEXT="$WHITE"
export THEME_MUTED="$GRAY"
export THEME_HIGHLIGHT="$BYELLOW"

# ======================================================================
#  END OF COLORS LIBRARY
# ======================================================================