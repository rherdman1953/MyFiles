#!/bin/bash

echo "Starting Mullvad and stopping Tailscale..."

# Stop Tailscale first
sudo tailscale down
sleep 1

# Connect to Mullvad
mullvad connect

# Check status
mullvad_status=$(mullvad status | grep -o "Disconnected\|Connected")
if [ "$mullvad_status" = "Connected" ]; then
    echo "✓ Mullvad is connected"
    notify-send "VPN Status" "Mullvad ON - Internet traffic encrypted" -i network-vpn-symbolic
else
    echo "✗ Mullvad failed to connect"
    notify-send "VPN Status" "Mullvad connection failed" -i dialog-error
fi

echo "Tailscale: Disconnected"
