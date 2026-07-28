<p align="center">
  <img src="https://img.shields.io/badge/GhostAP-v1.0.0-e94560?style=for-the-badge&logo=ghost&logoColor=white" alt="GhostAP Version">
  <img src="https://img.shields.io/badge/Developer-ATHEX%20BLACK%20HAT-0a0a1a?style=for-the-badge" alt="Developer">
  <img src="https://img.shields.io/badge/License-MIT-00e676?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20Kali-40c4ff?style=for-the-badge&logo=linux&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Python-3.8%2B-ffaa00?style=for-the-badge&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/Bash-5.0%2B-495670?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash">
</p>

<br>

<p align="center">
  <a href="https://github.com/Athexblackhat/GhostAP"><img src="/Ghost-AP.png" alt="0" border="0" /></a>
</p>

<br>
<br>

<p align="center">
  <b>Automated Evil Twin Attack Framework</b><br>
  <i>"The ghost in the network — unseen, undeniable."</i>
</p>

<br>

---

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-usage">Usage</a> •
  <a href="#-attack-workflow">Attack Workflow</a> •
  <a href="#-project-structure">Structure</a> •
  <a href="#-requirements">Requirements</a> •
  <a href="#-configuration">Configuration</a> •
  <a href="#-modules">Modules</a> •
  <a href="#-screenshots">Screenshots</a> •
  <a href="#-disclaimer">Disclaimer</a> •
  <a href="#-developer">Developer</a>
</p>

---

## 📖 Overview

**GhostAP** is a fully automated Evil Twin attack framework designed for WiFi security auditing and penetration testing. It scans for wireless networks, deauthenticates clients from the target access point, spawns a cloned fake AP with an identical SSID, and presents a captive portal that harvests the WiFi password — all through an interactive menu-driven interface.

**One command. Zero manual steps. Total automation.**

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔍 **Live Network Scanner** | Real-time airodump-ng scanning with color-coded signal strength, encryption type, and connected client count |
| 🎯 **Interactive Target Selection** | Numbered menu to pick target network — or auto-select the strongest AP with clients |
| 💥 **Deauth Attack** | Continuous or burst deauthentication flood to disconnect all clients from the target AP |
| 📡 **Fake Access Point** | Cloned SSID on the same channel via hostapd — indistinguishable from the real network |
| 🕸️ **Captive Portal** | Flask-based phishing page styled as a router firmware update, with full CSS theming |
| 🔑 **Credential Harvesting** | Captures WiFi passwords in real-time, logs to file with timestamp and victim IP |
| 🧹 **Graceful Cleanup** | Kills all processes, flushes iptables, restores monitor mode, restarts NetworkManager |
| 🎨 **Professional UI** | ASCII banner, color-coded output, xterm process windows, progress indicators |
| ⚙️ **Highly Configurable** | Central `settings.conf` file controls every aspect of the attack |
| 🧩 **Modular Architecture** | Separate modules for scanner, deauth, fake AP, portal, and cleanup |

---

## 📦 Installation

### 1. Clone the Repository
```
git clone https://github.com/Athexblackhat/GhostAP.git
cd GhostAP
```
### Install System Dependencies
```
sudo apt update
sudo apt install aircrack-ng hostapd dnsmasq python3 python3-pip xterm iptables net-tools wireless-tools -y
```
### Install Python Dependencies
```
pip3 install flask
```

### Verify Installation
```
sudo bash GhostAP.sh --version
```
## 🚀 Usage

### Interactive Mode (Recommended)
```
sudo bash GhostAP.sh
```
- Follow the on-screen menu:

1. Select Scan & Select Target to find networks

2. Pick a target from the numbered list

3. Confirm to launch the full attack chain

4. Wait for password capture

5. Press Enter to cleanup and exit

## Command-Line Flags
Flag        :      	Description
- -h,         :       --help	Display help information
- -v,         :      --version	Show version and developer info
- -s,         :     --scan-only	Scan networks and exit after selection
- -a,         :    --auto	Auto-select strongest network with clients and attack
 
## Examples
#### Full interactive session
```
sudo bash GhostAP.sh
```

#### Quick scan only
```
sudo bash GhostAP.sh -s
```


## 🔧 Requirements

### Hardware

| Component | Minimum | Recommended |
| --- | --- | --- |
| Wireless Adapter | Any with monitor mode + packet injection | Alfa AWUS036ACH / TP-Link WN722N v1 |
| Chipset Support | Realtek RTL8812AU / Atheros AR9271 | Mediatek MT7612U |
| RAM | 512 MB | 2+ GB |
| Storage | 50 MB free | 100+ MB free |

### Software

| Package | Version | Purpose |
| --- | --- | --- |
| `aircrack-ng` | ≥ 1.6 | Monitor mode, scanning, deauth |
| `hostapd` | ≥ 2.9 | Fake access point |
| `dnsmasq` | ≥ 2.80 | DHCP + DNS server |
| `python3` | ≥ 3.8 | Captive portal backend |
| `flask` | ≥ 2.0 | Web framework |
| `xterm` | latest | Parallel process display |
| `iptables` | latest | Traffic redirection |

### Operating System

| OS | Status |
| --- | --- |
| Kali Linux | ✅ Fully Supported |
| Parrot OS | ✅ Fully Supported |
| Ubuntu 20.04+ | ✅ Supported |
| Debian 11+ | ✅ Supported |
| Arch Linux | ⚠️ Manual dependency install |
| Termux (Android) | ❌ Not Supported |

## ⚙️ Configuration
***All settings are centralized in config/settings.conf. Key options:***

1. Scan duration in seconds
- SCAN_DURATION=30

2. Deauth packet count (0 = infinite)
- DEAUTH_PACKETS=0

3. Captive portal port
- PORTAL_PORT=80

4. DHCP settings
- DHCP_GATEWAY="10.0.0.1"
- DHCP_RANGE_START="10.0.0.50"
- DHCP_RANGE_END="10.0.0.150"

5. Portal branding
- PORTAL_COMPANY="NETGEAR"
- PORTAL_TITLE="Router Security Update"
- PORTAL_THEME_COLOR="#e94560"

6. Auto-select strongest network
- SCAN_AUTO_SELECT=false


## 🔮 Future Features
- □ PMKID capture and hashcat integration
- □ Bettercap-based advanced MITM module
- □ WPA3 transition mode downgrade attack
- □ HTML/PDF report generation
- □ Multiple language portal templates
- □ OAuth / social login phishing templates
- □ Discord/SMS webhook notifications on capture
- □ GPS-based wardriving log support
- □ Docker containerized deployment
## 👤 Developer
<p align="center"> <b>ATHEX BLACK HAT</b><br> <i>Cybersecurity Researcher • Penetration Tester • Tool Developer</i> </p><p align="center"> <a href="https://github.com/athex-blackhat"> <img src="https://img.shields.io/badge/GitHub-athex--blackhat-0a0a1a?style=for-the-badge&logo=github" alt="GitHub"> </a> &nbsp; <a href="https://t.me/athex_blackhat"> <img src="https://img.shields.io/badge/Telegram-%40athex__blackhat-40c4ff?style=for-the-badge&logo=telegram" alt="Telegram"> </a> &nbsp; <a href="mailto:athex.blackhat@proton.me"> <img src="https://img.shields.io/badge/Email-athex.blackhat%40proton.me-e94560?style=for-the-badge&logo=protonmail" alt="Email"> </a> </p>


## 📄 License
```
MIT License

Copyright (c) 2026 ATHEX BLACK HAT

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
<p align="center"> <b>GhostAP v1.0.0</b><br> <i>Developer: ATHEX BLACK HAT</i><br> <i>Made with ❤️ and H0T T34</i> </p>
<p align="center"> <samp>"The ghost in the network — unseen, undeniable."</samp> </p> ```
