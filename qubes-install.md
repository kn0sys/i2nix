# QubesOS Automated Install

1. Save the code above to a file in dom0, for example: `qubes-install.sh`. (`qvm-run --pass-io <QUBE_NAME> 'cat /home/user/qubes-install.sh' > ./qubes-install.sh` 
2. Make the script executable: `chmod +x qubes-install.sh`.
3. Verify you have the base `fedora-43` template installed (modify the `FEDORA_VER` variable at the top of the script if using a different version).
4. Run the script from your dom0 terminal: `./qubes-install.sh`.
