#!/bin/bash
#
# i2nix-gateway Setup Script
#
# This script automates the full configuration of the i2nix gateway
# after a minimal Debian installation.
#
# Run as root: sudo ./gateway-setup.sh
#
GATEWAY_INTERNAL_IP="10.152.152.10"

set -e

# --- Safety Check ---
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  exit 1
fi

echo "### Starting i2nix-gateway Configuration ###"

# --- 1. Network Configuration ---
echo "[+] Configuring network interfaces..."
apt-get install -y jq
# IMPORTANT: Verify your interface names with `ip a`.
# enp1s0 = External (NAT/Bridged), enp7s0 = Internal (i2nix)
EXTERNAL_IF=$(ip -j a | jq .[1].ifname)
INTERNAL_IF=$(ip -j a | jq .[2].ifname)

cat <<EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback

# External interface
allow-hotplug $EXTERNAL_IF
iface $EXTERNAL_IF inet dhcp

# Internal interface for i2nix-workstation
auto $INTERNAL_IF
iface $INTERNAL_IF inet static
    address $GATEWAY_INTERNAL_IP
    netmask 255.255.255.0
EOF

systemctl restart networking
echo "[+] Network interfaces configured."

# --- 2. I2P Installation ---
echo "[+] Installing I2P..."
apt-get update
apt-get install -y apt-transport-https curl gpg

curl -o /tmp/i2p-repo-key.asc https://geti2p.net/_static/i2p-archive-keyring.gpg
gpg --dearmor -o /usr/share/keyrings/i2p-archive-keyring.gpg /tmp/i2p-repo-key.asc
echo "deb [signed-by=/usr/share/keyrings/i2p-archive-keyring.gpg] https://deb.i2p.net/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/i2p.list

apt-get update
apt-get install -y i2p i2p-keyring
systemctl enable i2p
echo "[+] I2P installed."

# --- 3. Firewall and Transparent Proxying ---
echo "[+] Configuring I2P and Firewall..."
# Auto-configure I2P proxies to listen on the internal interface
# This is a bit of a hack, assumes the user-specific config file exists after first run.
# A more robust solution might use I2P's config update mechanisms.
sleep 15 # Give I2P time to start and create initial configs
I2P_USER=$(ps -o user= -p $(pidof java)) # Find the user I2P is running as
I2P_CONFIG_DIR="/home/$I2P_USER/.i2p"
cat <<EOF > $I2P_CONFIG_DIR/'00-I2P HTTP Proxy-i2ptunnel.config'
# NOTE: This I2P config file must use UTF-8 encoding
# Last saved: $(date --utc)
configFile=/home/user/.i2p/i2ptunnel.config.d/00-I2P HTTP Proxy-i2ptunnel.config
description=HTTP proxy for browsing eepsites and the web
i2cpHost=127.0.0.1
i2cpPort=7654
interface=$GATEWAY_INTERNAL_IP
listenPort=4444
name=I2P HTTP Proxy
option.i2cp.leaseSetEncType=4,0
option.i2cp.reduceIdleTime=900000
option.i2cp.reduceOnIdle=true
option.i2cp.reduceQuantity=1
option.i2p.streaming.connectDelay=1000
option.i2ptunnel.httpclient.SSLOutproxies=exit.storymcloud.i2p
option.inbound.length=3
option.inbound.lengthVariance=0
option.inbound.nickname=shared clients
option.outbound.length=3
option.outbound.lengthVariance=0
option.outbound.nickname=shared clients
option.outbound.priority=10
proxyList=exit.stormycloud.i2p
sharedClient=true
startOnLoad=true
type=httpclient
EOF

# Install and configure iptables
# Pre-seed debconf to auto-accept iptables-persistent prompts
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
apt-get install -y iptables-persistent

# Define firewall variables
I2NIX_WORKSTATION="10.152.152.11"
I2P_DNS_PORT="7653"
I2P_TRANS_PORT="7654" # I2P's default transparent proxy port

# Apply rules
iptables -F
iptables -t nat -F
iptables -P FORWARD DROP

# NAT Table redirection
iptables -t nat -A PREROUTING -i $INTERNAL_IF -p udp --dport 53 -j DNAT --to $GATEWAY_INTERNAL_IP:$I2P_DNS_PORT
iptables -t nat -A PREROUTING -i $INTERNAL_IF -p tcp --dport 53 -j DNAT --to $GATEWAY_INTERNAL_IP:$I2P_DNS_PORT
iptables -t nat -A PREROUTING -i $INTERNAL_IF -p tcp --syn -j DNAT --to $GATEWAY_INTERNAL_IP:$I2P_TRANS_PORT

# Filter Table forwarding
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i $INTERNAL_IF -d $GATEWAY_INTERNAL_IP -j ACCEPT

# Save the rules to make them persistent
netfilter-persistent save
echo "[+] Firewall configured and enabled."

# --- 4. Prepare Packages for Workstation ---
echo "[+] Downloading LibreWolf packages for Workstation..."
mkdir -p /opt/i2nix_packages
LIBREWOLF_URL=https://ftp.gwdg.de/pub/opensuse/repositories/home%3A/bgstack15%3A/aftermozilla/Debian_Unstable/amd64/librewolf_139.0-1_amd64.deb
curl -o librewolf.deb $LIBREWOLF_URL
LIBREOLF_GPG_URL=https://download.opensuse.org/repositories/home:/bgstack15:/aftermozilla/Debian_Unstable/Release.gpg
curl -o librewolf.gpg https://download.opensuse.org/repositories/home:/bgstack15:/aftermozilla/Debian_Unstable/Release.gpg
FIREJAIL_URL=https://netactuate.dl.sourceforge.net/project/firejail/firejail/firejail_0.9.74_1_amd64.deb?viasf=1
curl -o firejail.deb $FIREJAIL_URL
echo "[+] Packages ready for Workstation."

LIBREWOLF_SHARE=/opt/i2nix-packages/

mkdir -p $LIBREWOLF_SHARE

cp librewolf.deb $LIBREWOLF_SHARE
cp librewolf.gpg $LIBREWOLF_SHARE
cp firejail.deb $LIBREWOLF_SHARE

# --- 5. Start a temporary web server to serve files to Workstation ---
echo "[+] Starting temporary web server on port 8000..."
echo "--> On the Workstation, run the setup script. It will pull files from here."

# Kill the webserver used to pull Librewolf to Workstation after 5 minutes.
(cd /opt/i2nix_packages && timeout 5m python3 -m http.server 8000) &

echo "### i2nix-gateway Configuration COMPLETE ###"
echo "### The web server will automatically shut down in 5 minutes. ###"
