#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <unraid_host_or_ip> [output.csv]" >&2
    exit 1
fi

HOST="$1"
OUT="${2:-unraid_disk_inventory_$(date +%Y%m%d_%H%M%S).csv}"

ssh -T "root@${HOST}" 'bash -s' > "$OUT" <<'REMOTE_SCRIPT'
set -euo pipefail

csv_escape() {
    local s="${1:-}"
    s="${s//$'\n'/ }"
    s="${s//$'\r'/ }"
    s="${s//\"/\"\"}"
    printf '"%s"' "$s"
}

trim() {
    local s="${1:-}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

strip_wrapping_quotes() {
    local s="${1:-}"
    s="$(trim "$s")"
    while [[ "$s" == \"*\" && "$s" == *\" ]]; do
        s="${s#\"}"
        s="${s%\"}"
    done
    printf '%s' "$s"
}

get_first_by_id() {
    local dev_real
    dev_real="$(readlink -f "$1" 2>/dev/null || true)"
    [ -n "$dev_real" ] || return 0

    find /dev/disk/by-id -maxdepth 1 -type l 2>/dev/null | while read -r link; do
        local target
        target="$(readlink -f "$link" 2>/dev/null || true)"
        if [ "$target" = "$dev_real" ]; then
            basename "$link"
            break
        fi
    done
}

get_smart_field() {
    local dev="$1"
    local field_regex="$2"
    if command -v smartctl >/dev/null 2>&1; then
        smartctl -i "$dev" 2>/dev/null | awk -F: -v re="$field_regex" '
            $1 ~ re {
                sub(/^[[:space:]]+/, "", $2)
                print $2
                exit
            }
        '
    fi
}

declare -A SLOT_BY_DEVICE
declare -A SLOT_BY_ID

if [ -f /var/local/emhttp/disks.ini ]; then
    current_slot=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            current_slot="$(strip_wrapping_quotes "${BASH_REMATCH[1]}")"
        elif [[ "$line" =~ ^device=(.*)$ ]]; then
            current_device="$(strip_wrapping_quotes "${BASH_REMATCH[1]}")"
            [ -n "$current_slot" ] && [ -n "$current_device" ] && SLOT_BY_DEVICE["$current_device"]="$current_slot"
        elif [[ "$line" =~ ^id=(.*)$ ]]; then
            current_id="$(strip_wrapping_quotes "${BASH_REMATCH[1]}")"
            [ -n "$current_slot" ] && [ -n "$current_id" ] && SLOT_BY_ID["$current_id"]="$current_slot"
        fi
    done < /var/local/emhttp/disks.ini
fi

CAPTURE_TIME="$(date --iso-8601=seconds 2>/dev/null || date)"
HOSTNAME="$(hostname)"

{
    csv_escape "capture_time"; printf ","
    csv_escape "hostname"; printf ","
    csv_escape "unraid_slot"; printf ","
    csv_escape "slot_source"; printf ","
    csv_escape "device"; printf ","
    csv_escape "kernel_name"; printf ","
    csv_escape "size_bytes"; printf ","
    csv_escape "model"; printf ","
    csv_escape "serial"; printf ","
    csv_escape "firmware"; printf ","
    csv_escape "transport"; printf ","
    csv_escape "rota"; printf ","
    csv_escape "type"; printf ","
    csv_escape "by_id"; printf ","
    csv_escape "smart_model"; printf ","
    csv_escape "smart_serial"; printf "\n"
}

lsblk -d -b -n -P -o KNAME,PATH,SIZE,MODEL,SERIAL,TRAN,ROTA,TYPE | while read -r line; do
    unset KNAME PATH SIZE MODEL SERIAL TRAN ROTA TYPE
    eval "$line"

    [ "${TYPE:-}" = "disk" ] || continue

    case "${KNAME:-}" in
        loop*|ram*|zram*|sr*|md*|dm-*) continue ;;
    esac

    devpath="${PATH:-/dev/$KNAME}"
    model="$(trim "${MODEL:-}")"
    serial="$(trim "${SERIAL:-}")"
    by_id="$(get_first_by_id "$devpath")"
    firmware="$(trim "$(get_smart_field "$devpath" 'Firmware Version|Firmware Revision')")"
    smart_model="$(trim "$(get_smart_field "$devpath" 'Device Model|Model Number|Product')")"
    smart_serial="$(trim "$(get_smart_field "$devpath" 'Serial Number')")"

    slot=""
    slot_source=""

    if [ -n "$smart_serial" ] && [ -n "${SLOT_BY_ID[$smart_serial]:-}" ]; then
        slot="${SLOT_BY_ID[$smart_serial]}"
        slot_source="disks.ini:id=smart_serial"
    elif [ -n "$serial" ] && [ -n "${SLOT_BY_ID[$serial]:-}" ]; then
        slot="${SLOT_BY_ID[$serial]}"
        slot_source="disks.ini:id=serial"
    elif [ -n "${SLOT_BY_DEVICE[$KNAME]:-}" ]; then
        slot="${SLOT_BY_DEVICE[$KNAME]}"
        slot_source="disks.ini:device"
    else
        slot="unassigned"
    fi

    [ "$(strip_wrapping_quotes "$slot")" = "flash" ] && continue

    {
        csv_escape "$CAPTURE_TIME"; printf ","
        csv_escape "$HOSTNAME"; printf ","
        csv_escape "$slot"; printf ","
        csv_escape "$slot_source"; printf ","
        csv_escape "$devpath"; printf ","
        csv_escape "${KNAME:-}"; printf ","
        csv_escape "${SIZE:-}"; printf ","
        csv_escape "$model"; printf ","
        csv_escape "$serial"; printf ","
        csv_escape "$firmware"; printf ","
        csv_escape "${TRAN:-}"; printf ","
        csv_escape "${ROTA:-}"; printf ","
        csv_escape "${TYPE:-}"; printf ","
        csv_escape "$by_id"; printf ","
        csv_escape "$smart_model"; printf ","
        csv_escape "$smart_serial"; printf "\n"
    }
done
REMOTE_SCRIPT

echo "Wrote local CSV: $OUT"