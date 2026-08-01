# QubesOS Automated Install

1. Save the code above to a file in dom0, for example: `i2nix-install.sh`. (`qvm-run --pass-io <QUBE_NAME> 'cat /home/user/i2nix-install.sh' > ./i2nix-install.sh` 
2. Make the script executable: `chmod +x i2nix-install.sh`.
3. Verify you have the base `fedora-43` template installed (modify the `FEDORA_VER` variable at the top of the script if using a different version).
4. Run the script from your dom0 terminal: `./i2nix-install.sh`.
