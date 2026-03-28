#!/bin/bash

# =============================================================================
# arr-rescans — Sonarr / Radarr / Lidarr rescan & import monitor
# Location:  /boot/config/plugins/user.scripts/scripts/arr-rescans/script
# Schedule:  */5 * * * *
# Config:    /boot/config/arr-rescans.conf
# =============================================================================

# Load external config — abort with Unraid alert if missing
if [ ! -f /boot/config/arr-rescans.conf ]; then
  /usr/local/emhttp/webGui/scripts/notify \
    -e "arr-rescans" \
    -s "arr-rescans config missing" \
    -d "Config file /boot/config/arr-rescans.conf not found. Script cannot run." \
    -i "alert"
  exit 1
fi
source /boot/config/arr-rescans.conf

# App base URLs
SONARR="http://192.168.1.12:8989"
RADARR="http://192.168.1.12:7878"
LIDARR="http://192.168.1.12:8686"

# Sync folder base paths (host paths)
SONARR_SYNC="/mnt/user/media/download/sync/sonarr"
RADARR_SYNC="/mnt/user/media/download/sync/radarr"

# How long (in minutes) before alerting on an unimported item
ALERT_THRESHOLD=120

# =============================================================================
# send_notification — Discord with Unraid fallback
# =============================================================================
send_notification() {
  local message="$1"
  local MSG
  MSG=$(jq -n --arg msg "$message" '{content: $msg}')
  local HTTP_CODE
  HTTP_CODE=$(curl -s -o /tmp/discord_response.json -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "$MSG" "$DISCORD_WEBHOOK")
  if [ "$HTTP_CODE" != "204" ]; then
    local ERROR
    ERROR=$(cat /tmp/discord_response.json 2>/dev/null)
    /usr/local/emhttp/webGui/scripts/notify \
      -e "arr-rescans" \
      -s "Discord webhook error" \
      -d "HTTP $HTTP_CODE: $ERROR — Message: $message" \
      -i "warning"
    echo "Discord failed (HTTP $HTTP_CODE), sent Unraid notification"
  fi
}

# =============================================================================
# confirm_import — check whether all video files in a path are gone.
# Returns 0 (true) if no video files remain, 1 (false) if files still present.
# $1 = path to check (file or directory)
# =============================================================================
confirm_import() {
  local path="$1"
  if [ -f "$path" ]; then
    # Loose file — gone entirely
    [ ! -f "$path" ] && return 0
    # Still present but hardlinked into media library — counts as imported
    local links
    links=$(stat -c %h "$path")
    [ "$links" -gt 1 ] && return 0
    return 1
  elif [ -d "$path" ]; then
    local remaining
    remaining=$(find "$path" -type f \( \
      -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \
      -o -iname "*.m4v" -o -iname "*.mov" \) | wc -l)
    # No video files at all — fully removed
    [ "$remaining" -eq 0 ] && return 0
    # Check for any video files with link count of 1 (not yet hardlinked)
    local unlinked
    unlinked=$(find "$path" -type f \( \
      -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \
      -o -iname "*.m4v" -o -iname "*.mov" \) \
      -links 1 | wc -l)
    # All video files hardlinked — fully imported
    [ "$unlinked" -eq 0 ] && return 0
    return 1
  fi
  # Path no longer exists — treat as imported
  return 0
}

# =============================================================================
# STEP 1 — Clean up orphaned marker files
# Marker files whose base media file/folder is gone can be removed safely.
# =============================================================================
for marker in \
    "$SONARR_SYNC"/*.mkv.imported \
    "$SONARR_SYNC"/*.mkv.first_seen \
    "$SONARR_SYNC"/*.mkv.alerted \
    "$RADARR_SYNC"/*.mkv.imported \
    "$RADARR_SYNC"/*.mkv.first_seen \
    "$RADARR_SYNC"/*.mkv.alerted; do
  [ -f "$marker" ] || continue
  base="${marker%.imported}"
  base="${base%.first_seen}"
  base="${base%.alerted}"
  [ -f "$base" ] || rm -f "$marker"
done

for marker in \
    "$SONARR_SYNC"/*/".imported" \
    "$SONARR_SYNC"/*/".first_seen" \
    "$SONARR_SYNC"/*/".alerted" \
    "$RADARR_SYNC"/*/".imported" \
    "$RADARR_SYNC"/*/".first_seen" \
    "$RADARR_SYNC"/*/".alerted"; do
  [ -f "$marker" ] || continue
  parent_dir=$(dirname "$marker")
  [ -d "$parent_dir" ] || rm -f "$marker"
done

# =============================================================================
# STEP 2 — Suspicious file detection (subfolders only)
# Alert and skip any folder containing executable file types.
# =============================================================================
for SYNC_DIR in "$SONARR_SYNC" "$RADARR_SYNC"; do
  APP="Sonarr"
  [ "$SYNC_DIR" = "$RADARR_SYNC" ] && APP="Radarr"

  for item in "$SYNC_DIR"/*/; do
    [ -d "$item" ] || continue
    [ -f "${item}.imported" ] && continue
    SUSPICIOUS=$(find "$item" -type f \( \
      -iname "*.exe" -o -iname "*.bat" -o -iname "*.com" \
      -o -iname "*.scr" -o -iname "*.js" -o -iname "*.vbs" \) | wc -l)
    if [ "$SUSPICIOUS" -gt 0 ]; then
      folder=$(basename "$item")
      send_notification "🚨 **Suspicious files in ${APP} download**: \`$folder\` contains $SUSPICIOUS potentially malicious file(s). Import skipped — manual review required."
      touch "${item}.imported"
      echo "SUSPICIOUS: $folder"
    fi
  done
done

# =============================================================================
# STEP 3 — Stuck-import alerts (subfolders and loose .mkv files)
# Uses .first_seen marker timestamps — does NOT alert on items already marked
# .imported. Items marked .imported but whose files are still present are
# flagged separately in Step 5.
# =============================================================================
alert_if_stuck() {
  local item="$1"
  local app="$2"
  local label="$3"

  [ -f "${item}.imported" ] && return
  if [ ! -f "${item}.first_seen" ]; then
    touch "${item}.first_seen"
    return
  fi
  local marker_time now age
  marker_time=$(stat -c %Y "${item}.first_seen")
  now=$(date +%s)
  age=$(( (now - marker_time) / 60 ))
  if [ "$age" -gt "$ALERT_THRESHOLD" ]; then
    [ -f "${item}.alerted" ] && return
    send_notification "⚠️ **${app}**: \`${label}\` has not imported after ${age} minutes"
    echo "Alert: $label (${age} minutes)"
    touch "${item}.alerted"
  fi
}

# Sonarr subfolders
for item in "$SONARR_SYNC"/*/; do
  [ -d "$item" ] || continue
  alert_if_stuck "$item" "Sonarr" "$(basename "$item")"
done

# Radarr subfolders
for item in "$RADARR_SYNC"/*/; do
  [ -d "$item" ] || continue
  alert_if_stuck "$item" "Radarr" "$(basename "$item")"
done

# Sonarr loose .mkv files
for mkv in "$SONARR_SYNC"/*.mkv; do
  [ -f "$mkv" ] || continue
  alert_if_stuck "$mkv" "Sonarr" "$(basename "$mkv")"
done

# Radarr loose .mkv files
for mkv in "$RADARR_SYNC"/*.mkv; do
  [ -f "$mkv" ] || continue
  alert_if_stuck "$mkv" "Radarr" "$(basename "$mkv")"
done

# =============================================================================
# STEP 4 — RefreshMonitoredDownloads (first pass)
# Keeps the *arr queue in sync with qBittorrent state before scanning.
# =============================================================================
curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$SONARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$RADARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $LIDARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$LIDARR/api/v3/command" > /dev/null

# =============================================================================
# STEP 5 — Submit scan commands
# .imported is NOT set here. It is set only after file-gone confirmation in
# Step 7. This prevents silent Sonarr/Radarr match failures from being
# permanently skipped.
# =============================================================================

# Sonarr subfolders
for item in "$SONARR_SYNC"/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  folder=$(basename "$item")
  PAYLOAD=$(jq -n --arg name "DownloadedEpisodesScan" --arg path "/downloads/$folder" \
    '{name: $name, path: $path}')
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$SONARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    echo "Sonarr scan submitted: $folder"
  else
    echo "Sonarr scan ERROR: $folder — $RESPONSE"
  fi
done

# Radarr subfolders
for item in "$RADARR_SYNC"/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  folder=$(basename "$item")
  PAYLOAD=$(jq -n --arg name "DownloadedMoviesScan" --arg path "/downloads/$folder" \
    '{name: $name, path: $path}')
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$RADARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    echo "Radarr scan submitted: $folder"
  else
    echo "Radarr scan ERROR: $folder — $RESPONSE"
  fi
done

# Sonarr loose .mkv files
for mkv in "$SONARR_SYNC"/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  filename=$(basename "$mkv")
  PAYLOAD=$(jq -n --arg name "DownloadedEpisodesScan" --arg path "/downloads/$filename" \
    '{name: $name, path: $path}')
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$SONARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    echo "Sonarr scan submitted: $filename"
  else
    echo "Sonarr scan ERROR: $filename — $RESPONSE"
  fi
done

# Radarr loose .mkv files
for mkv in "$RADARR_SYNC"/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  filename=$(basename "$mkv")
  PAYLOAD=$(jq -n --arg name "DownloadedMoviesScan" --arg path "/downloads/$filename" \
    '{name: $name, path: $path}')
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$RADARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    echo "Radarr scan submitted: $filename"
  else
    echo "Radarr scan ERROR: $filename — $RESPONSE"
  fi
done

# =============================================================================
# STEP 6 — Wait for Sonarr/Radarr to process imports
# =============================================================================
sleep 180

# =============================================================================
# STEP 7 — Confirm imports by checking whether video files are gone
# Only set .imported after files are confirmed absent from the sync path.
# This is the only place .imported is created for successful imports.
# =============================================================================

# Sonarr subfolders
for item in "$SONARR_SYNC"/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  if confirm_import "$item"; then
    touch "${item}.imported"
    echo "Sonarr confirmed import: $(basename "$item")"
  else
    echo "Sonarr files still present (pending or failed): $(basename "$item")"
  fi
done

# Radarr subfolders
for item in "$RADARR_SYNC"/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  if confirm_import "$item"; then
    touch "${item}.imported"
    echo "Radarr confirmed import: $(basename "$item")"
  else
    echo "Radarr files still present (pending or failed): $(basename "$item")"
  fi
done

# Sonarr loose .mkv files
for mkv in "$SONARR_SYNC"/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  if confirm_import "$mkv"; then
    touch "${mkv}.imported"
    echo "Sonarr confirmed import: $(basename "$mkv")"
  else
    echo "Sonarr file still present (pending or failed): $(basename "$mkv")"
  fi
done

# Radarr loose .mkv files
for mkv in "$RADARR_SYNC"/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  if confirm_import "$mkv"; then
    touch "${mkv}.imported"
    echo "Radarr confirmed import: $(basename "$mkv")"
  else
    echo "Radarr file still present (pending or failed): $(basename "$mkv")"
  fi
done

# =============================================================================
# STEP 8 — RefreshMonitoredDownloads (second pass)
# Run after imports to clear completed queue entries.
# =============================================================================
curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$SONARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$RADARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $LIDARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$LIDARR/api/v3/command" > /dev/null
