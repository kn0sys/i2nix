#!/bin/bash
# i2nix Linux installer script

# --- Dependencies Check ---
for cmd in virt-install virsh wget mkpasswd; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "$cmd could not be found. Please install it."
        exit 1
    fi
done

# --- Download Debian 13 ISO ---
ISO_FILENAME="debian-13.0.0-amd64-netinst.iso"
if [ ! -f "$ISO_FILENAME" ]; then
    FULL_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.0.0-amd64-netinst.iso"
    echo "Downloading Debian 13 netinst ISO..."
    wget -O "$ISO_FILENAME" "$FULL_URL"
    echo "Download complete: $ISO_FILENAME"
else
    echo "ISO file already exists. Skipping download."
fi

# --- Create Preseed Config ---
echo "Creating preseed.cfg files..."
./preseed.sh gateway
./preseed.sh workstation

# --- Install Gateway ---
echo "Installing i2nix-gateway VM... This will take some time."
virt-install \
  --name i2nix-gateway \
  --ram 1024 \
  --vcpus 1 \
  --disk path=/var/lib/libvirt/images/i2nix-gateway.qcow2,size=4 \
  --os-variant debian13 \
  --network bridge=virbr0,model=virtio \
  --network network=default,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --location "$PWD/$ISO_FILENAME" \
  --initrd-inject gateway-preseed.cfg \
  --extra-args="hostname=i2nix-gateway auto=true priority=critical preseed/file=/gateway-preseed.cfg console=ttyS0,115200n8" \
  --wait -1

# --- Install Workstation ---
echo "Installing i2nix-workstation VM... This will take some time."
virt-install \
  --name i2nix-workstation \
  --ram 2048 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/i2nix-workstation.qcow2,size=8 \
  --os-variant debian13 \
  --network bridge=virbr0,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --location "$PWD/$ISO_FILENAME" \
  --initrd-inject workstation-preseed.cfg \
  --extra-args="hostname=i2nix-workstation auto=true priority=critical preseed/file=/workstation-preseed.cfg console=ttyS0,115200n8" \
  --wait -1

echo "Both VMs have been installed."

# --- Configure Gateway ---
echo "Starting and configuring Gateway..."
virsh start i2nix-gateway
# Wait for the VM to boot and get an IP address
echo "Waiting for Gateway to boot..."
sleep 45
GATEWAY_IP=$(arp -e | grep $(virsh -c qemu:///system net-dhcp-leases default | grep i2nix-gateway | awk '{print $3}') | awk '{print $1}')
if [ -z "$GATEWAY_IP" ]; then
    echo "Could not get Gateway IP. Setup failed."
    exit 1
fi
echo "Gateway IP is $GATEWAY_IP"
ssh-keyscan "$GATEWAY_IP" >> ~/.ssh/known_hosts
ssh i2nix@"$GATEWAY_IP" "sudo apt-get update && sudo apt-get install -y git && git clone https://github.com/kn0sys/i2nix && cd i2nix && chmod +x gateway-setup.sh && sudo ./gateway-setup.sh"

# --- Configure Workstation ---
echo "Starting and configuring Workstation..."
virsh start i2nix-workstation
echo "Waiting for Workstation to boot..."
sleep 45
WORKSTATION_IP=$(arp -e | grep $(virsh -c qemu:///system net-dhcp-leases default | grep i2nix-workstation | awk '{print $3}') | awk '{print $1}')
if [ -z "$WORKSTATION_IP" ]; then
    echo "Could not get Workstation IP. Setup failed."
    exit 1
fi
echo "Workstation IP is $WORKSTATION_IP"
ssh-keyscan "$WORKSTATION_IP" >> ~/.ssh/known_hosts
ssh i2nix@"$WORKSTATION_IP" "sudo apt-get update && sudo apt-get install -y git task-xfce-desktop && git clone https://github.com/kn0sys/i2nix && cd i2nix && chmod +x workstation-setup.sh && sudo ./workstation-setup.sh && sudo reboot"

echo "i2nix installation complete. Launching workstation console."
# Clean up preseed file
rm *preseed.cfg
# Launch virt-manager focused on the workstation
virt-manager --connect qemu:///system --show-domain-console i2nix-workstation
