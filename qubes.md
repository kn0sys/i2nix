# Qubes Os Build Guide

### Clone the Fedora TemplateVM
* enter `i2nix-gateway` for the name
* start the template and open a terminal

### Install Software
* `sudo dnf update -y`
* `sudo dnf copr enable supervillain/i2pd`
* `sudo dnf install i2pd`

### Create the NetVM
* Create a new qube using the `i2nix-gateway` template
* Set the NetVM as `sys-firewall` and add the `network-manager` service

TODO: to be continued...
