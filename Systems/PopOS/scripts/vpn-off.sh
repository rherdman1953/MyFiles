#!/bin/bash

echo "Stopping both Tailscale and Mullvad..."

# Disconnect Mullvad
mullvad disconnect
sleep 1

# Stop Tailscale
sudo tailscale down

echo "✓ All VPNs disconnected"
notify-send "VPN Status" "All VPNs OFF" -i network-offline
