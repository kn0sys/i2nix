#!/usr/bin/env bash
# Automates the creation of i2nix-gateway and i2nix-workstation in Qubes OS dom0

set -e

# Define Fedora template version
FEDORA_VER="43"
BASE_TEMPLATE="fedora-${FEDORA_VER}-xfce"
GW_TEMPLATE="i2nix-gateway-f${FEDORA_VER}"
WS_TEMPLATE="i2nix-workstation-f${FEDORA_VER}"

echo "=================================================="
echo " Starting i2nix Qubes Build Automation"
echo "=================================================="

# Check if base template exists
if ! qvm-check "$BASE_TEMPLATE" &>/dev/null; then
    echo "Error: Base template $BASE_TEMPLATE does not exist. Please install it first."
    exit 1
fi

# --------------------------------------------------------
# 1. i2nix-gateway configuration
# --------------------------------------------------------
echo "==> Cloning $BASE_TEMPLATE to $GW_TEMPLATE..."
qvm-clone "$BASE_TEMPLATE" "$GW_TEMPLATE"

echo "==> Installing i2pd in $GW_TEMPLATE..."
# Using bash heredoc through qvm-run to execute multiple commands in the template
qvm-run --pass-io -u root "$GW_TEMPLATE" bash -s << 'EOF'
dnf update -y
dnf copr enable supervillain/i2pd -y
dnf install i2pd -y
systemctl enable i2pd

# Append POP3 and SMTP tunnels to configuration rather than relying on brittle sed uncommenting
cat <<TUNNELS >> /etc/i2pd/tunnels.conf

[POP3]
type = client
address = 127.0.0.1
port = 7660
destination = pop3.postman.i2p
keys = pop3.dat

[SMTP]
type = client
address = 127.0.0.1
port = 7659
destination = smtp.postman.i2p
keys = smtp.dat
TUNNELS
EOF

echo "==> Shutting down $GW_TEMPLATE..."
qvm-shutdown "$GW_TEMPLATE" --wait

echo "==> Creating ProxyVM: sys-i2nix..."
qvm-create --class AppVM --template "$GW_TEMPLATE" --label red sys-i2nix
qvm-prefs sys-i2nix provides_network true
qvm-prefs sys-i2nix netvm sys-firewall
qvm-service sys-i2nix network-manager on

echo "==> Enabling Simple Port Binding in dom0..."
POLICY_FILE="/etc/qubes/policy.d/30-user-networking.policy"
if ! grep -q "anon-i2nix @default allow target=sys-i2nix" "$POLICY_FILE" 2>/dev/null; then
    echo "qubes.ConnectTCP * anon-i2nix @default allow target=sys-i2nix" | sudo tee -a "$POLICY_FILE"
    echo "Port binding policy added to $POLICY_FILE"
fi

# --------------------------------------------------------
# 2. i2nix-workstation configuration
# --------------------------------------------------------
echo "==> Cloning $BASE_TEMPLATE to $WS_TEMPLATE..."
qvm-clone "$BASE_TEMPLATE" "$WS_TEMPLATE"

echo "==> Installing software and configuring Firefox in $WS_TEMPLATE..."
# We apply the Firefox policies directly to the template so they persist for all AppVMs derived from it
qvm-run --pass-io -u root "$WS_TEMPLATE" bash -s << 'EOF'
dnf install -y firejail

mkdir -p /etc/firefox/policies/
cat <<POLICIES > /etc/firefox/policies/policies.json
{
  "policies": {
    "DisableFirefoxStudies": true,
    "DisableTelemetry": true,
    "DisablePocket": true,
    "DisableFirefoxAccounts": true,
    "NetworkPrediction": false,
    "DisableFeedbackCommands": true,
    "HttpsOnlyMode": "disallowed",
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
      "HTTPProxy": "127.0.0.1:4444",
      "UseHTTPProxyForAllProtocols": true,
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
POLICIES

mkdir -p /usr/local/share/applications
cat <<DESKTOP > /usr/local/share/applications/firefox.desktop
[Desktop Entry]
Name=Firefox (Sandboxed)
Exec=firejail firefox %u
Comment=Sandboxed private web browser
Icon=firefox
Type=Application
Categories=Network;WebBrowser;
DESKTOP
EOF

echo "==> Shutting down $WS_TEMPLATE..."
qvm-shutdown "$WS_TEMPLATE" --wait

echo "==> Creating AppVM: anon-i2nix..."
qvm-create --class AppVM --template "$WS_TEMPLATE" --label red anon-i2nix
qvm-prefs anon-i2nix netvm sys-i2nix

echo "==> Starting anon-i2nix to configure persistent AppVM settings..."
qvm-start anon-i2nix
qvm-run --pass-io -u root anon-i2nix bash -s << 'EOF'
cat <<RCLOCAL >> /rw/config/rc.local
# HTTP Proxy
qvm-connect-tcp 4444:@default:4444
# POP3
qvm-connect-tcp 7660:@default:7660
# SMTP
qvm-connect-tcp 7659:@default:7659
RCLOCAL
chmod +x /rw/config/rc.local

echo "export http_proxy=127.0.0.1:4444" >> /home/user/.bashrc
echo "export https_proxy=127.0.0.1:4444" >> /home/user/.bashrc
EOF

echo "==> Applying firewall rules to anon-i2nix..."
qvm-firewall anon-i2nix add --before 0 drop proto=icmp

echo "=================================================="
echo " Build Complete!"
echo " Note: Librewolf AppImage installation and"
echo " Thunderbird configuration must still be executed"
echo " manually inside the anon-i2nix qube."
echo "=================================================="
