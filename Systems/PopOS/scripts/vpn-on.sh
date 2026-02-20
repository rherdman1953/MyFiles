#!/bin/bash

echo "Starting Tailscale and stopping Mullvad..."

# Disconnect Mullvad first
mullvad disconnect
sleep 1

# Start Tailscale
sudo tailscale up

# Check status
if tailscale status --active &>/dev/null; then
    echo "✓ Tailscale is connected"
    notify-send "VPN Status" "Tailscale ON - Home network accessible" -i network-vpn
else
    echo "✗ Tailscale failed to connect"
    notify-send "VPN Status" "Tailscale connection failed" -i dialog-error
fi

mullvad_status=$(mullvad status | grep -o "Disconnected\|Connected")
echo "Mullvad: $mullvad_status"
