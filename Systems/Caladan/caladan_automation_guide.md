# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** April 2026  
**Server:** Caladan (192.168.1.12) — Unraid  

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Rescan Script](#5-rescan-script-unraid-user-scripts)
6. [Cleanup Script](#6-cleanup-script-unraid-user-scripts)
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

**CRITICAL:** Exceptions must come BEFORE the wildcard. Order matters — first match wins. Exclusions (like sample files) must also appear before the allow-all rules for each subdirectory.

File location: `/mnt/user/media/download/sync/.stignore`

```
!/sonarr
!/radarr
!/lidarr
!/sonarr/**
!/radarr/**
!/lidarr/**
**/[Ss]ample/
**/[Ss]ample/**
*[Ss]ample*.mkv
*.imported
*.first_seen
*
```

**Pattern notes:**
- `*.imported` and `*.first_seen` — excludes marker files created by arr-rescans so they never appear as Locally Changed Items in Syncthing
- `**/[Ss]ample/**` and `*[Ss]ample*.mkv` — excludes sample video files from syncing (saves bandwidth)
- Sample exclusions must appear before the `!/sonarr/**` allow rules or they will never match (first-match-wins)

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

When Syncthing shows "Locally Changed Items" and is not syncing new content, use the **Revert Local Changes** button in the Syncthing UI. Safe because Caladan is Receive Only and qBittorrent manages file lifecycle.

> **Note:** The Revert Local Changes button only appears when the folder is idle. If the folder is actively syncing, the button will not be visible. Use the API instead:

```bash
curl -X POST "http://localhost:8384/rest/db/revert?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

This is the exact equivalent of the UI button and works regardless of folder state.

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

## 5. Rescan Script (Unraid User Scripts)

### 5.1 External Config File

Sensitive values are stored outside the script in `/boot/config/arr-rescans.conf`. This file persists across reboots and is never committed to git.

```bash
# /boot/config/arr-rescans.conf
SONARR_KEY="your_sonarr_api_key"
RADARR_KEY="your_radarr_api_key"
LIDARR_KEY="your_lidarr_api_key"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
SYNC_RETENTION_DAYS=14
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

To update the Discord webhook or API keys, edit only this file — never touch the script.

### 5.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
- **Schedule:** `*/5 * * * *` (every 5 minutes)

### 5.3 Script Contents

```bash
#!/bin/bash

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

# Clean up orphaned marker files for loose .mkv files
for marker in /mnt/user/media/download/sync/sonarr/*.mkv.imported \
              /mnt/user/media/download/sync/sonarr/*.mkv.first_seen \
              /mnt/user/media/download/sync/radarr/*.mkv.imported \
              /mnt/user/media/download/sync/radarr/*.mkv.first_seen; do
  [ -f "$marker" ] || continue
  base="${marker%.imported}"
  base="${base%.first_seen}"
  [ -f "$base" ] || rm -f "$marker"
done

# Check for suspicious files - sonarr subfolders
for item in /mnt/user/media/download/sync/sonarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  SUSPICIOUS=$(find "$item" -type f \( -iname "*.exe" -o -iname "*.bat" -o -iname "*.com" -o -iname "*.scr" -o -iname "*.js" -o -iname "*.vbs" \) | wc -l)
  if [ "$SUSPICIOUS" -gt 0 ]; then
    folder=$(basename "$item")
    send_notification "🚨 **Suspicious files in Sonarr download**: \`$folder\` contains $SUSPICIOUS potentially malicious file(s). Import skipped — manual review required."
    touch "${item}.imported"
    echo "SUSPICIOUS: $folder"
  fi
done

# Check for suspicious files - radarr subfolders
for item in /mnt/user/media/download/sync/radarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  SUSPICIOUS=$(find "$item" -type f \( -iname "*.exe" -o -iname "*.bat" -o -iname "*.com" -o -iname "*.scr" -o -iname "*.js" -o -iname "*.vbs" \) | wc -l)
  if [ "$SUSPICIOUS" -gt 0 ]; then
    folder=$(basename "$item")
    send_notification "🚨 **Suspicious files in Radarr download**: \`$folder\` contains $SUSPICIOUS potentially malicious file(s). Import skipped — manual review required."
    touch "${item}.imported"
    echo "SUSPICIOUS: $folder"
  fi
done

# Alert on sonarr subfolders stuck unimported for 2+ hours
for item in /mnt/user/media/download/sync/sonarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  if [ ! -f "${item}.first_seen" ]; then
    touch "${item}.first_seen"
    continue
  fi
  marker_time=$(stat -c %Y "${item}.first_seen")
  now=$(date +%s)
  age=$(( (now - marker_time) / 60 ))
  if [ "$age" -gt 120 ]; then
    folder=$(basename "$item")
    send_notification "⚠️ **Sonarr**: \`$folder\` has not imported after ${age} minutes"
    echo "Alert: $folder (${age} minutes)"
  fi
done

# Alert on radarr subfolders stuck unimported for 2+ hours
for item in /mnt/user/media/download/sync/radarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  if [ ! -f "${item}.first_seen" ]; then
    touch "${item}.first_seen"
    continue
  fi
  marker_time=$(stat -c %Y "${item}.first_seen")
  now=$(date +%s)
  age=$(( (now - marker_time) / 60 ))
  if [ "$age" -gt 120 ]; then
    folder=$(basename "$item")
    send_notification "⚠️ **Radarr**: \`$folder\` has not imported after ${age} minutes"
    echo "Alert: $folder (${age} minutes)"
  fi
done

# Alert on sonarr loose .mkv files stuck unimported for 2+ hours
for mkv in /mnt/user/media/download/sync/sonarr/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  if [ ! -f "${mkv}.first_seen" ]; then
    touch "${mkv}.first_seen"
    continue
  fi
  marker_time=$(stat -c %Y "${mkv}.first_seen")
  now=$(date +%s)
  age=$(( (now - marker_time) / 60 ))
  if [ "$age" -gt 120 ]; then
    filename=$(basename "$mkv")
    send_notification "⚠️ **Sonarr**: \`$filename\` has not imported after ${age} minutes"
    echo "Alert: $filename (${age} minutes)"
  fi
done

# Alert on radarr loose .mkv files stuck unimported for 2+ hours
for mkv in /mnt/user/media/download/sync/radarr/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  if [ ! -f "${mkv}.first_seen" ]; then
    touch "${mkv}.first_seen"
    continue
  fi
  marker_time=$(stat -c %Y "${mkv}.first_seen")
  now=$(date +%s)
  age=$(( (now - marker_time) / 60 ))
  if [ "$age" -gt 120 ]; then
    filename=$(basename "$mkv")
    send_notification "⚠️ **Radarr**: \`$filename\` has not imported after ${age} minutes"
    echo "Alert: $filename (${age} minutes)"
  fi
done

# Refresh tracked queue items
curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$SONARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$RADARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $LIDARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$LIDARR/api/v3/command" > /dev/null

# Scan sonarr subfolders - skip only if already marked as imported
for item in /mnt/user/media/download/sync/sonarr/*/; do
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

# Scan radarr subfolders - skip only if already marked as imported
for item in /mnt/user/media/download/sync/radarr/*/; do
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

# Scan loose sonarr .mkv files - skip only if already marked as imported
for mkv in /mnt/user/media/download/sync/sonarr/*.mkv; do
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

# Scan loose radarr .mkv files - skip only if already marked as imported
for mkv in /mnt/user/media/download/sync/radarr/*.mkv; do
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

sleep 180

# Second pass - RefreshMonitoredDownloads only
curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$SONARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$RADARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $LIDARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$LIDARR/api/v3/command" > /dev/null
```

### 5.4 Script Design Notes

**External config file** — API keys and Discord webhook stored in `/boot/config/arr-rescans.conf`, separate from the script. Update credentials by editing only the conf file. Never commit the conf file to git.

**send_notification function** — sends to Discord and falls back to Unraid native notification if Discord returns a non-204 response.

**DownloadedEpisodesScan per folder** — core import mechanism. Scans each subfolder individually. Also handles loose .mkv files directly.

**`.imported` marker file** — sole guard against re-scanning. The `-mmin -60` timestamp check was removed as it caused loose .mkv files older than 60 minutes to never be scanned.

**`.first_seen` marker file** — reliable 2-hour import delay detection using marker file timestamps (directory mtimes are unreliable on Unraid's filesystem).

**jq `--arg` payload builder** — safely handles special characters in folder names including brackets, spaces, and apostrophes common in anime and foreign language releases.

**Suspicious file detection** — alerts Discord and skips import for folders containing .exe, .bat, .com, .scr, .js, or .vbs files.

**Alert coverage** — fires for both subfolders AND loose .mkv files after 2+ hours unimported. Earlier versions only alerted on subfolders.

**Stale Radarr queue entries** — when imports happen via DownloadedMoviesScan rather than through the normal queue flow, Radarr may retain stale "completed" queue entries. Clear manually via Radarr → Activity → Queue or via API:
```bash
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

---

## 6. Cleanup Script (Unraid User Scripts)

### 6.1 Purpose

The arr-cleanup script removes imported files from the sync folders once they exceed the configured retention period. This mirrors qBittorrent's 14-day seeding limit on the seedbox — once the seedbox deletes a file, it should eventually be cleaned from the Caladan sync folder too. Only folders/files with an `.imported` marker are eligible for deletion, so nothing unimported is ever touched.

### 6.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-cleanup/script`
- **Schedule:** `0 4 * * *` (4am daily)

### 6.3 Configuration

Retention period is controlled by `SYNC_RETENTION_DAYS` in `/boot/config/arr-rescans.conf`. The script defaults to 14 days if the value is not set. Age is measured from the `.imported` marker file timestamp — not the file's own mtime, which reflects the seedbox download time rather than when the file arrived and was imported.

### 6.4 Script Contents

```bash
#!/bin/bash

# Load external config
if [ ! -f /boot/config/arr-rescans.conf ]; then
  /usr/local/emhttp/webGui/scripts/notify \
    -e "arr-cleanup" \
    -s "arr-cleanup config missing" \
    -d "Config file /boot/config/arr-rescans.conf not found." \
    -i "alert"
  exit 1
fi
source /boot/config/arr-rescans.conf

# Default to 14 days if not set
SYNC_RETENTION_DAYS="${SYNC_RETENTION_DAYS:-14}"

SYNC_BASE="/mnt/user/media/download/sync"
DELETED=0
ERRORS=0

send_notification() {
  local message="$1"
  local MSG=$(jq -n --arg msg "$message" '{content: $msg}')
  local HTTP_CODE=$(curl -s -o /tmp/discord_response.json -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "$MSG" "$DISCORD_WEBHOOK")
  if [ "$HTTP_CODE" != "204" ]; then
    local ERROR=$(cat /tmp/discord_response.json 2>/dev/null)
    /usr/local/emhttp/webGui/scripts/notify \
      -e "arr-cleanup" \
      -s "Discord webhook error" \
      -d "HTTP $HTTP_CODE: $ERROR — Message: $message" \
      -i "warning"
  fi
}

cleanup_dir() {
  local dir="$1"
  local label="$2"

  # Remove subfolders older than retention days that have .imported marker
  for item in "$dir"/*/; do
    [ -d "$item" ] || continue
    [ -f "${item}.imported" ] || continue

    # Check age of the .imported marker
    marker_time=$(stat -c %Y "${item}.imported" 2>/dev/null) || continue
    now=$(date +%s)
    age_days=$(( (now - marker_time) / 86400 ))

    if [ "$age_days" -ge "$SYNC_RETENTION_DAYS" ]; then
      folder=$(basename "$item")
      if rm -rf "$item"; then
        echo "Deleted: $label/$folder (${age_days} days old)"
        DELETED=$((DELETED + 1))
      else
        echo "ERROR deleting: $label/$folder"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  done

  # Remove loose .mkv files older than retention days that have .imported marker
  for mkv in "$dir"/*.mkv; do
    [ -f "$mkv" ] || continue
    [ -f "${mkv}.imported" ] || continue

    marker_time=$(stat -c %Y "${mkv}.imported" 2>/dev/null) || continue
    now=$(date +%s)
    age_days=$(( (now - marker_time) / 86400 ))

    if [ "$age_days" -ge "$SYNC_RETENTION_DAYS" ]; then
      filename=$(basename "$mkv")
      if rm -f "$mkv" "${mkv}.imported" "${mkv}.first_seen" 2>/dev/null; then
        echo "Deleted: $label/$filename (${age_days} days old)"
        DELETED=$((DELETED + 1))
      else
        echo "ERROR deleting: $label/$filename"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  done
}

cleanup_dir "$SYNC_BASE/sonarr" "sonarr"
cleanup_dir "$SYNC_BASE/radarr" "radarr"
cleanup_dir "$SYNC_BASE/lidarr" "lidarr"

# Send summary notification if anything happened
if [ "$DELETED" -gt 0 ] || [ "$ERRORS" -gt 0 ]; then
  msg="🧹 **Sync cleanup**: Removed $DELETED item(s) older than ${SYNC_RETENTION_DAYS} days"
  [ "$ERRORS" -gt 0 ] && msg="$msg — ⚠️ $ERRORS deletion error(s), check logs"
  send_notification "$msg"
  echo "Summary: $DELETED deleted, $ERRORS errors"
else
  echo "Nothing to clean up (threshold: ${SYNC_RETENTION_DAYS} days)"
fi
```

### 6.5 Script Design Notes

**`.imported` marker age** — age is measured from the `.imported` marker timestamp, not the video file's mtime. The video file mtime reflects when it was created on the seedbox, not when it arrived and was imported on Caladan, making it unreliable for retention calculations.

**Safety guard** — only items with an `.imported` marker are touched. Anything still awaiting import is never deleted.

**Loose .mkv cleanup** — removes the `.mkv`, `.mkv.imported`, and `.mkv.first_seen` files together as a unit.

**Discord summary** — only sends a notification if something was actually deleted or errored. Silent runs produce no alert.

**Dry run** — to check what would be deleted without removing anything:
```bash
source /boot/config/arr-rescans.conf
SYNC_RETENTION_DAYS="${SYNC_RETENTION_DAYS:-14}"
SYNC_BASE="/mnt/user/media/download/sync"

for dir in sonarr radarr lidarr; do
  for item in "$SYNC_BASE/$dir"/*/; do
    [ -d "$item" ] || continue
    [ -f "${item}.imported" ] || continue
    marker_time=$(stat -c %Y "${item}.imported" 2>/dev/null) || continue
    age_days=$(( ($(date +%s) - marker_time) / 86400 ))
    echo "$dir/$(basename $item) — ${age_days} days old"
  done
done
```

---

## 7. Known Issues & Workarounds

### 7.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 7.2 Anime Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most via alias matching. The jq payload builder handles bracket characters in SubsPlease folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 7.3 Syncthing Race Condition

The rescan script retries every 5 minutes until the `.imported` marker is created, so files mid-sync will be caught on subsequent runs.

### 7.4 Syncthing Locally Changed Items

After deleting imported files locally, Syncthing tracks these as "Locally Changed Items". Click Revert Local Changes in the UI, or use the API if the folder is actively syncing (see Section 3.5).

### 7.5 Season Pack Imports

Require Interactive Import in Sonarr. Use Wanted > Manual Import > folder > Interactive Import.

### 7.6 Fake/Malicious Torrents

The rescan script detects .exe and other suspicious files, sends a Discord alert, and skips import. Blocklist the release in Sonarr/Radarr to trigger a search for a valid release.

### 7.7 Remote Path Mapping Host

qBittorrent remote path mapping host must be `ibiza.seedhost.eu`. Remote path must be `/home18/scytale1953/Media-sync` without trailing slash or app subfolder.

### 7.8 Foreign Language Series Title Mismatches

Sonarr stores the TVDB canonical title regardless of search term used when adding. If a series is only available under a foreign title (e.g. "La Oficina" vs "The Office (MX)"), submit the alias to TVDB. Once approved, refresh the series in Sonarr to pull in the alias.

### 7.9 Resetting a Stuck Import

If a folder has an `.imported` marker but the file never actually imported:
```bash
rm "/mnt/user/media/download/sync/sonarr/FOLDERNAME/.imported"
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

### 7.10 Syncthing Stuck Syncing / Revert Button Missing

The Revert Local Changes button only appears when the folder is idle. If Syncthing is stuck mid-sync (often caused by a large file download), use the API revert from Section 3.5. The folder will process the revert once the active download completes and the folder reaches idle. Check what is currently downloading:

```bash
curl -s "http://localhost:8384/rest/db/need?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY" | jq '{progress: .progress[:5] | .[] | {name, size}}'
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

### 8.7 Clearing Stale Radarr Queue Entries

```bash
# Get queue IDs
curl -s "http://192.168.1.12:7878/api/v3/queue?apikey=YOUR_RADARR_KEY" | jq '.records[] | {id, title, status}'

# Delete a specific entry
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: YOUR_RADARR_KEY"
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
- [ ] **Verify ignore pattern order: sample/marker exclusions BEFORE allow rules, wildcard LAST**

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
- [ ] Create `/boot/config/arr-rescans.conf` with API keys, Discord webhook, and `SYNC_RETENTION_DAYS=14`
- [ ] `chmod 600 /boot/config/arr-rescans.conf`
- [ ] Create `arr-rescans` script per Section 5.3 — schedule `*/5 * * * *`
- [ ] Create `arr-cleanup` script per Section 6.4 — schedule `0 4 * * *`
- [ ] Test both scripts by running manually
- [ ] Verify Discord alert received from arr-rescans

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*
*Note: Never commit arr-rescans.conf to git — it contains sensitive credentials*
