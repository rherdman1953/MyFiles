# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** March 2026  
**Server:** Caladan (192.168.1.12) — Unraid  

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Rescan Script — arr-rescans](#5-rescan-script--arr-rescans)
6. [Import Monitor Script — arr-import-monitor](#6-import-monitor-script--arr-import-monitor)
7. [Known Issues & Workarounds](#7-known-issues--workarounds)
8. [Maintenance Procedures](#8-maintenance-procedures)
9. [Rebuild Checklist](#9-rebuild-checklist)

---

## 1. Infrastructure Overview

### Architecture

```
qBittorrent (Seedbox) → Syncthing → /downloads (Caladan) → Sonarr / Radarr / Lidarr → Plex
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

---

## 5. Rescan Script — arr-rescans

**Version:** 3.0  
**Schedule:** `*/5 * * * *`  
**Purpose:** Triggers *arr scan commands on synced download folders. Does not handle alerting — that is the responsibility of arr-import-monitor (Section 6).

### 5.1 External Config File

Sensitive values are stored outside the script in `/boot/config/arr-rescans.conf`. This file persists across reboots and is never committed to git. It is shared by both arr-rescans and arr-import-monitor.

```bash
# /boot/config/arr-rescans.conf

# Required — API keys and Discord webhook
SONARR_KEY="your_sonarr_api_key"
RADARR_KEY="your_radarr_api_key"
LIDARR_KEY="your_lidarr_api_key"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"

# Optional — arr-import-monitor tuning (defaults shown)
# IMPORT_ALERT_THRESHOLD=120    # Minutes before alerting on a stuck import
# IMPORT_REALERT_SECONDS=86400  # Seconds before re-alerting on a still-stuck import (default 24h)
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

To update the Discord webhook or API keys, edit only this file — never touch the scripts.

### 5.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
- **Schedule:** `*/5 * * * *` (every 5 minutes)

### 5.3 Script Contents

```bash
#!/bin/bash
# arr-rescans v3.0
# Core function: trigger *arr scans on synced download folders.
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
SYNC_BASE="/mnt/user/media/download/sync"

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
  fi
}

# ─── Clean up orphaned marker files for loose .mkv files ─────────────────────
for marker in \
  "$SYNC_BASE"/sonarr/*.mkv.imported \
  "$SYNC_BASE"/sonarr/*.mkv.first_seen \
  "$SYNC_BASE"/radarr/*.mkv.imported \
  "$SYNC_BASE"/radarr/*.mkv.first_seen; do
  [ -f "$marker" ] || continue
  base="${marker%.imported}"
  base="${base%.first_seen}"
  [ -f "$base" ] || rm -f "$marker"
done

# ─── Suspicious file detection ────────────────────────────────────────────────
check_suspicious() {
  local app_label="$1"
  local dir="$2"
  for item in "$dir"/*/; do
    [ -d "$item" ] || continue
    [ -f "${item}.imported" ] && continue
    local SUSPICIOUS
    SUSPICIOUS=$(find "$item" -type f \( \
      -iname "*.exe" -o -iname "*.bat" -o -iname "*.com" \
      -o -iname "*.scr" -o -iname "*.js" -o -iname "*.vbs" \
    \) | wc -l)
    if [ "$SUSPICIOUS" -gt 0 ]; then
      local folder
      folder=$(basename "$item")
      send_notification "🚨 **${app_label}**: \`${folder}\` contains ${SUSPICIOUS} suspicious file(s). Import skipped — manual review required."
      touch "${item}.imported"
      echo "SUSPICIOUS: $folder"
    fi
  done
}

check_suspicious "Sonarr" "$SYNC_BASE/sonarr"
check_suspicious "Radarr" "$SYNC_BASE/radarr"

# ─── Refresh monitored downloads (first pass) ─────────────────────────────────
curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$SONARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$RADARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $LIDARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$LIDARR/api/v3/command" > /dev/null

# ─── Scan sonarr subfolders ───────────────────────────────────────────────────
for item in "$SYNC_BASE/sonarr"/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  folder=$(basename "$item")
  PAYLOAD=$(jq -n --arg name "DownloadedEpisodesScan" --arg path "/downloads/$folder" \
    '{name: $name, path: $path}')
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$SONARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    touch "${item}.imported"
    echo "Sonarr scan: $folder"
  fi
done

# ─── Scan radarr subfolders ───────────────────────────────────────────────────
for item in "$SYNC_BASE/radarr"/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  folder=$(basename "$item")
  PAYLOAD=$(jq -n --arg name "DownloadedMoviesScan" --arg path "/downloads/$folder" \
    '{name: $name, path: $path}')
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$RADARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    touch "${item}.imported"
    echo "Radarr scan: $folder"
  fi
done

# ─── Scan loose sonarr .mkv files ────────────────────────────────────────────
for mkv in "$SYNC_BASE/sonarr"/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  filename=$(basename "$mkv")
  PAYLOAD=$(jq -n --arg name "DownloadedEpisodesScan" --arg path "/downloads/$filename" \
    '{name: $name, path: $path}')
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$SONARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    touch "${mkv}.imported"
    echo "Sonarr scan: $filename"
  fi
done

# ─── Scan loose radarr .mkv files ────────────────────────────────────────────
for mkv in "$SYNC_BASE/radarr"/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  filename=$(basename "$mkv")
  PAYLOAD=$(jq -n --arg name "DownloadedMoviesScan" --arg path "/downloads/$filename" \
    '{name: $name, path: $path}')
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$RADARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    touch "${mkv}.imported"
    echo "Radarr scan: $filename"
  fi
done

# ─── Wait, then second pass RefreshMonitoredDownloads ─────────────────────────
sleep 180

curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$SONARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$RADARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $LIDARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$LIDARR/api/v3/command" > /dev/null
```

### 5.4 Script Design Notes

**External config file** — API keys, Discord webhook, and optional import monitor tuning stored in `/boot/config/arr-rescans.conf`, shared with arr-import-monitor. Never commit this file to git.

**send_notification function** — sends to Discord and falls back to Unraid native notification if Discord returns a non-204 response.

**DownloadedEpisodesScan / DownloadedMoviesScan per folder** — core import mechanism. Scans each subfolder individually. Also handles loose .mkv files directly.

**`.imported` marker file** — scan-efficiency guard only. Prevents the script from re-posting the same scan command every 5 minutes for folders that have already been processed. It does not indicate whether the import actually succeeded — that determination is made by arr-import-monitor via the queue API.

**jq `--arg` payload builder** — safely handles special characters in folder names including brackets, spaces, and apostrophes common in anime and foreign language releases.

**Suspicious file detection** — alerts Discord and skips import for folders containing .exe, .bat, .com, .scr, .js, or .vbs files.

**No alerting logic** — stuck import alerting was removed from this script in v3.0. It is handled entirely by arr-import-monitor, which uses the *arr queue APIs to determine actual import state rather than relying on filesystem marker files.

---

## 6. Import Monitor Script — arr-import-monitor

**Version:** 1.0  
**Schedule:** `*/15 * * * *`  
**Purpose:** Detects downloads that have not been imported after a configurable threshold by querying the *arr queue APIs. Sends Discord alerts with per-item deduplication.

### 6.1 How It Works

Each *arr app maintains a queue of tracked downloads. After a download completes, the app sets `trackedDownloadState` to `importPending` while it attempts to import the file, or `importFailed` if an import attempt was unsuccessful. This script queries those states directly — no filesystem markers or timestamps involved.

Items in `importPending` or `importFailed` state older than `THRESHOLD_MINUTES` trigger a Discord alert. The alert includes the status message from the *arr app (e.g. "No files found are eligible for import") which identifies the cause immediately.

Successfully imported items (`trackedDownloadState: imported`) and items still downloading are ignored.

### 6.2 Alert Deduplication

A state file at `/tmp/arr-import-monitor.state` tracks which queue items have already been alerted. Each entry records the app name, queue item ID, and the epoch timestamp of the first alert:

```
Sonarr:1234:1743174000
Radarr:5678:1743174000
```

Behaviour:
- First time an item is seen as stuck → alert fires, entry written to state file
- Subsequent runs within `REALERT_SECONDS` (default 24h) → suppressed
- After `REALERT_SECONDS` → re-alert fires, entry timestamp updated
- Entries older than 48 hours are purged (covers items that resolved or were cleared)
- State file is volatile (`/tmp/`) and does not persist across reboots — this is intentional; a reboot is a natural opportunity to re-evaluate all stuck items

### 6.3 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-import-monitor/script`
- **Schedule:** `*/15 * * * *` (every 15 minutes)

### 6.4 Script Contents

```bash
#!/bin/bash
# arr-import-monitor v1.0
# Queries Sonarr/Radarr/Lidarr queue APIs to detect downloads that have not
# been imported after a configurable threshold. Sends Discord alerts with
# per-item deduplication so each stuck download alerts once, then re-alerts
# after 24 hours if still unresolved.
#
# Schedule: */15 * * * *

# Load external config (shared with arr-rescans)
if [ ! -f /boot/config/arr-rescans.conf ]; then
  /usr/local/emhttp/webGui/scripts/notify \
    -e "arr-import-monitor" \
    -s "arr-import-monitor config missing" \
    -d "Config file /boot/config/arr-rescans.conf not found. Script cannot run." \
    -i "alert"
  exit 1
fi
source /boot/config/arr-rescans.conf

SONARR_URL="http://192.168.1.12:8989"
RADARR_URL="http://192.168.1.12:7878"
LIDARR_URL="http://192.168.1.12:8686"

# Configurable thresholds (override in arr-rescans.conf if desired)
THRESHOLD_MINUTES="${IMPORT_ALERT_THRESHOLD:-120}"
REALERT_SECONDS="${IMPORT_REALERT_SECONDS:-86400}"

STATE_FILE="/tmp/arr-import-monitor.state"
touch "$STATE_FILE"

# ─── Notification ─────────────────────────────────────────────────────────────
send_notification() {
  local message="$1"
  local MSG
  MSG=$(jq -n --arg msg "$message" '{content: $msg}')
  local HTTP_CODE
  HTTP_CODE=$(curl -s -o /tmp/discord_im_response.json -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "$MSG" "$DISCORD_WEBHOOK")
  if [ "$HTTP_CODE" != "204" ]; then
    local ERROR
    ERROR=$(cat /tmp/discord_im_response.json 2>/dev/null)
    /usr/local/emhttp/webGui/scripts/notify \
      -e "arr-import-monitor" \
      -s "Discord webhook error" \
      -d "HTTP $HTTP_CODE: $ERROR — Message: $message" \
      -i "warning"
    echo "Discord failed (HTTP $HTTP_CODE)"
  fi
}

# ─── State file management ───────────────────────────────────────────────────

clean_old_state() {
  local now
  now=$(date +%s)
  local cutoff=$(( now - 172800 ))  # 48h
  local tmpfile
  tmpfile=$(mktemp)
  while IFS= read -r line; do
    local ts
    ts=$(echo "$line" | cut -d: -f3)
    if [[ "$ts" =~ ^[0-9]+$ ]] && [ "$ts" -gt "$cutoff" ]; then
      echo "$line"
    fi
  done < "$STATE_FILE" > "$tmpfile"
  mv "$tmpfile" "$STATE_FILE"
}

should_alert() {
  local app="$1"
  local id="$2"
  local key="${app}:${id}"
  local now
  now=$(date +%s)

  local entry
  entry=$(grep "^${key}:" "$STATE_FILE" 2>/dev/null | tail -1)

  if [ -z "$entry" ]; then
    echo "${key}:${now}" >> "$STATE_FILE"
    return 0
  fi

  local first_alerted
  first_alerted=$(echo "$entry" | cut -d: -f3)
  local elapsed=$(( now - first_alerted ))

  if [ "$elapsed" -ge "$REALERT_SECONDS" ]; then
    sed -i "/^${key}:/d" "$STATE_FILE"
    echo "${key}:${now}" >> "$STATE_FILE"
    return 0
  fi

  return 1
}

# ─── Queue check per app ──────────────────────────────────────────────────────
check_app_queue() {
  local app_name="$1"
  local url="$2"
  local key="$3"
  local api_ver="${4:-v3}"

  local queue
  queue=$(curl -s -H "X-Api-Key: $key" \
    "${url}/api/${api_ver}/queue?pageSize=200&includeUnknownSeriesItems=true" 2>/dev/null)

  if [ -z "$queue" ] || ! echo "$queue" | jq -e '.records' > /dev/null 2>&1; then
    echo "[$app_name] ERROR: Failed to query queue API — check connectivity or API key"
    /usr/local/emhttp/webGui/scripts/notify \
      -e "arr-import-monitor" \
      -s "${app_name} queue API unreachable" \
      -d "arr-import-monitor could not reach ${app_name} at ${url}" \
      -i "warning"
    return
  fi

  local now
  now=$(date +%s)

  local stuck_items
  stuck_items=$(echo "$queue" | jq -r '
    .records[] |
    select(
      .trackedDownloadState == "importPending" or
      .trackedDownloadState == "importFailed"
    ) |
    [
      (.id | tostring),
      (.title // "Unknown title"),
      (.added // ""),
      (.trackedDownloadState // "unknown"),
      (
        .statusMessages // [] |
        map(.messages // [] | join("; ")) |
        select(length > 0) |
        first // ""
      ) // ""
    ] | @tsv
  ')

  if [ -z "$stuck_items" ]; then
    echo "[$app_name] No stuck imports"
    return
  fi

  while IFS=$'\t' read -r item_id title added state status_msg; do
    [ -z "$item_id" ] && continue

    local added_epoch
    added_epoch=$(date -d "$added" +%s 2>/dev/null)
    if [ -z "$added_epoch" ]; then
      echo "[$app_name] Could not parse date '$added' for: $title"
      continue
    fi

    local age_minutes=$(( (now - added_epoch) / 60 ))

    if [ "$age_minutes" -lt "$THRESHOLD_MINUTES" ]; then
      echo "[$app_name] Below threshold: $title (${age_minutes}m, state: $state)"
      continue
    fi

    local hours=$(( age_minutes / 60 ))
    local mins=$(( age_minutes % 60 ))
    local age_str
    if [ "$hours" -gt 0 ]; then
      age_str="${hours}h ${mins}m"
    else
      age_str="${mins}m"
    fi

    local msg="⚠️ **${app_name}**: \`${title}\` — not imported after ${age_str} (state: ${state})"
    if [ -n "$status_msg" ]; then
      msg="${msg}\n> ${status_msg}"
    fi

    if should_alert "$app_name" "$item_id"; then
      send_notification "$msg"
      echo "[$app_name] ALERTED: $title (${age_str}, state: $state)"
      [ -n "$status_msg" ] && echo "  Reason: $status_msg"
    else
      echo "[$app_name] Suppressed (re-alert pending): $title"
    fi

  done <<< "$stuck_items"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
clean_old_state

check_app_queue "Sonarr" "$SONARR_URL" "$SONARR_KEY" "v3"
check_app_queue "Radarr" "$RADARR_URL" "$RADARR_KEY" "v3"
check_app_queue "Lidarr" "$LIDARR_URL" "$LIDARR_KEY" "v1"
```

### 6.5 Design Notes

**API-driven detection** — uses `trackedDownloadState` from the *arr queue API rather than filesystem markers. This is authoritative: the app itself reports whether a download is stuck. The previous marker-file approach failed because `.imported` was set when the scan *command* was accepted, not when the import *completed*.

**State file is volatile** — `/tmp/arr-import-monitor.state` is cleared on reboot. This is intentional — after a reboot all stuck items will alert again on the next run, which is the correct behaviour.

**Status messages included in alerts** — the `statusMessages` field from the queue item is appended to the Discord notification, giving immediate diagnostic context (e.g. "No files found are eligible for import").

**Ghost queue entries** — a common source of `importPending` alerts is entries where the file was actually imported successfully (or imported via a replacement grab), but the original queue entry was never cleared. These appear as `importPending` with "No files found" because the folder on disk no longer matches the release name. Fix: remove the queue entry without blocklisting — see Section 8.8.

**Lidarr uses API v1** — Sonarr and Radarr use `/api/v3/queue`; Lidarr uses `/api/v1/queue`. The `check_app_queue` function accepts the API version as a parameter.

**Empty state file is normal** — when no items are stuck, the state file remains empty. Entries only appear after an alert fires.

---

## 7. Known Issues & Workarounds

### 7.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 7.2 Anime Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most via alias matching. The jq payload builder handles bracket characters in SubsPlease folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 7.3 Syncthing Race Condition

The rescan script retries every 5 minutes until the `.imported` marker is created, so files mid-sync will be caught on subsequent runs.

### 7.4 Syncthing Local Additions

After deleting imported files locally, Syncthing tracks these as "Locally Changed Items". Click Revert Local Changes to reset when needed.

### 7.5 Season Pack Imports

Require Interactive Import in Sonarr. Use Wanted > Manual Import > folder > Interactive Import.

### 7.6 Fake/Malicious Torrents

The rescan script detects .exe and other suspicious files, sends a Discord alert, and skips import. Blocklist the release in Sonarr/Radarr to trigger a search for a valid release.

### 7.7 Remote Path Mapping Host

qBittorrent remote path mapping host must be `ibiza.seedhost.eu`. Remote path must be `/home18/scytale1953/Media-sync` without trailing slash or app subfolder.

### 7.8 Foreign Language Series Title Mismatches

Sonarr stores the TVDB canonical title regardless of search term used when adding. If a series is only available under a foreign title (e.g. "La Oficina" vs "The Office (MX)"), submit the alias to TVDB. Once approved, refresh the series in Sonarr to pull in the alias.

### 7.9 Ghost Queue Entries (importPending with "No files found")

When Sonarr or Radarr grabs a replacement release for something that already imported, the original queue entry remains as `importPending` because the original folder is gone. The import monitor will alert on these. Diagnosis: check whether the episode/movie already has a file in the library, then clear the queue entry without blocklisting.

```bash
source /boot/config/arr-rescans.conf

# Check Sonarr library for a specific series
curl -s "http://192.168.1.12:8989/api/v3/series" \
  -H "X-Api-Key: $SONARR_KEY" | \
  jq '.[] | select(.title | test("SERIES NAME"; "i")) | {id, title}'

# Check if a specific episode has a file (use series ID from above)
curl -s "http://192.168.1.12:8989/api/v3/episode?seriesId=ID" \
  -H "X-Api-Key: $SONARR_KEY" | \
  jq '.[] | select(.episodeNumber == N and .seasonNumber == N) | {title, hasFile}'

# Check Radarr library
curl -s "http://192.168.1.12:7878/api/v3/movie" \
  -H "X-Api-Key: $RADARR_KEY" | \
  jq '.[] | select(.title | test("MOVIE NAME"; "i")) | {title, hasFile, monitored}'
```

If `hasFile` is true, the queue entry is a ghost — see Section 8.8 to clear it.

### 7.10 Resetting a Stuck Import

If a folder has an `.imported` marker but the file never actually imported:
```bash
rm "/mnt/user/media/download/sync/sonarr/FOLDERNAME/.imported"
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
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

### 8.4 Forcing a Manual Import Monitor Run

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-import-monitor/script
```

### 8.5 Resetting Import Monitor Alert State

To force re-alerting on all currently stuck items (e.g. after clearing false positives, or to test alerting):
```bash
rm /tmp/arr-import-monitor.state
```

The state file will be recreated and all stuck items will alert on the next run.

### 8.6 Checking Sync Folder Contents

```bash
ls /mnt/user/media/download/sync/sonarr/
ls /mnt/user/media/download/sync/radarr/
ls /mnt/user/media/download/sync/lidarr/
```

### 8.7 Checking Syncthing Sync Status

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

### 8.8 Clearing Stale Queue Entries (Ghost importPending)

Use bulk delete to clear all stuck entries at once. Does not remove files from the seedbox or blocklist the release.

```bash
source /boot/config/arr-rescans.conf

# Radarr — bulk delete all importPending / importFailed entries
RADARR_IDS=$(curl -s "http://192.168.1.12:7878/api/v3/queue?pageSize=200" \
  -H "X-Api-Key: $RADARR_KEY" | \
  jq '[.records[] | select(.trackedDownloadState == "importPending" or .trackedDownloadState == "importFailed") | .id]')

curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/bulk?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"ids\": $RADARR_IDS}"

# Sonarr — bulk delete all importPending / importFailed entries
SONARR_IDS=$(curl -s "http://192.168.1.12:8989/api/v3/queue?pageSize=200" \
  -H "X-Api-Key: $SONARR_KEY" | \
  jq '[.records[] | select(.trackedDownloadState == "importPending" or .trackedDownloadState == "importFailed") | .id]')

curl -s -X DELETE "http://192.168.1.12:8989/api/v3/queue/bulk?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $SONARR_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"ids\": $SONARR_IDS}"
```

To delete a single entry by ID:
```bash
curl -s -X DELETE \
  "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

### 8.9 Updating Discord Webhook or API Keys

```bash
nano /boot/config/arr-rescans.conf
```

---

## 9. Rebuild Checklist

### 9.1 Unraid Containers

- [ ] Deploy binhex-syncthing with host networking on port 8384
- [ ] Deploy Sonarr (linuxserver/sonarr) on port 8989
- [ ] Deploy Radarr (linuxserver/radarr) on port 7878
- [ ] Deploy Lidarr (linuxserver/lidarr) on port 8686
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
- [ ] Create `/boot/config/arr-rescans.conf` with API keys and Discord webhook
- [ ] `chmod 600 /boot/config/arr-rescans.conf`
- [ ] Create `arr-rescans` script per Section 5.3, set schedule `*/5 * * * *`
- [ ] Create `arr-import-monitor` script per Section 6.4, set schedule `*/15 * * * *`
- [ ] Test arr-rescans by running manually
- [ ] Test arr-import-monitor by running manually — confirm clean output or expected alerts
- [ ] Verify Discord alert received on a stuck import

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*  
*Note: Never commit arr-rescans.conf to git — it contains sensitive credentials*
