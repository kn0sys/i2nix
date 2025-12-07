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

### Enable Simple Port Binding

In `dom0` edit `/etc/qubes/policy.d/30-user-networking.policy`

```bash
qubes.ConnectTCP * anon-i2nix @default allow target=sys-i2nix
```

[Reference](https://doc.qubes-os.org/en/latest/user/security-in-qubes/firewall.html)

## i2nix-workstation configuration

### Clone the Fedora TemplateVM
* enter `i2nix-workstation` for the name
* start the template and open a terminal

### Create the AppVM
* Create a AppVM new qube using the `i2nix-workstation` template
* Enter `anon-i2nix` for the name
* Set the NetVM as `sys-i2nix`

### Configure the Firefox Browser

NOTE: If manually setting, ensure `Use this proxy for HTTPS` is checked

```bash

mkdir -p /etc/firefox/policies/
cat <<EOF > /etc/firefox/policies/policies.json
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
EOF

mkdir -p /usr/local/share/applications
cat <<EOF > /usr/local/share/applications/firefox.desktop
[Desktop Entry]
Name=Firefox (Sandboxed)
Exec=firejail firefox %u
Comment=Sandboxed private web browser
Icon=firefox
Type=Application
Categories=Network;WebBrowser;
EOF
```

### Global http proxy

Append the following to `/rw/config/rc.local`

```bash
qvm-connect-tcp 4444:@default:4444
echo "export http_proxy=127.0.0.1:4444" >> /home/user/.bashrc
echo "export https_proxy=127.0.0.1:4444" >> /home/user/.bashrc
# Disable ICMP
qvm-firewall anon-i2nix add --before 0 drop proto=icmp
```

TODO: anon-i2nix vm testing, librewolf installation, etc
