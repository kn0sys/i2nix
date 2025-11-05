#!/bin/bash
#
# i2nix-workstation Setup Script
#
# This script automates the full configuration of the i2nix Workstation
# after a minimal Debian + XFCE installation.
#
# Run as root: sudo ./workstation-setup.sh
#

# TODO: Configure desktop environment

set -e

# --- Safety Check ---
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  exit 1
fi

echo "### Starting i2nix-workstation Configuration ###"

echo "[+] Installing core software..."

echo "[+] Downloading LibreWolf packages for Workstation..."
apt update -y
apt install -y curl
PACKAGE_DIR=/tmp/i2nix_install
mkdir -p $PACKAGE_DIR
LIBREWOLF_URL=https://ftp.gwdg.de/pub/opensuse/repositories/home%3A/bgstack15%3A/aftermozilla/Debian_Unstable/amd64/librewolf_142.0-1_amd64.deb
curl -o librewolf.deb $LIBREWOLF_URL
mv librewolf.deb $PACKAGE_DIR
LIBREOLF_GPG_URL=https://download.opensuse.org/repositories/home:/bgstack15:/aftermozilla/Debian_Unstable/Release.gpg
curl -o librewolf.gpg https://download.opensuse.org/repositories/home:/bgstack15:/aftermozilla/Debian_Unstable/Release.gpg
mv librewolf.gpg $PACKAGE_DIR
FIREJAIL_URL=https://netactuate.dl.sourceforge.net/project/firejail/firejail/firejail_0.9.74_1_amd64.deb?viasf=1
curl -o firejail.deb $FIREJAIL_URL
mv firejail.deb $PACKAGE_DIR
echo "[+] Packages ready for Workstation."

echo "[+] Installing and hardening LibreWolf..."
# Install
gpg --dearmor -o /usr/share/keyrings/librewolf.gpg $PACKAGE_DIR/librewolf.gpg
dpkg -i $PACKAGE_DIR/librewolf.deb || apt-get -f install -y
dpkg -i $PACKAGE_DIR/firejail.deb || apt-get -f install -y
rm -rf $PACKAGE_DIR

# Install desktop
tasksel
apt update -y
apt install -y jq lynx

# --- 1. Network Configuration ---
echo "[+] Configuring network interfaces..."
# IMPORTANT: Verify your interface name with `ip a`.
INTERNAL_IF=$(ip -j a | jq .[1].ifname | tr -d '"')

GATEWAY_IP=$1

cat <<EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Internal interface to the i2nix-gateway
auto $INTERNAL_IF
iface $INTERNAL_IF inet static
    address 10.152.152.11
    netmask 255.255.255.0
    gateway $GATEWAY_IP
EOF

# Configure DNS
echo "nameserver $GATEWAY_IP" > /etc/resolv.conf

echo "[+] Network interfaces configured."

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


# Set lynx http proxy
sh -c 'echo "http_proxy=http://10.152.152.10:8444" >> /etc/lynx/lynx.cfg'

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
      "HTTPProxy": "$GATEWAY_IP:8444",
      "SOCKSProxy": "$GATEWAY_IP:8667",
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

# Apply Kernel Hardening
echo "[+] Applying system hardening..."
cat <<EOF > /etc/sysctl.d/99-i2nix-hardening.conf
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.unprivileged_userns_clone=0
kernel.unprivileged_bpf_disabled=1
net.ipv4.tcp_syncookies=1
net.ipv4.icmp_echo_ignore_broadcasts=1
EOF
sysctl --system
 
# --- Final Steps ---
echo ""
echo "### i2nix-workstation Configuration COMPLETE ###"
echo "### It is highly recommended to REBOOT the system now. ###"

