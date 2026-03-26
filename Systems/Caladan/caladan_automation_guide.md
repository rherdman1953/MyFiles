# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** March 2026
**Server:** Caladan (192.168.1.12) — Unraid
**Script Version:** v2

> ⚠️ **Never commit `arr-rescans.conf` to git — it contains sensitive credentials.**

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Rescan Script](#5-rescan-script-unraid-user-scripts)
6. [Known Issues & Workarounds](#6-known-issues--workarounds)
7. [Maintenance Procedures](#7-maintenance-procedures)
8. [Rebuild Checklist](#8-rebuild-checklist)

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
| Caladan OS | Unraid 7.2.4 |
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

> **CRITICAL:** Exceptions must come BEFORE the wildcard. Order matters — first match wins.

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

> **CRITICAL:** Remote path must be the base path without trailing slash or app subfolder. Host must be `ibiza.seedhost.eu`.

### 4.4 API Keys

Stored in `/boot/config/arr-rescans.conf` — see Section 5.1.

### 4.5 Quality Profile (HD-1080p)

- Upgrades Allowed: Yes
- Upgrade Until: Bluray-1080p
- Quality order: Remux-1080p, Bluray-1080p, WEB 1080p, HDTV-1080p

---

## 5. Rescan Script (Unraid User Scripts)

### 5.1 External Config File

Sensitive values are stored outside the script in `/boot/config/arr-rescans.conf`. This file persists across reboots and is never committed to git.

```bash
# /boot/config/arr-rescans.conf
SONARR_KEY="your_sonarr_api_key"
RADARR_KEY="your_radarr_api_key"
LIDARR_KEY="your_lidarr_api_key"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

To update the Discord webhook or API keys, edit only this file — never touch the script.

### 5.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
- **Schedule:** `*/5 * * * *` (every 5 minutes)

### 5.3 v1 → v2 Changes

v1 had a critical bug where `.imported` was set the moment the Sonarr/Radarr API *accepted* the scan command, not when the import actually succeeded. This caused silently failed imports (e.g. title mismatches, unrecognised series) to be permanently skipped with no alert ever firing.

| Concern | v1 Behaviour (Buggy) | v2 Behaviour (Fixed) |
|---------|----------------------|----------------------|
| `.imported` marker timing | Set when API accepted scan command | Set **only** after video files confirmed gone from sync path |
| Silent import failure | Permanently skipped — no alert ever fired | Files remain present → `.first_seen` age check triggers Discord alert |
| Alert suppression | Alert loop checked `.imported` and skipped stuck folders | Alert loop is independent; `.imported` only set on confirmed success |
| `confirm_import()` | Not present | New function: returns 0 when no video files remain in path |
| Script steps | 6 steps | 8 steps — adds Step 7 (file-gone confirmation) before final refresh |

### 5.4 Script Execution Flow

| Step | Action |
|------|--------|
| 1 | Clean up orphaned `.imported` and `.first_seen` marker files |
| 2 | Suspicious file detection — alert and skip folders with `.exe`/`.bat`/`.com`/`.scr`/`.js`/`.vbs` |
| 3 | Stuck-import alerts — Discord alert if `.first_seen` age exceeds 120 minutes |
| 4 | `RefreshMonitoredDownloads` (first pass) — sync queue with qBittorrent state |
| 5 | Submit `DownloadedEpisodesScan` / `DownloadedMoviesScan` per folder and loose `.mkv` — **`.imported` NOT set here** |
| 6 | `sleep 180` — allow Sonarr/Radarr time to process |
| 7 | Confirm imports: set `.imported` **only** when video files are gone from sync path |
| 8 | `RefreshMonitoredDownloads` (second pass) — clear completed queue entries |

### 5.5 Script Contents

```bash
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
    # Loose file — check whether the file itself is gone
    [ ! -f "$path" ] && return 0
    return 1
  elif [ -d "$path" ]; then
    local remaining
    remaining=$(find "$path" -type f \( \
      -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \
      -o -iname "*.m4v" -o -iname "*.mov" \) | wc -l)
    [ "$remaining" -eq 0 ] && return 0
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
    "$RADARR_SYNC"/*.mkv.imported \
    "$RADARR_SYNC"/*.mkv.first_seen; do
  [ -f "$marker" ] || continue
  base="${marker%.imported}"
  base="${base%.first_seen}"
  [ -f "$base" ] || rm -f "$marker"
done

for marker in \
    "$SONARR_SYNC"/*/".imported" \
    "$SONARR_SYNC"/*/".first_seen" \
    "$RADARR_SYNC"/*/".imported" \
    "$RADARR_SYNC"/*/".first_seen"; do
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
    send_notification "⚠️ **${app}**: \`${label}\` has not imported after ${age} minutes"
    echo "Alert: $label (${age} minutes)"
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
```

### 5.6 Design Notes

**`send_notification`** — sends to Discord and falls back to Unraid native notification if Discord returns a non-204 response.

**`confirm_import()`** — new in v2. Accepts a file or directory path and returns 0 (success) when no video files (`.mkv` `.mp4` `.avi` `.m4v` `.mov`) remain. This is the sole gate for setting `.imported`.

**`.imported` marker** — sole guard against re-scanning. Set **only** in Step 7 after `confirm_import()` returns 0. Never set when a scan command is merely accepted by the API.

**`.first_seen` marker** — reliable 2-hour import delay detection using marker file timestamps. Directory mtimes are unreliable on Unraid's filesystem. Alert fires only when item lacks `.imported`, so confirmed successes never alert.

**`jq --arg` payload builder** — safely handles special characters in folder names including brackets, spaces, and apostrophes common in anime and foreign language releases.

**Suspicious file detection** — alerts Discord and sets `.imported` (to suppress further scanning) for folders containing `.exe`, `.bat`, `.com`, `.scr`, `.js`, or `.vbs` files.

**Stale Radarr queue entries** — when imports happen via `DownloadedMoviesScan` rather than through the normal queue flow, Radarr may retain stale "completed" queue entries. Clear manually via Radarr → Activity → Queue or via API:

```bash
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

---

## 6. Known Issues & Workarounds

### 6.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only — no action required.

### 6.2 Anime Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most via alias matching. The `jq` payload builder handles bracket characters in SubsPlease folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 6.3 Syncthing Race Condition

The rescan script retries every 5 minutes until the `.imported` marker is created, so files mid-sync will be caught on subsequent runs.

### 6.4 Syncthing Local Additions

After deleting imported files locally, Syncthing tracks these as "Locally Changed Items". Click **Revert Local Changes** to reset when needed.

### 6.5 Season Pack Imports

Require Interactive Import in Sonarr. Use **Wanted > Manual Import > folder > Interactive Import**.

### 6.6 Fake / Malicious Torrents

The rescan script detects `.exe` and other suspicious files, sends a Discord alert, and skips import. Blocklist the release in Sonarr/Radarr to trigger a search for a valid release.

### 6.7 Remote Path Mapping Host

qBittorrent remote path mapping host must be `ibiza.seedhost.eu`. Remote path must be `/home18/scytale1953/Media-sync` without trailing slash or app subfolder.

### 6.8 Foreign Language Series Title Mismatches

Sonarr stores the TVDB canonical title regardless of search term used when adding. If a series is only available under a foreign title (e.g. "La Oficina" vs "The Office (MX)"), submit the alias to TVDB. Once approved, refresh the series in Sonarr to pull in the alias.

### 6.9 Resetting a Stuck Import

If a folder has an `.imported` marker but the file never actually imported:

```bash
rm "/mnt/user/media/download/sync/sonarr/FOLDERNAME/.imported"
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

> With v2, this scenario is far less likely because `.imported` is only set after confirming files are gone.

---

## 7. Maintenance Procedures

### 7.1 Manual Sync Folder Cleanup

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

### 7.2 Checking Import Logs

```bash
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30
docker logs sonarr --since 1h 2>&1 | grep Error | tail -20
```

### 7.3 Forcing a Manual Rescan

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

### 7.4 Checking Sync Folder Contents

```bash
ls /mnt/user/media/download/sync/sonarr/
ls /mnt/user/media/download/sync/radarr/
ls /mnt/user/media/download/sync/lidarr/
```

### 7.5 Checking Syncthing Sync Status

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

### 7.6 Updating Discord Webhook or API Keys

```bash
nano /boot/config/arr-rescans.conf
```

### 7.7 Clearing Stale Radarr Queue Entries

```bash
# Get queue IDs
curl -s "http://192.168.1.12:7878/api/v3/queue?apikey=YOUR_RADARR_KEY" | jq '.records[] | {id, title, status}'

# Delete a specific entry
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: YOUR_RADARR_KEY"
```

---

## 8. Rebuild Checklist

### 8.1 Unraid Containers

- [ ] Deploy binhex-syncthing with host networking on port 8384
- [ ] Deploy Sonarr (linuxserver/sonarr) on port 8989
- [ ] Deploy Radarr (linuxserver/radarr) on port 7878
- [ ] Deploy Lidarr (linuxserver/lidarr) on port 8686
- [ ] Configure all volume mounts per Section 4.1
- [ ] **Manually add /downloads mapping to Lidarr**

### 8.2 Syncthing

- [ ] Add Media sync folder with ID `sfqzb-cvm5v`
- [ ] Set folder type to **Receive Only**
- [ ] Set folder path to `/media/sync` (container path)
- [ ] Add seedbox as remote device
- [ ] Create `/mnt/user/media/download/sync/.stignore` per Section 3.3
- [ ] **Verify ignore pattern order: exceptions FIRST, wildcard LAST**

### 8.3 *arr Apps

- [ ] Add qBittorrent download client per Section 4.2
- [ ] Add remote path mappings per Section 4.3
- [ ] Configure quality profiles
- [ ] Verify /downloads container mount present in all three apps
- [ ] Connect Discord notifications in Sonarr/Radarr

### 8.4 Seedbox

- [ ] Verify qBittorrent save path is `/home18/scytale1953/Media-sync/`
- [ ] Verify qBittorrent seeding limits (20160 min, remove torrent and files)
- [ ] Verify Syncthing cron is present
- [ ] Verify Syncthing connected to Caladan device ID

### 8.5 User Scripts

- [ ] Install User Scripts plugin in Unraid
- [ ] Create `/boot/config/arr-rescans.conf` with API keys and Discord webhook
- [ ] `chmod 600 /boot/config/arr-rescans.conf`
- [ ] Create `arr-rescans` script per Section 5.5 (v2 — file-confirmation logic)
- [ ] Set schedule to `*/5 * * * *`
- [ ] Test by running manually
- [ ] Verify Discord alert received

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*
*Note: Never commit arr-rescans.conf to git — it contains sensitive credentials*
