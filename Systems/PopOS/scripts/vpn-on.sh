#!/bin/bash

# Find notify-send regardless of PATH (needed when sudo alters environment)
NOTIFY=$(command -v notify-send 2>/dev/null || command -v /usr/bin/notify-send 2>/dev/null)
notify() {
    if [[ -n "$NOTIFY" ]]; then
        if [[ -n "$SUDO_USER" ]]; then
            sudo -u "$SUDO_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$SUDO_USER")/bus" "$NOTIFY" "$@"
        else
            "$NOTIFY" "$@"
        fi
    fi
}

get_ts_health() {
    tailscale status --json 2>/dev/null \
        | python3 -c "
import json,sys
data=json.load(sys.stdin)
health=data.get('Health',[])
# Filter out known false positive that occurs after Mullvad disconnect
# MagicDNS (100.100.100.100) works fine despite this warning
real_issues=[h for h in health if 'configured DNS servers' not in h]
print(real_issues[0] if real_issues else '')
" 2>/dev/null
}

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
    notify "VPN Status" "Mullvad failed to disconnect" -i dialog-error
    exit 1
fi

# Flush DNS state before bringing Tailscale up to avoid stale resolver entries
sudo resolvectl flush-caches 2>/dev/null

# Start Tailscale
sudo tailscale up

# Wait for Tailscale to fully connect (up to 15 seconds)
echo "Waiting for Tailscale to connect..."
for i in {1..15}; do
    tailscale status --active &>/dev/null && break
    sleep 1
done

# Report final status
ts_health=$(get_ts_health)

if tailscale status --active &>/dev/null; then
    if [[ -z "$ts_health" ]]; then
        echo "✓ Tailscale is connected"
        notify "VPN Status" "Tailscale ON - Home network accessible" -i network-vpn
    else
        echo "✓ Tailscale connected (with warning: $ts_health)"
        notify "VPN Status" "Tailscale ON - warning: $ts_health" -i dialog-warning
    fi
else
    echo "✗ Tailscale failed to connect"
    notify "VPN Status" "Tailscale connection failed" -i dialog-error
fi

echo "Mullvad: $mullvad_status"
