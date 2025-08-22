#!/bin/bash
#
# i2nix-workstation Setup Script
#
# This script automates the full configuration of the i2nix Workstation
# after a minimal Debian + XFCE installation.
#
# Run as root: sudo ./workstation-setup.sh
#

set -e

# --- Safety Check ---
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  exit 1
fi

echo "### Starting i2nix-workstation Configuration ###"

echo "### Installing XFCE Desktop###"
apt-get install -y task-xfce-desktop

# --- 1. Network Configuration ---
echo "[+] Configuring network interfaces..."
# IMPORTANT: Verify your interface name with `ip a`.
INTERNAL_IF=$(ip -j a | jq .[1].ifname)

cat <<EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Internal interface to the i2nix-gateway
auto $INTERNAL_IF
iface $INTERNAL_IF inet static
    address 10.152.152.11
    netmask 255.255.255.0
    gateway 10.152.152.10
EOF

# Configure DNS
echo "nameserver 10.152.152.10" > /etc/resolv.conf

systemctl restart networking
echo "[+] Network interfaces configured."

# --- 2. System Hardening ---
echo "[+] Applying system hardening..."
# Kernel Hardening
cat <<EOF > /etc/sysctl.d/99-i2nix-hardening.conf
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.unprivileged_userns_clone=0
kernel.unprivileged_bpf_disabled=1
net.ipv4.tcp_syncookies=1
net.ipv4.icmp_echo_ignore_broadcasts=1
EOF
sysctl --system

# Time Sync Script
cat <<'EOF' > /usr/local/bin/i2nix-timesync.sh
#!/bin/bash
DATE_HEADER=$(curl -sSL --head "https://www.google.com" | grep -i '^date:' | sed 's/Date: //i' | tr -d '\r')
if [ -n "$DATE_HEADER" ]; then
    echo "Successfully fetched time: $DATE_HEADER"
    date -u --set="$DATE_HEADER"
else
    echo "Error: Failed to fetch time."
fi
EOF
chmod +x /usr/local/bin/i2nix-timesync.sh
echo "[+] System hardening applied."

# --- 3. Install Software ---
echo "[+] Installing core software...

echo "[+] Fetching LibreWolf and Firejail from Gateway..."
mkdir -p /tmp/i2nix_install
wget http://10.152.152.10:8000/librewolf.deb
mv librewolf.deb /tmp/i2nix_install
wget http://10.152.152.10:8000/librewolf.gpg
mv librewolf.gpg /tmp/i2nix_install
wget http://10.152.152.10:8000/firejail.deb
mv firejail.deb /tmp/i2nix_install
echo "[+] Packages fetched."

echo "[+] Installing and hardening LibreWolf..."
# Install
gpg --dearmor -o /usr/share/keyrings/librewolf.gpg /tmp/i2nix_install/librewolf.gpg
dpkg -i /tmp/i2nix_install/librewolf.deb || apt-get -f install -y
rm -rf /tmp/i2nix_install

# Create system-wide policies for hardening (the professional way)
mkdir -p /etc/librewolf/policies/
cat <<EOF > /etc/librewolf/policies/policies.json
{
  "policies": {
    "DisableFirefoxStudies": true,
    "DisableTelemetry": true,
    "DisablePocket": true,
    "DisableFirefoxAccounts": true,
    "NetworkPrediction": false,
    "DisableFeedbackCommands": true,
    "DNSOverHTTPS": {
        "Enabled": false
    },
    "Homepage": {
      "StartPage": "homepage",
      "URL": "http://stats.i2p"
    },
    "Proxy": {
      "Mode": "manual",
      "Locked": true,
      "HTTPProxy": "10.152.152.10:4444",
      "SOCKSProxy": "10.152.152.10:7667",
      "SOCKSVersion": 5,
      "UseSOCKSProxyForAllProtocols": false,
      "ProxyDNS": true
    },
    "Preferences": {
        "privacy.resistFingerprinting": { "Value": true, "Status": "locked" },
        "webgl.disabled": { "Value": true, "Status": "locked" },
        "media.peerconnection.enabled": { "Value": false, "Status": "locked" },
        "privacy.firstparty.isolate": { "Value": true, "Status": "locked" }
    }
  }
}
EOF

# Create system-wide override for Firejail integration
mkdir -p /usr/local/share/applications
cat <<EOF > /usr/local/share/applications/librewolf.desktop
[Desktop Entry]
Name=LibreWolf (Sandboxed)
Exec=firejail librewolf %u
Comment=Sandboxed private web browser
Icon=librewolf
Type=Application
Categories=Network;WebBrowser;
EOF

# Set Hardened Librewolf as default browser
xdg-settings set default-web-browser librewolf.desktop

echo "[+] LibreWolf installed and hardened."

# --- Final Steps ---
echo ""
echo "### i2nix-workstation Configuration COMPLETE ###"
echo "### It is highly recommended to REBOOT the system now. ###"
