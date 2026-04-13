# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** April 2026  
**Server:** Caladan (192.168.1.12) — Unraid  

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [arr-rescans Script](#5-arr-rescans-script-unraid-user-scripts)
6. [arr-import-monitor Script](#6-arr-import-monitor-script-unraid-user-scripts)
7. [Known Issues & Workarounds](#7-known-issues--workarounds)
8. [Maintenance Procedures](#8-maintenance-procedures)
9. [Rebuild Checklist](#9-rebuild-checklist)

---

## 1. Infrastructure Overview

### Architecture

```
qBittorrent (Seedbox) → Syncthing → /downloads (Caladan) → Unpackarr → Sonarr / Radarr / Lidarr → Plex
```

### Key Infrastructure

| Component | Value |
|-----------|-------|
| Caladan IP | 192.168.1.12 |
| Caladan OS | Unraid |
| Seedbox Host | scytale1953.ibiza.seedhost.eu |
| Seedbox User | scytale1953 |
| Seedbox Base Path | /home18/scytale1953/ |
| Media Sync Path (Seedbox) | ~/Media-sync/ |
| Media Sync Path (Caladan) | /mnt/user/media/download/sync/ |
| Syncthing Folder ID | sfqzb-cvm5v |
| Caladan Syncthing Port | 8384 |

---

## 2. Seedbox Configuration (seedhost.eu)

### 2.1 qBittorrent

qBittorrent is the active download client. Available at: `https://ibiza.seedhost.eu/scytale1953/qbittorrent/`

**Tools → Options → Downloads:**
- Default Save Path: `/home18/scytale1953/Media-sync/`

**Tools → Options → BitTorrent (Seeding Limits):**
- When ratio reaches: disabled (0)
- When seeding time reaches: 20160 minutes (14 days)
- Then: Remove torrent and files

> qBittorrent automatically cleans up Media-sync files after 14 days seeding. No manual cleanup or cron job is needed.

> Archive extraction is handled on Caladan by Unpackarr — no seedbox-side extraction scripts or qBittorrent completion hooks are required.

### 2.2 qBittorrent Download Categories

Each *arr app uses a category tag to identify downloads:

| Category | Save Path |
|----------|-----------|
| sonarr | /home18/scytale1953/Media-sync/sonarr/ |
| radarr | /home18/scytale1953/Media-sync/radarr/ |
| lidarr | /home18/scytale1953/Media-sync/lidarr/ |

### 2.3 Seedbox Cron

Only one cron entry is needed — the Syncthing watchdog:

```cron
MAILTO=""
*/5 * * * * /bin/bash ~/software/cron/syncthing
```

### 2.4 ruTorrent (Legacy — no longer used as download client)

ruTorrent is still installed but qBittorrent is used for all *arr downloads. If switching back:

- Ratio plugin MAX_RATIO is set to 9999 to prevent early removal
- File: `~/www/scytale1953.ibiza.seedhost.eu/scytale1953/rutorrent/plugins/ratio/conf.php`
- Ratio group 1 (ratioDef): Min% 0, Max% 0, UL 0, Time 336h, Action: Remove

### 2.5 Media-sync Folder Structure

| Directory | Purpose |
|-----------|---------|
| sonarr/ | TV downloads — synced to Caladan |
| radarr/ | Movie downloads — synced to Caladan |
| lidarr/ | Music downloads — synced to Caladan |
| freeleech/ | Freeleech downloads — NOT synced (ignored) |
| prowlarr/ | Prowlarr test downloads — NOT synced (ignored) |
| radarr-4k/ | 4K movies — NOT synced (ignored) |
| foo/ | Miscellaneous — NOT synced (ignored) |

---

## 3. Syncthing Configuration

### 3.1 Caladan Syncthing Container

| Setting | Value |
|---------|-------|
| Container Name | binhex-syncthing |
| Image | binhex/arch-syncthing |
| Network Mode | host |
| Web UI Port | 8384 |
| Config Path | /mnt/user/appdata/binhex-syncthing/ |
| Sync Mount | /mnt/user/media/download/sync/ → /media/sync |

### 3.2 Folder Configuration

| Setting | Value |
|---------|-------|
| Folder ID | sfqzb-cvm5v |
| Folder Name | Media sync |
| Caladan Path | /mnt/user/media/download/sync/ (host) = /media/sync (container) |
| Seedbox Path | ~/Media-sync/ |
| Folder Type (Caladan) | Receive Only |
| Folder Type (Seedbox) | Send Only |
| Rescan Interval | 1 hour |

### 3.3 Ignore Patterns

**CRITICAL:** Exceptions must come BEFORE the wildcard. Order matters — first match wins.

File location: `/mnt/user/media/download/sync/.stignore`

```
!/sonarr
!/sonarr/**
!/radarr
!/radarr/**
!/lidarr
!/lidarr/**
*
```

### 3.4 Checking Sync Status via CLI

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

Add as a bash alias in `~/.bashrc`:

```bash
alias syncstatus='STKEY=$(grep -o "<apikey>[^<]*" /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d">" -f2) && curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"'
```

### 3.5 Revert Local Changes

When Syncthing shows "Local Additions" and is not syncing new content, use the **Revert Local Changes** button in the Syncthing UI. Safe because Caladan is Receive Only and qBittorrent manages file lifecycle.

---

## 4. *arr Application Configuration

### 4.1 Docker Container Path Mappings

| App | Host Path | Container Path | Port |
|-----|-----------|---------------|------|
| Sonarr | /mnt/user/media/download/sync/sonarr/ | /downloads | 8989 |
| Radarr | /mnt/user/media/download/sync/radarr/ | /downloads | 7878 |
| Lidarr | /mnt/user/media/download/sync/lidarr/ | /downloads | 8686 |

Media library mounts:
- Sonarr: `/mnt/user/media/tv/` → `/tv`
- Radarr: `/mnt/user/media/films/` → `/movies`
- Lidarr: `/mnt/user/media/mp3/Rock/` → `/music`

> **Note:** Lidarr does not include a /downloads mapping by default — add it manually.

### 4.2 Download Client Configuration (All *arrs)

| Setting | Value |
|---------|-------|
| Client Type | qBittorrent |
| Name | seedhost.eu |
| Host | ibiza.seedhost.eu |
| Port | 443 |
| URL Base | /scytale1953/qbittorrent |
| SSL | Yes |
| Username | scytale1953 |
| Category | sonarr / radarr / lidarr (per app) |
| Post-Import Category | blank |
| Remove Completed | Unchecked |

> Enable Advanced Settings in the dialog to see the URL Base field.

### 4.3 Remote Path Mappings

| App | Remote Path (Seedbox) | Local Path (Container) |
|-----|-----------------------|------------------------|
| Sonarr | /home18/scytale1953/Media-sync | /downloads/ |
| Radarr | /home18/scytale1953/Media-sync | /downloads/ |
| Lidarr | /home18/scytale1953/Media-sync | /downloads/ |

> Remote path must be the base path without trailing slash or app subfolder. Host must be `ibiza.seedhost.eu`.

### 4.4 API Keys

Stored in `/boot/config/arr-rescans.conf` — see Section 5.1.

### 4.5 Quality Profile (HD-1080p)

- Upgrades Allowed: Yes
- Upgrade Until: Bluray-1080p
- Quality order: Remux-1080p, Bluray-1080p, WEB 1080p, HDTV-1080p

### 4.6 Unpackarr

Unpackarr runs as a Docker container on Caladan. It monitors the sync download folders and automatically extracts RAR archives after torrents complete, placing the extracted video files alongside the archive so the *arrs can import them. There is no web UI and no port mapping.

#### Container Configuration

| Setting | Value |
|---------|-------|
| Container Name | unpackarr |
| Downloads Mount | /mnt/user/media/download/sync/ → /downloads |
| No port mapping | No web UI |

#### Environment Variables

| Variable | Value |
|----------|-------|
| UN_DEBUG | false |
| UN_LOG_FILE | /downloads/unpackarr.log |
| UN_SONARR_0_URL | http://192.168.1.12:8989 |
| UN_SONARR_0_API_KEY | (Sonarr API key) |
| UN_SONARR_0_PATH | /sonarr |
| UN_RADARR_0_URL | http://192.168.1.12:7878 |
| UN_RADARR_0_API_KEY | (Radarr API key) |
| UN_RADARR_0_PATH | /radarr |

> Lidarr is not currently configured in Unpackarr as music releases are not typically distributed as archives.

> The log file `/downloads/unpackarr.log` maps to `/mnt/user/media/download/sync/unpackarr.log` on the host.

#### How It Works

Unpackarr polls Sonarr and Radarr for completed downloads. When it finds a completed item whose folder contains a RAR archive and no extracted video file, it extracts the archive in place. The *arrs then find the video file on the next arr-rescans pass.

---

## 5. arr-rescans Script (Unraid User Scripts)

### 5.1 External Config File

Sensitive values are stored outside the script in `/boot/config/arr-rescans.conf`. This file persists across reboots and is never committed to git.

```bash
# /boot/config/arr-rescans.conf
SONARR_KEY="your_sonarr_api_key"
RADARR_KEY="your_radarr_api_key"
LIDARR_KEY="your_lidarr_api_key"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
VIDEO_EXTENSIONS="mkv mp4 avi m4v"

# Optional overrides for arr-import-monitor thresholds:
# IMPORT_ALERT_THRESHOLD=30      # minutes before alerting (default 30)
# IMPORT_REALERT_SECONDS=3600    # seconds before re-alerting same item (default 1 hour)
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

To update the Discord webhook, API keys, or video extensions, edit only this file — never touch the scripts.

### 5.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
- **Schedule:** `*/5 * * * *` (every 5 minutes)

### 5.3 Script Contents (v4.3)

```bash
#!/bin/bash
# arr-rescans v4.3
# Core function: trigger *arr scans on synced download folders.
# Import detection via Sonarr/Radarr history API — no marker files required.
# Alerting on stuck imports is handled separately by arr-import-monitor.
#
# Schedule: */5 * * * *

# Load external config
if [ ! -f /boot/config/arr-rescans.conf ]; then
  /usr/local/emhttp/webGui/scripts/notify \
    -e "arr-rescans" \
    -s "arr-rescans config missing" \
    -d "Config file /boot/config/arr-rescans.conf not found. Script cannot run." \
    -i "alert"
  exit 1
fi
source /boot/config/arr-rescans.conf

SONARR="http://192.168.1.12:8989"
RADARR="http://192.168.1.12:7878"
LIDARR="http://192.168.1.12:8686"

# Send Discord notification with Unraid fallback
send_notification() {
  local message="$1"
  local MSG=$(jq -n --arg msg "$message" '{content: $msg}')
  local HTTP_CODE=$(curl -s -o /tmp/discord_response.json -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "$MSG" "$DISCORD_WEBHOOK")
  if [ "$HTTP_CODE" != "204" ]; then
    local ERROR=$(cat /tmp/discord_response.json 2>/dev/null)
    /usr/local/emhttp/webGui/scripts/notify \
      -e "arr-rescans" \
      -s "Discord webhook error" \
      -d "HTTP $HTTP_CODE: $ERROR — Message: $message" \
      -i "warning"
    echo "Discord failed (HTTP $HTTP_CODE), sent Unraid notification"
  fi
}

# Build find arguments from VIDEO_EXTENSIONS in conf
find_videos() {
  local path="$1"
  local depth="${2:-2}"
  local cmd=(find "$path" -maxdepth "$depth" -type f)
  local first=1
  cmd+=(\()
  for ext in $VIDEO_EXTENSIONS; do
    [ $first -eq 0 ] && cmd+=(-o)
    cmd+=(-iname "*.$ext")
    first=0
  done
  cmd+=(\))
  "${cmd[@]}"
}

# Fetch import history once per app — eventType 3 = downloadFolderImported
# pageSize 1000 covers all but the most extreme history volumes
echo "Fetching Sonarr import history..."
SONARR_HISTORY=$(curl -s \
  "$SONARR/api/v3/history?pageSize=1000&eventType=3&apikey=$SONARR_KEY" | \
  jq -r '.records[].data.droppedPath // empty')

echo "Fetching Radarr import history..."
RADARR_HISTORY=$(curl -s \
  "$RADARR/api/v3/history?pageSize=1000&eventType=3&apikey=$RADARR_KEY" | \
  jq -r '.records[].data.droppedPath // empty')

# Returns 0 (true) if the given name appears in the provided history string
in_history() {
  local name="$1"
  local history="$2"
  grep -qF "$name" <<< "$history"
}

# Refresh tracked queue items
curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$SONARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$RADARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $LIDARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$LIDARR/api/v3/command" > /dev/null

# Check for suspicious files - sonarr subfolders
for item in /mnt/user/media/download/sync/sonarr/*/; do
  [ -d "$item" ] || continue
  folder=$(basename "$item")
  in_history "$folder" "$SONARR_HISTORY" && continue
  SUSPICIOUS=$(find "$item" -type f \( -iname "*.exe" -o -iname "*.bat" -o -iname "*.com" -o -iname "*.scr" -o -iname "*.js" -o -iname "*.vbs" \) | wc -l)
  if [ "$SUSPICIOUS" -gt 0 ]; then
    send_notification "🚨 **Suspicious files in Sonarr download**: \`$folder\` contains $SUSPICIOUS potentially malicious file(s). Import skipped — manual review required."
    echo "SUSPICIOUS: $folder"
  fi
done

# Check for suspicious files - radarr subfolders
for item in /mnt/user/media/download/sync/radarr/*/; do
  [ -d "$item" ] || continue
  folder=$(basename "$item")
  in_history "$folder" "$RADARR_HISTORY" && continue
  SUSPICIOUS=$(find "$item" -type f \( -iname "*.exe" -o -iname "*.bat" -o -iname "*.com" -o -iname "*.scr" -o -iname "*.js" -o -iname "*.vbs" \) | wc -l)
  if [ "$SUSPICIOUS" -gt 0 ]; then
    send_notification "🚨 **Suspicious files in Radarr download**: \`$folder\` contains $SUSPICIOUS potentially malicious file(s). Import skipped — manual review required."
    echo "SUSPICIOUS: $folder"
  fi
done

# Scan sonarr subfolders - skip if folder appears in import history
for item in /mnt/user/media/download/sync/sonarr/*/; do
  [ -d "$item" ] || continue
  folder=$(basename "$item")
  if in_history "$folder" "$SONARR_HISTORY"; then
    echo "Sonarr skip (imported): $folder"
    continue
  fi
  PAYLOAD=$(jq -n --arg name "DownloadedEpisodesScan" --arg path "/downloads/$folder" \
    '{name: $name, path: $path}')
  curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$SONARR/api/v3/command" > /dev/null
  echo "Sonarr scan queued: $folder"
done

# Scan radarr subfolders - skip if folder appears in import history
for item in /mnt/user/media/download/sync/radarr/*/; do
  [ -d "$item" ] || continue
  folder=$(basename "$item")
  if in_history "$folder" "$RADARR_HISTORY"; then
    echo "Radarr skip (imported): $folder"
    continue
  fi
  PAYLOAD=$(jq -n --arg name "DownloadedMoviesScan" --arg path "/downloads/$folder" \
    '{name: $name, path: $path}')
  curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$RADARR/api/v3/command" > /dev/null
  echo "Radarr scan queued: $folder"
done

# Scan loose sonarr video files - skip if filename appears in import history
for ext in $VIDEO_EXTENSIONS; do
  for vid in /mnt/user/media/download/sync/sonarr/*.$ext; do
    [ -f "$vid" ] || continue
    filename=$(basename "$vid")
    if in_history "$filename" "$SONARR_HISTORY"; then
      echo "Sonarr skip (imported): $filename"
      continue
    fi
    PAYLOAD=$(jq -n --arg name "DownloadedEpisodesScan" --arg path "/downloads/$filename" \
      '{name: $name, path: $path}')
    curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
      -d "$PAYLOAD" "$SONARR/api/v3/command" > /dev/null
    echo "Sonarr scan queued: $filename"
  done
done

# Scan loose radarr video files - skip if filename appears in import history
for ext in $VIDEO_EXTENSIONS; do
  for vid in /mnt/user/media/download/sync/radarr/*.$ext; do
    [ -f "$vid" ] || continue
    filename=$(basename "$vid")
    if in_history "$filename" "$RADARR_HISTORY"; then
      echo "Radarr skip (imported): $filename"
      continue
    fi
    PAYLOAD=$(jq -n --arg name "DownloadedMoviesScan" --arg path "/downloads/$filename" \
      '{name: $name, path: $path}')
    curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
      -d "$PAYLOAD" "$RADARR/api/v3/command" > /dev/null
    echo "Radarr scan queued: $filename"
  done
done
```

### 5.4 Script Design Notes

**History API import detection** — import status is determined by querying the Sonarr/Radarr history API for `eventType=3` (downloadFolderImported). The `droppedPath` field contains the source folder/file name. No marker files are used or required.

**`find_videos` helper** — builds a `find` command dynamically from `VIDEO_EXTENSIONS` in the conf file. Adding support for a new container format requires only a conf edit.

**`VIDEO_EXTENSIONS` in conf** — list of video file extensions used for loose file scanning. Stored in `arr-rescans.conf` alongside credentials so all extension changes are in one place.

**`in_history` function** — simple grep against the pre-fetched history string. History is fetched once per run, not per folder, to avoid hammering the API.

**`send_notification` function** — sends to Discord, falls back to Unraid native notification if Discord returns a non-204 response.

**jq `--arg` payload builder** — safely handles special characters in folder names including brackets, spaces, and apostrophes common in anime and foreign language releases.

**Suspicious file detection** — alerts Discord for folders containing .exe, .bat, .com, .scr, .js, or .vbs files.

**Alerting fully delegated** — stuck import alerts are not part of this script. See Section 6 (arr-import-monitor).

**Stale Radarr queue entries** — when imports happen via DownloadedMoviesScan rather than through the normal queue flow, Radarr may retain stale completed queue entries. Clear manually via Radarr → Activity → Queue or via API:

```bash
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

---

## 6. arr-import-monitor Script (Unraid User Scripts)

### 6.1 Overview

A separate script that runs every 15 minutes and queries the *arr queue APIs directly. It identifies items stuck in `importPending` or `importFailed` states beyond a configurable threshold and sends Discord alerts with per-item deduplication via a state file.

Alerting is intentionally kept out of arr-rescans so each script has a single responsibility.

### 6.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-import-monitor/script`
- **Schedule:** `*/15 * * * *` (every 15 minutes)

### 6.3 Configurable Thresholds

Add these optional overrides to `/boot/config/arr-rescans.conf`:

```bash
IMPORT_ALERT_THRESHOLD=30      # minutes in stuck state before alerting (default 30)
IMPORT_REALERT_SECONDS=3600    # seconds before re-alerting the same item (default 1 hour)
```

### 6.4 Script Contents (v1.1)

```bash
#!/bin/bash

# arr-import-monitor v1.1
# Queries *arr queue APIs for items stuck in importPending or importFailed
# and sends Discord alerts with per-item deduplication.
# Schedule: */15 * * * *

# Load external config
if [ ! -f /boot/config/arr-rescans.conf ]; then
  /usr/local/emhttp/webGui/scripts/notify \
    -e "arr-import-monitor" \
    -s "arr-import-monitor config missing" \
    -d "Config file /boot/config/arr-rescans.conf not found. Script cannot run." \
    -i "alert"
  exit 1
fi
source /boot/config/arr-rescans.conf

SONARR="http://192.168.1.12:8989"
RADARR="http://192.168.1.12:7878"
LIDARR="http://192.168.1.12:8686"

# Configurable thresholds — override in arr-rescans.conf if desired
THRESHOLD=${IMPORT_ALERT_THRESHOLD:-30}
REALERT=${IMPORT_REALERT_SECONDS:-3600}

STATE_FILE="/tmp/arr-import-monitor.state"
touch "$STATE_FILE"

# Send Discord notification with Unraid fallback
send_notification() {
  local message="$1"
  local MSG=$(jq -n --arg msg "$message" '{content: $msg}')
  local HTTP_CODE=$(curl -s -o /tmp/discord_response.json -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "$MSG" "$DISCORD_WEBHOOK")
  if [ "$HTTP_CODE" != "204" ]; then
    local ERROR=$(cat /tmp/discord_response.json 2>/dev/null)
    /usr/local/emhttp/webGui/scripts/notify \
      -e "arr-import-monitor" \
      -s "Discord webhook error" \
      -d "HTTP $HTTP_CODE: $ERROR — Message: $message" \
      -i "warning"
    echo "Discord failed (HTTP $HTTP_CODE), sent Unraid notification"
  fi
}

# Check if we should alert for this item based on deduplication state
# Returns 0 (should alert) or 1 (suppress)
should_alert() {
  local key="$1"
  local now=$(date +%s)
  local last_alerted=$(grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
  if [ -z "$last_alerted" ]; then
    return 0
  fi
  local elapsed=$(( now - last_alerted ))
  if [ "$elapsed" -ge "$REALERT" ]; then
    return 0
  fi
  return 1
}

# Record alert timestamp for deduplication
record_alert() {
  local key="$1"
  local now=$(date +%s)
  local tmp=$(mktemp)
  grep -v "^${key}=" "$STATE_FILE" > "$tmp" 2>/dev/null
  echo "${key}=${now}" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# Remove state entries for items no longer in the queue
prune_state() {
  local -n active_keys=$1
  local tmp=$(mktemp)
  while IFS='=' read -r key ts; do
    [ -z "$key" ] && continue
    local found=0
    for active in "${active_keys[@]}"; do
      [ "$active" = "$key" ] && found=1 && break
    done
    [ $found -eq 1 ] && echo "${key}=${ts}" >> "$tmp"
  done < "$STATE_FILE"
  mv "$tmp" "$STATE_FILE"
}

# Process queue for a single *arr instance
# Args: $1=app_name $2=base_url $3=api_key
check_queue() {
  local app="$1"
  local url="$2"
  local key="$3"
  local now=$(date +%s)
  local active_keys=()

  local queue
  queue=$(curl -s -H "X-Api-Key: $key" \
    "${url}/api/v3/queue?pageSize=200&includeUnknownMovieItems=true&includeUnknownSeriesItems=true")

  if [ -z "$queue" ] || ! echo "$queue" | jq -e '.records' > /dev/null 2>&1; then
    echo "${app}: failed to fetch queue or empty response"
    return
  fi

  local count
  count=$(echo "$queue" | jq '.records | length')
  echo "${app}: ${count} queue items found"

  while IFS= read -r record; do
    local id title status error_msg

    id=$(echo "$record"        | jq -r '.id')
    title=$(echo "$record"     | jq -r '.title // "Unknown"')
    status=$(echo "$record"    | jq -r '.status // ""')
    error_msg=$(echo "$record" | jq -r '.errorMessage // ""')

    case "$status" in
      importPending|importFailed) ;;
      *) continue ;;
    esac

    local state_key="${app}:${id}"
    active_keys+=("$state_key")

    # First-seen tracking for age calculation
    local first_seen
    first_seen=$(grep "^${state_key}_first=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    if [ -z "$first_seen" ]; then
      echo "${state_key}_first=${now}" >> "$STATE_FILE"
      first_seen=$now
    fi
    active_keys+=("${state_key}_first")

    local age_minutes=$(( (now - first_seen) / 60 ))

    if [ "$age_minutes" -lt "$THRESHOLD" ]; then
      echo "${app}: '${title}' in ${status} for ${age_minutes}m — below threshold, skipping"
      continue
    fi

    if should_alert "$state_key"; then
      local icon="⚠️"
      local label="stuck"
      if [ "$status" = "importFailed" ]; then
        icon="❌"
        label="failed"
      fi

      local msg="${icon} **${app}**: \`${title}\` has ${label} import for ${age_minutes} minutes"
      if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
        msg="${msg} — ${error_msg}"
      fi

      send_notification "$msg"
      record_alert "$state_key"
      echo "${app}: alerted for '${title}' (${status}, ${age_minutes}m)"
    else
      echo "${app}: '${title}' (${status}, ${age_minutes}m) — suppressed, recently alerted"
    fi

  done < <(echo "$queue" | jq -c '.records[]')

  prune_state active_keys
}

check_queue "Sonarr" "$SONARR" "$SONARR_KEY"
check_queue "Radarr" "$RADARR" "$RADARR_KEY"
check_queue "Lidarr" "$LIDARR" "$LIDARR_KEY"

echo "arr-import-monitor complete"
```

### 6.5 Script Design Notes

**Separation of concerns** — this script only alerts; it never triggers scans. arr-rescans only scans; it never alerts. Each script does one thing.

**First-seen tracking** — age is calculated from when the monitor first noticed the item in a stuck state, stored in the state file as `key_first`. This is more reliable than API time fields, which are inconsistent across *arr versions.

**Per-item deduplication** — each queue item gets a `app:id` key in the state file. Alerts are suppressed until `IMPORT_REALERT_SECONDS` has elapsed since the last alert for that item.

**State file pruning** — `prune_state` removes entries for items that have left the queue, keeping the state file from growing unboundedly.

**State file location** — `/tmp/arr-import-monitor.state` is cleared on reboot, which is intentional. Stuck items from before a reboot will be re-evaluated fresh.

**Ghost queue entries** — when a replacement release is grabbed and imported, the original queue entry can remain orphaned in `importPending`. Diagnosis: query the library API and check `hasFile: true`. Resolution: bulk delete via `/queue/bulk` with `removeFromClient=false&blocklist=false`.

---

## 7. Known Issues & Workarounds

### 7.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 7.2 Anime Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most via alias matching. The jq payload builder handles bracket characters in SubsPlease folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 7.3 Syncthing Race Condition

arr-rescans runs every 5 minutes. Files mid-sync when the script runs will be scanned on the next pass. History-based import detection means there is no risk of double-importing.

### 7.4 Syncthing Local Additions

After deleting imported files locally, Syncthing tracks these as "Locally Changed Items". Click Revert Local Changes to reset when needed.

### 7.5 Season Pack Imports

Require Interactive Import in Sonarr. Use Wanted > Manual Import > folder > Interactive Import.

### 7.6 Fake/Malicious Torrents

The rescan script detects .exe and other suspicious files and sends a Discord alert. Blocklist the release in Sonarr/Radarr to trigger a search for a valid release.

### 7.7 Remote Path Mapping Host

qBittorrent remote path mapping host must be `ibiza.seedhost.eu`. Remote path must be `/home18/scytale1953/Media-sync` without trailing slash or app subfolder.

### 7.8 Foreign Language Series Title Mismatches

Sonarr stores the TVDB canonical title regardless of search term used when adding. If a series is only available under a foreign title (e.g. "La Oficina" vs "The Office (MX)"), submit the alias to TVDB. Once approved, refresh the series in Sonarr to pull in the alias.

### 7.9 Archived Downloads Not Importing

If Unpackarr has not yet extracted an archive when arr-rescans fires, the *arrs will find nothing importable in the folder. Unpackarr polls on its own schedule and will extract shortly after; arr-rescans will pick up the extracted file on the next 5-minute pass. If a folder remains unimported beyond the arr-import-monitor threshold, check the Unpackarr log:

```bash
tail -50 /mnt/user/media/download/sync/unpackarr.log
```

### 7.10 Ghost Queue Entries (importPending orphans)

When a replacement release is grabbed and imported, the original queue entry can remain orphaned in `importPending`. Diagnosis:

```bash
curl -s "http://192.168.1.12:8989/api/v3/queue?pageSize=200" \
  -H "X-Api-Key: $SONARR_KEY" | jq '.records[] | select(.status=="importPending") | {id, title}'
```

Resolution — bulk delete with no client removal and no blocklist:

```bash
curl -s -X DELETE "http://192.168.1.12:8989/api/v3/queue/bulk" \
  -H "X-Api-Key: $SONARR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"ids":[ID1,ID2],"removeFromClient":false,"blocklist":false}'
```

### 7.11 Clearing Stale Radarr Queue Entries

When imports happen via DownloadedMoviesScan rather than through the normal queue flow, Radarr may retain stale completed queue entries.

```bash
# Get queue IDs
curl -s "http://192.168.1.12:7878/api/v3/queue?apikey=YOUR_RADARR_KEY" | jq '.records[] | {id, title, status}'

# Delete a specific entry
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: YOUR_RADARR_KEY"
```

---

## 8. Maintenance Procedures

### 8.1 Manual Sync Folder Cleanup

On Caladan:
```bash
rm -rf /mnt/user/media/download/sync/sonarr/*
rm -rf /mnt/user/media/download/sync/radarr/*
rm -rf /mnt/user/media/download/sync/lidarr/*
```

On seedbox (SSH):
```bash
rm -rf ~/Media-sync/sonarr/*
rm -rf ~/Media-sync/radarr/*
rm -rf ~/Media-sync/lidarr/*
```

After cleaning both sides, click **Revert Local Changes** in Caladan's Syncthing UI.

### 8.2 Checking Import Logs

```bash
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30
docker logs sonarr --since 1h 2>&1 | grep Error | tail -20
```

### 8.3 Forcing a Manual Rescan

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

### 8.4 Checking Sync Folder Contents

```bash
ls /mnt/user/media/download/sync/sonarr/
ls /mnt/user/media/download/sync/radarr/
ls /mnt/user/media/download/sync/lidarr/
```

### 8.5 Checking Syncthing Sync Status

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

### 8.6 Updating Discord Webhook or API Keys

```bash
nano /boot/config/arr-rescans.conf
```

### 8.7 Checking Unpackarr Logs

```bash
tail -50 /mnt/user/media/download/sync/unpackarr.log
```

Or via Docker logs:

```bash
docker logs unpackarr --since 1h
```

### 8.8 Clearing the Import Monitor State File

Useful if an item was resolved manually and you want to suppress re-alerts without waiting for the realert window:

```bash
# Clear all state
rm /tmp/arr-import-monitor.state

# Or remove a specific item's entry
sed -i '/^Sonarr:QUEUE_ID/d' /tmp/arr-import-monitor.state
```

---

## 9. Rebuild Checklist

### 9.1 Unraid Containers

- [ ] Deploy binhex-syncthing with host networking on port 8384
- [ ] Deploy Sonarr (linuxserver/sonarr) on port 8989
- [ ] Deploy Radarr (linuxserver/radarr) on port 7878
- [ ] Deploy Lidarr (linuxserver/lidarr) on port 8686
- [ ] Deploy Unpackarr per Section 4.6 (no port mapping)
- [ ] Configure all volume mounts per Section 4.1
- [ ] **Manually add /downloads mapping to Lidarr**

### 9.2 Syncthing

- [ ] Add Media sync folder with ID `sfqzb-cvm5v`
- [ ] Set folder type to **Receive Only**
- [ ] Set folder path to `/media/sync` (container path)
- [ ] Add seedbox as remote device
- [ ] Create `/mnt/user/media/download/sync/.stignore` per Section 3.3
- [ ] **Verify ignore pattern order: exceptions FIRST, wildcard LAST**

### 9.3 *arr Apps

- [ ] Add qBittorrent download client per Section 4.2
- [ ] Add remote path mappings per Section 4.3
- [ ] Configure quality profiles
- [ ] Verify /downloads container mount present in all three apps
- [ ] Connect Discord notifications in Sonarr/Radarr

### 9.4 Seedbox

- [ ] Verify qBittorrent save path is `/home18/scytale1953/Media-sync/`
- [ ] Verify qBittorrent seeding limits (20160 min, remove torrent and files)
- [ ] Verify Syncthing cron is present
- [ ] Verify Syncthing connected to Caladan device ID

### 9.5 User Scripts

- [ ] Install User Scripts plugin in Unraid
- [ ] Create `/boot/config/arr-rescans.conf` with API keys, Discord webhook, and VIDEO_EXTENSIONS
- [ ] `chmod 600 /boot/config/arr-rescans.conf`
- [ ] Create `arr-rescans` script (v4.3) per Section 5.3
- [ ] Set arr-rescans schedule to `*/5 * * * *`
- [ ] Create `arr-import-monitor` script (v1.1) per Section 6.4
- [ ] Set arr-import-monitor schedule to `*/15 * * * *`
- [ ] Test both scripts by running manually
- [ ] Verify Discord alerts received

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*  
*Note: Never commit arr-rescans.conf to git — it contains sensitive credentials*
