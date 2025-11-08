![i2nix](i2nix.png) 

# Installation

For automated installer see [install.md](https://github.com/kn0sys/i2nix/blob/main/install.md).

# i2nix: Reproducible Build Guide
**Version i2nix-v0.1.1**

## 1. Introduction
i2nix is a security-focused Linux operating system designed to route all network connections through the I2P anonymity network. It follows the isolation principles of Whonix®, using a two-part virtual machine design:

* **i2nix-gateway**: A dedicated virtual machine that acts as a network router, forcing all traffic through I2P.
* **i2nix-workstation**: A completely isolated virtual machine for user applications, which can only connect to the internet via the Gateway.

This guide provides the steps to build both components from scratch for a truly reproducible and transparent system.

### Prerequisites
* A Linux host machine with KVM/QEMU and `virt-manager, libvirt, virsh, virt-install, virt-viewer` installed.
* A Debian net-installer ISO (e.g., `debian-13-netinst.iso`).
* Basic familiarity with the Linux command line and `virt-manager`.
* For system requirements see `install.sh` and `virt-install` options `vcpus`, `ram` and `disk-path` `size`.

## 2. Building the i2nix-gateway

### Step 2.1: Base System Installation
1.  Create a new VM in `virt-manager`.
2.  During the Debian installation:
    * **Software selection**: Deselect all options except for **"standard system utilities"** and **"SSH server"**.
    * **Partitioning**: Standard is fine. Encrypted LVM is recommended.

### Step 2.2: Network Configuration
1.  Shut down the VM after installation. In `virt-manager`, configure two network adapters:
    * **Adapter 1 (External)**: Set to your default NAT or Bridged network. This is for I2P to connect to the internet.
    * **Adapter 2 (Internal)**: Create a new virtual network. Name it `i2nix` and set it to "Isolated network".
2.  (Optional: run the [gateway-setup.sh](https://github.com/kn0sys/i2nix/blob/main/gateway-setup.sh) and proceed to Workstation setup) Start the VM and configure `/etc/network/interfaces`:

    ```bash
    # /etc/network/interfaces
    source /etc/network/interfaces.d/*

    auto lo
    iface lo inet loopback

    # External interface (e.g., enp1s0)
    allow-hotplug enp1s0
    iface enp1s0 inet dhcp

    # Internal interface for i2nix-workstation (e.g., enp7s0)
    auto enp7s0
    iface enp7s0 inet static
        address 10.152.152.10
        netmask 255.255.255.0
    ```

### Step 2.3: I2P Installation

```bash
apt-get update
apt-get install -y apt-transport-https curl wget gpg

wget -q -O - https://repo.i2pd.xyz/.help/add_repo | sudo bash -s -

apt update -y
apt install -y i2pd
systemctl enable i2pd
echo "[+] i2pd installed."

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
port = 8444
keys = http-keys.dat

[alt-socks]
type = socks
address = $GATEWAY_INTERNAL_IP
port = 8667
keys = socks-keys.dat 
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

# Allow workstation ssh access to pull packages
iptables -A INPUT -p tcp -s $I2NIX_WORKSTATION --dport 22 -j ACCEPT

# Save the rules to make them persistent
netfilter-persistent save

echo "[+] Firewall configured and enabled."
```

## 3. Building the i2nix-workstation

### Step 3.1: Base System Installation
1.  Create a new VM in `virt-manager`.
2.  During the Debian installation:
    * **Software selection**: Select **"XFCE"** (or another desktop environment) and **"standard system utilities"**.

### Step 3.2: Network Configuration
1.  Shut down the VM. In `virt-manager`, configure a **single** network adapter set to the isolated `i2nix` virtual network.
2.  (Optional: run the [workstation-setup.sh](https://github.com/kn0sys/i2nix/blob/main/workstation-setup.sh) and test Librewolf) Start the VM and configure a static IP.
    * Edit `/etc/network/interfaces`:
        ```bash
        # /etc/network/interfaces
        auto enp1s0
        iface enp1s0 inet static
            address 10.152.152.11
            netmask 255.255.255.0
            gateway 10.152.152.10
        ```
    * Set the DNS server in `/etc/resolv.conf`:
        ```
        nameserver 10.152.152.10
        ```
### Step 3.3: Connection Test
1.  `ping 10.152.152.10` -> **Should PASS**.
2.  `ping 8.8.8.8` -> **Should FAIL**.
3.  `wget stats.i2p` -> **Should SUCCEED** and return HTML.

## 4. Hardening the i2nix-workstation

### Step 4.1: Browser Hardening (LibreWolf)
1.  **On the Gateway**, download the LibreWolf GPG key and `.deb` package. (`https://download.opensuse.org/repositories/home:/bgstack15:/aftermozilla...`)
2.  **Transfer** these files to the Workstation (e.g., via a temporary shared folder).
3.  **On the Workstation**, install the files:
    ```bash
    # Move key to correct location
    sudo gpg --dearmor -o /usr/share/keyrings/librewolf.gpg keyring.gpg
    # Install package (this will likely fail on dependencies)
    sudo dpkg -i librewolf_*.deb
    # Fix broken dependencies, which downloads them through I2P
    sudo apt-get -f install
    ```
4.  **In LibreWolf `about:config`**, set the following to `true`:
    * `privacy.resistFingerprinting`
    * `webgl.disabled`
    * `privacy.firstparty.isolate`
    * `network.proxy.socks_remote_dns`
5.  **In LibreWolf Network Settings**, configure manual proxy:
    * **HTTP Host**: `10.152.152.10`, **Port**: `4444`
    * **SOCKS Host**: `10.152.152.10`, **Port**: `7667`
    * Select **SOCKS v5**.
    * Check **"Proxy DNS when using SOCKS v5"**.

### Step 4.2: Application Sandboxing (Firejail)
1.  Install Firejail: `sudo apt install firejail firejail-profiles`.
2.  Copy the LibreWolf launcher: `cp /usr/share/applications/librewolf.desktop ~/.local/share/applications/`.
3.  Edit `~/.local/share/applications/librewolf.desktop` and change the `Exec` line:
    * **From**: `Exec=librewolf %u`
    * **To**: `Exec=firejail librewolf %u`

### Step 4.3: Kernel Hardening
1.  Create `/etc/sysctl.d/99-i2nix-hardening.conf`:
    ```ini
    kernel.kptr_restrict=2
    kernel.dmesg_restrict=1
    kernel.unprivileged_userns_clone=0
    kernel.unprivileged_bpf_disabled=1
    net.ipv4.tcp_syncookies=1
    net.ipv4.icmp_echo_ignore_broadcasts=1
    ```
2.  Apply settings: `sudo sysctl --system`.

---
*This guide provides the steps to create a functional i2nix system. Further security hardening is always encouraged.*
