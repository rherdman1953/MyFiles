#!/bin/bash
echo "Starting Tailscale and stopping Mullvad..."

# Disconnect Mullvad and wait for full teardown
mullvad disconnect
sleep 2

# Confirm Mullvad is actually disconnected before proceeding
for i in {1..5}; do
    mullvad_status=$(mullvad status | grep -o "Disconnected\|Connected")
    [[ "$mullvad_status" == "Disconnected" ]] && break
    echo "Waiting for Mullvad to disconnect... ($i/5)"
    sleep 1
done

if [[ "$mullvad_status" != "Disconnected" ]]; then
    echo "✗ Mullvad failed to disconnect - aborting"
    notify-send "VPN Status" "Mullvad failed to disconnect" -i dialog-error
    exit 1
fi

# Flush DNS state before bringing Tailscale up to avoid stale resolver entries
sudo resolvectl flush-caches 2>/dev/null

# Start Tailscale
sudo tailscale up

# Wait for Tailscale to fully connect (up to 15 seconds)
echo "Waiting for Tailscale to connect..."
for i in {1..15}; do
    if tailscale status --active &>/dev/null; then
        break
    fi
    sleep 1
done

# Report final status
ts_health=$(tailscale status --json 2>/dev/null | python3 -m json.tool 2>/dev/null | grep -A1 '"Health"' | tail -1 | tr -d '", ')

if tailscale status --active &>/dev/null; then
    if [[ -z "$ts_health" || "$ts_health" == "]" ]]; then
        echo "✓ Tailscale is connected (no health warnings)"
        notify-send "VPN Status" "Tailscale ON - Home network accessible" -i network-vpn
    else
        echo "✓ Tailscale connected (with warning: $ts_health)"
        notify-send "VPN Status" "Tailscale ON - but check health warnings" -i dialog-warning
    fi
else
    echo "✗ Tailscale failed to connect"
    notify-send "VPN Status" "Tailscale connection failed" -i dialog-error
fi

echo "Mullvad: $mullvad_status"