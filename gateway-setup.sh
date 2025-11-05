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
apt update -y
apt install -y jq
# IMPORTANT: Verify your interface names with `ip a`.
# enp1s0 = External (NAT/Bridged), enp7s0 = Internal (i2nix)
EXTERNAL_IF=$(ip -j a | jq .[1].ifname | tr -d '"')
INTERNAL_IF=$(ip -j a | jq .[2].ifname | tr -d '"')

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

# Define firewall variables
I2NIX_WORKSTATION_IP=10.152.152.11
I2P_DNS_PORT="7653"
I2P_HTTP_PROXY_PORT="8444"
I2P_SOCKS_PROXY_PORT="8667"
I2P_TRANS_PORT="7654" # I2P's default transparent proxy port

# --- 2. I2P Installation ---
echo "[+] Installing I2P..."
apt-get update
apt-get install -y apt-transport-https curl wget gpg

wget -q -O - https://repo.i2pd.xyz/.help/add_repo | sudo bash -s -

apt update -y
apt install -y i2pd
systemctl enable i2pd
echo "[+] i2pd installed."

# --- 3. Firewall and Transparent Proxying ---
echo "[+] Configuring I2P and Firewall..."
# Auto-configure I2P proxies to listen on the internal interface
# This is a bit of a hack, assumes the user-specific config file exists after first run.
# A more robust solution might use I2P's config update mechanisms.
sleep 15 # Give I2P time to start and create initial configs
I2P_CONFIG_DIR="/etc/i2pd"
mkdir -p $I2P_CONFIG_DIR
touch "$I2P_CONFIG_DIR/tunnels.conf"
cat <<EOF > $I2P_CONFIG_DIR/'tunnels.conf'
[httpproxy]
type = httpproxy
address = $GATEWAY_INTERNAL_IP
port = $I2P_HTTP_PROXY_PORT
keys = http-keys.dat

[alt-socks]
type = socks
address = $GATEWAY_INTERNAL_IP
port = $I2P_SOCKS_PROXY_PORT
keys = socks-keys.dat 
EOF

# Install and configure iptables
# Pre-seed debconf to auto-accept iptables-persistent prompts
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
apt-get install -y iptables-persistent

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

# Allow workstation access to I2P proxies
apt update -y
apt install -y ufw
ufw enable
ufw allow from $I2NIX_WORKSTATION_IP to any port $I2P_HTTP_PROXY_PORT
ufw allow from $I2NIX_WORKSTATION_IP to any port $I2P_SOCKS_PROXY_PORT
ufw status

echo "[+] Firewall configured and enabled."

echo "### i2nix-gateway Configuration COMPLETE ###"

