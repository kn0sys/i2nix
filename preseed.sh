#!/bin/bash

# creates preseed.cfg for virt-install

password=""
pass_var="Enter $1 password: "
while IFS= read -p "$pass_var" -r -s -n 1 letter; do
    if [[ $letter == $'\0' ]]; then
        break
    fi
    password="${password}${letter}"
    pass_var="*"
done
echo

I2NIX_CRED=$(mkpasswd -m sha-512 "$password")

cat <<EOF > $1-preseed.cfg
# --- Localization ---
d-i debian-installer/language string en
d-i debian-installer/country string US
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

# --- Network ---
d-i netcfg/get_hostname string i2nix-$1
d-i netcfg/get_domain string local
d-i hw-detect/load_firmware boolean true

# --- User setup ---
d-i passwd/root-password-crypted password $I2NIX_CRED
d-i passwd/user-fullname string I2nix User
d-i passwd/username string i2nix
d-i passwd/user-password-crypted password $I2NIX_CRED

# --- Partitioning ---
# Use /dev/vda for VirtIO disks
d-i partman-auto/disk string /dev/vda
d-i partman-auto/method string lvm
d-i partman-auto-lvm/new_vg_name string i2nix-vg
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# --- Package selection ---
tasksel tasksel/first multiselect standard
d-i pkgsel/include string openssh-server sudo qemu-guest-agent

# --- Bootloader Configuration ---
# This is the key to automating the GRUB installation prompt.
d-i grub-installer/bootdev string /dev/vda
d-i grub-pc/install_devices string /dev/vda

# This tells the final installed kernel to use the serial console.
d-i debian-installer/add-kernel-opts string "console=ttyS0,115200n8"

# --- Final commands ---
# Add user to sudo group
d-i preseed/late_command string \
    in-target usermod -aG sudo i2nix; \
    in-target sh -c "echo 'i2nix ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-i2nix-nopasswd"; \
    in-target chmod 0440 /etc/sudoers.d/90-i2nix-nopasswd; \
    in-target sh -c "echo 'send host-name = gethostname();' >> /etc/dhcp/dhclient.conf";

d-i finish-install/reboot_in_progress note
EOF

echo "$1-preseed.cfg created successfully."
