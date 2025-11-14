# Qubes OS Build Guide

## i2nix-gateway configuration

### Clone the Fedora TemplateVM
* Enter `i2nix-gateway` for the name
* Start the template and open a terminal

### Install Software
* `sudo dnf update -y`
* `sudo dnf copr enable supervillain/i2pd`
* `sudo dnf install i2pd`

### Create the NetVM
* Create a AppVM (ProxyVM) new qube using the `i2nix-gateway` template
* Enter `sys-i2nix` for the name
* Enable the `provides network service to other qubes` checkbox
* Set the NetVM as `sys-firewall` and add the `network-manager` service

### I2P Proxy Script

`vim /rw/config/start_i2p_proxy.sh`

```bash
#!/bin/sh
killall i2pd
QUBES_IP=$(xenstore-read qubes_ip)
I2P_HTTP_PROXY_PORT=8444
I2P_DNS_PORT=7653
I2P_TRANS_PORT="7654"

if [ X$QUBES_IP == X ]; then
echo "Error getting QUBES IP!"
echo "Not starting i2p, but setting the traffic redirection anyway to prevent leaks."
QUBES_IP="127.0.0.1"
else
i2pd \
--httpproxy.port 8444 \
--httpproxy.address QUBES_IP \
|| echo "Error starting i2p!"

fi

echo “0” > /proc/sys/net/ipv4/ip_forward
/sbin/iptables -t nat -F
/sbin/iptables -t nat -A PREROUTING -i vif+ -p udp --dport 53 -j DNAT --to-destination $QUBES_IP:53
/sbin/iptables -t nat -A PREROUTING -i vif+ -p tcp -j DNAT --to-destination $QUBES_IP:$I2P_TRANS_PORT
/sbin/iptables -I INPUT 1 -i vif+ -p udp --dport 53 -j ACCEPT
/sbin/iptables -I INPUT 2 -i vif+ -p tcp --dport I2P_TRANS_PORT -j ACCEPT
/sbin/iptables -F FORWARD

echo “1” > /proc/sys/net/ipv4/ip_forward
```

### Autostart

`vim /rw/config/rc.local`

```bash

#!/bin/sh

chkconfig qubes_netwatcher off
chkconfig qubes_firewall off
/rw/config/start_i2p_proxy.sh
```

### Restart on NetVM Dynamic Switching

`vim /rw/config/qubes_ip_change_hook`

```bash
#!/bin/sh
/rw/config/start_i2p_proxy.sh
```

## i2nix-workstation configuration

### Clone the Fedora TemplateVM
* enter `i2nix-workstation` for the name
* start the template and open a terminal

### Install Software
* `sudo dnf update -y`
* `sudo dnf install -y firejail`
* `curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee /etc/yum.repos.d/librewolf.repo`
* `sudo dnf install -y librewolf` 

### Create the AppVM
* Create a AppVM new qube using the `i2nix-gateway` template
* Enter `anon-i2nix` for the name
* Set the NetVM as `sys-i2nix`

### Configure the Librewolf Browser

```bash

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
```

TODO: anon-i2nix vm testing
