![i2nix](i2nix.png) 

# i2nix: Reproducible Build Guide
**Version 1.0 (2025-08-10)**

## 1. Introduction
i2nix is a security-focused Linux operating system designed to route all network connections through the I2P anonymity network. It follows the isolation principles of Whonix®, using a two-part virtual machine design:

* **i2nix-gateway**: A dedicated virtual machine that acts as a network router, forcing all traffic through I2P.
* **i2nix-workstation**: A completely isolated virtual machine for user applications, which can only connect to the internet via the Gateway.

This guide provides the steps to build both components from scratch for a truly reproducible and transparent system.

### Prerequisites
* A Linux host machine with KVM/QEMU and `virt-manager` installed.
* A Debian net-installer ISO (e.g., `debian-12-netinst.iso`).
* Basic familiarity with the Linux command line and `virt-manager`.

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
2.  Start the VM and configure `/etc/network/interfaces`:

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
1.  Add the I2P repository:
    ```bash
    sudo apt-get update
    sudo apt-get install apt-transport-https curl gpg
    curl -o /tmp/i2p-repo-key.asc [https://geti2p.net/_static/idk.key.asc](https://geti2p.net/_static/idk.key.asc)
    sudo gpg --dearmor -o /usr/share/keyrings/i2p-archive-keyring.gpg /tmp/i2p-repo-key.asc
    echo "deb [signed-by=/usr/share/keyrings/i2p-archive-keyring.gpg] https://deb.i2p.net/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/i2p.list
    ```
2.  Install and enable the I2P service:
    ```bash
    sudo apt-get update
    sudo apt-get install i2p i2p-keyring
    sudo systemctl enable i2p
    sudo systemctl start i2p
    ```

### Step 2.4: Firewall & Transparent Proxying
1.  **Configure I2P HTTP Proxy Tunnel**:
    * Using a text-based browser on the Gateway (e.g., `w3m`), navigate to the router console at `http://127.0.0.1:7657`.
    * Go to **"I2PTunnel"**.
    * Modify the **"HTTP Proxy"** client tunnel with these settings:
        * **Interface**: `10.152.152.10`
        * **Port**: `4444`

2.  **Configure I2P SOCKS Proxy Tunnel**:
    * Using a text-based browser on the Gateway (e.g., `w3m`), navigate to the router console at `http://127.0.0.1:7657`.
    * Go to **"I2PTunnel"**.
    * Create a new **"SOCKS 4/4a/5"** client tunnel with these settings:
        * **Name**: `i2nix-transproxy`
        * **Interface**: `10.152.152.10`
        * **Port**: `7667`
        * **Outproxies**: `outproxy.acetone.i2p` (or another reliable outproxy)
        * Enable **"Auto Start"**.
    * Save and start the new tunnel.
      
2.  **Apply Firewall Rules**:
    * Install the persistence tool: `sudo apt-get install iptables-persistent`.
    * Create a script `firewall-setup.sh` with the following content and run it with `sudo bash firewall-setup.sh`.

    ```bash
    #!/bin/bash
    I2NIX_WORKSTATION="10.152.152.11"
    GATEWAY_INTERNAL_IP="10.152.152.10"
    INTERNAL_INTERFACE="enp7s0" # CHANGE IF YOURS IS DIFFERENT
    I2P_DNS_PORT="7653"
    I2P_TRANS_PORT="7667"

    # Flush old rules
    iptables --flush
    iptables --delete-chain
    iptables --policy FORWARD DROP

    # NAT Table: Redirect traffic
    # DNS
    iptables -t nat -A PREROUTING -i $INTERNAL_INTERFACE -p udp --dport 53 -j DNAT --to-destination $GATEWAY_INTERNAL_IP:$I2P_DNS_PORT
    iptables -t nat -A PREROUTING -i $INTERNAL_INTERFACE -p tcp --dport 53 -j DNAT --to-destination $GATEWAY_INTERNAL_IP:$I2P_DNS_PORT
    # All other TCP
    iptables -t nat -A PREROUTING -i $INTERNAL_INTERFACE -p tcp --syn -j DNAT --to-destination $GATEWAY_INTERNAL_IP:$I2P_TRANS_PORT

    # Filter Table: Permit forwarding of redirected traffic
    iptables -A FORWARD -i $INTERNAL_INTERFACE -d $GATEWAY_INTERNAL_IP -p tcp --dport $I2P_TRANS_PORT -m state --state NEW -j ACCEPT
    iptables -A FORWARD -i $INTERNAL_INTERFACE -d $GATEWAY_INTERNAL_IP -p tcp --dport $I2P_DNS_PORT -m state --state NEW -j ACCEPT
    iptables -A FORWARD -i $INTERNAL_INTERFACE -d $GATEWAY_INTERNAL_IP -p udp --dport $I2P_DNS_PORT -m state --state NEW -j ACCEPT
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Save rules
    netfilter-persistent save
    echo "Gateway firewall applied."
    ```

## 3. Building the i2nix-workstation

### Step 3.1: Base System Installation
1.  Create a new VM in `virt-manager`.
2.  During the Debian installation:
    * **Software selection**: Select **"XFCE"** (or another desktop environment) and **"standard system utilities"**.

### Step 3.2: Network Configuration
1.  Shut down the VM. In `virt-manager`, configure a **single** network adapter set to the isolated `i2nix` virtual network.
2.  Start the VM and configure a static IP.
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
