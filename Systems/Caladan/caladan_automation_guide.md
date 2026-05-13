# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** May 2026  
**Server:** Caladan (192.168.1.12) — Unraid  

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Rescan Script (arr-rescans)](#5-rescan-script-arr-rescans)
6. [Import Monitor (arr-import-monitor)](#6-import-monitor-arr-import-monitor)
7. [Sync Folder Cleanup (sync-cleanup)](#7-sync-folder-cleanup-sync-cleanup)
8. [Known Issues & Workarounds](#8-known-issues--workarounds)
9. [Maintenance Procedures](#9-maintenance-procedures)
10. [Rebuild Checklist](#10-rebuild-checklist)

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

> qBittorrent automatically cleans up Media-sync files after 14 days seeding. No manual cleanup or cron job is needed on the seedbox side. sync-cleanup (Section 7) handles Caladan-side cleanup.

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
| Rescan Interval | 0 (disabled — prevents re-flagging of locally present files) |

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
*.nfo
*.srr
*.jpg
*.jpeg
**/Screens/
**/screens/
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

When Syncthing shows "Locally Changed Items" (files present on Caladan but gone from the seedbox), use the **Revert Local Changes** button in the Syncthing UI, or trigger via API:

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -X POST "http://localhost:8384/rest/db/revert?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

Safe because Caladan is Receive Only. sync-cleanup (Section 7) triggers this automatically after each live run.

### 3.6 Deadlock Recovery

If Syncthing is permanently stuck and "Revert Local Changes" never appears:

1. Stop the binhex-syncthing container
2. Delete the index database: `rm -rf /mnt/user/appdata/binhex-syncthing/syncthing/index-v0.14.0.db`
3. Start the container — Syncthing will re-index from scratch

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

## 5. Rescan Script (arr-rescans)

**Current version: v4.2**

### 5.1 External Config File

Sensitive values and tuneable parameters are stored outside the script in `/boot/config/arr-rescans.conf`. This file persists across reboots and is never committed to git.

```bash
# /boot/config/arr-rescans.conf
SONARR_KEY="your_sonarr_api_key"
RADARR_KEY="your_radarr_api_key"
LIDARR_KEY="your_lidarr_api_key"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"

# Optional overrides for arr-import-monitor (leave commented to use defaults)
# IMPORT_ALERT_THRESHOLD=30       # minutes before alerting on stuck import
# IMPORT_REALERT_SECONDS=3600     # seconds before re-alerting on same item
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

To update the Discord webhook or API keys, edit only this file — never touch the script.

### 5.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
- **Schedule:** `*/5 * * * *` (every 5 minutes)

### 5.3 Script Design Notes (v4.2)

**History API for import detection** — at startup the script fetches `downloadFolderImported` history (eventType=3, pageSize=1000) from Sonarr and Radarr into memory. Per-folder/file checks use herestring grep (`grep -qF "$name" <<< "$history"`) to skip already-imported items. This replaces the marker-file approach entirely.

**Why herestring, not echo pipe** — `grep -qF "$name" <<< "$history"` is required to avoid broken pipe errors when grep exits early against large history strings.

**Marker files completely removed** — `.imported` and `.first_seen` files caused Syncthing to track them as locally changed items, leading to deadlocks. History API polling is the robust replacement.

**Alerting delegated to arr-import-monitor** — arr-rescans only triggers scans. Stuck-import detection and Discord alerts are handled entirely by arr-import-monitor (Section 6). Clean separation of concerns.

**DownloadedEpisodesScan / DownloadedMoviesScan per folder** — core import mechanism. Scans each subfolder individually and handles loose .mkv files directly.

**jq `--arg` payload builder** — safely handles special characters in folder names including brackets, spaces, and apostrophes common in anime and foreign language releases.

**Suspicious file detection** — alerts Discord and skips import for folders containing .exe, .bat, .com, .scr, .js, or .vbs files.

**Lidarr uses `/api/v1/`** — all Lidarr API calls use `/api/v1/` not `/api/v3/`. Sonarr and Radarr use `/api/v3/`.

**`--max-time 10` on all curls** — prevents script from hanging if an *arr app is unresponsive.

**Hardlink detection does not work here** — Sonarr/Radarr copy rather than hardlink imported files on this setup because source (sync folder) and destination (media library) land on different physical disks under unionfs. `nlink > 1` is not a reliable import guard.

---

## 6. Import Monitor (arr-import-monitor)

**Current version: v2.0**

### 6.1 Purpose

Monitors Sonarr, Radarr, and Lidarr queues for stuck imports and alerts via Discord. Runs separately from arr-rescans on a slower schedule so the two scripts have clean separation of concerns.

### 6.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-import-monitor/script`
- **Schedule:** `*/10 * * * *` (every 10 minutes)

### 6.3 State File

- **Path:** `/tmp/arr-import-monitor.state`
- Volatile — cleared on reboot. An empty or missing state file on startup is normal.
- Uses prefixed keys to avoid collisions: `fs:sonarr:`, `fs:radarr:`, `queue:sonarr:`, `queue:radarr:`, `queue:lidarr:`

### 6.4 Design Notes (v2.0)

**Unified state file** — all alert deduplication (filesystem and queue) uses a single `/tmp/arr-import-monitor.state` file with prefixed keys.

**First-seen tracking via state** — `_first` keys track when the monitor first noticed a stuck item, so alert age is calculated from first observation rather than from unreliable API time fields.

**`_keys_ref` nameref pattern** — `prune_state` uses `local -n _keys_ref=$1` (not `active_keys`) to avoid a circular nameref error when called from inside `check_queue` where `active_keys` is already a local variable.

**`api_ver` parameter in `check_queue`** — the function accepts an optional 4th argument for API version, defaulting to `v3`. Lidarr is called as `check_queue "Lidarr" "$LIDARR" "$LIDARR_KEY" "v1"`.

**Queue alert coverage** — alerts on `trackedDownloadStatus` of `warning` or `error` for completed downloads that haven't imported.

**Automatic state pruning** — resolved queue entries are removed from the state file so it doesn't grow unboundedly.

**Configurable thresholds** — `IMPORT_ALERT_THRESHOLD` (minutes before alerting, default 30) and `IMPORT_REALERT_SECONDS` (cooldown between repeat alerts, default 3600) can be overridden in `arr-rescans.conf`.

---

## 7. Sync Folder Cleanup (sync-cleanup)

**Current version: v1.2**

### 7.1 Purpose

Removes successfully imported files from Caladan's sync folders (`/mnt/user/media/download/sync/`). Without this, imported content accumulates indefinitely after the seedbox deletes its copy at the 14-day seeding limit, causing Syncthing's "Locally Changed Items" count to grow over time and degrade sync performance.

### 7.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/sync-cleanup/script`
- **Schedule:** `0 3 * * *` (daily at 3am) — or run on demand

### 7.3 Usage

```bash
# Dry-run (default) — lists what would be deleted, no changes made, no Discord message
bash /boot/config/plugins/user.scripts/scripts/sync-cleanup/script

# Live run — deletes confirmed-imported items and triggers Syncthing revert
bash /boot/config/plugins/user.scripts/scripts/sync-cleanup/script --live
```

### 7.4 Script Contents

```bash
#!/bin/bash
# sync-cleanup v1.2
# Removes successfully imported files from Caladan sync folders.
# Uses Sonarr/Radarr/Lidarr history API (eventType=3, downloadFolderImported) to
# determine what is safe to delete — same approach as arr-rescans v4.2.
# After deletion, triggers Syncthing revert to clear locally-changed-items pile.
#
# Usage:
#   bash sync-cleanup          # dry-run (lists what would be deleted, no changes)
#   bash sync-cleanup --live   # actually deletes files and triggers Syncthing revert

LIVE=false
[[ "$1" == "--live" ]] && LIVE=true

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

CONF=/boot/config/arr-rescans.conf
if [ ! -f "$CONF" ]; then
  echo "ERROR: Config file $CONF not found." >&2
  exit 1
fi
source "$CONF"

SONARR="http://192.168.1.12:8989"
RADARR="http://192.168.1.12:7878"
LIDARR="http://192.168.1.12:8686"

SYNC_SONARR="/mnt/user/media/download/sync/sonarr"
SYNC_RADARR="/mnt/user/media/download/sync/radarr"
SYNC_LIDARR="/mnt/user/media/download/sync/lidarr"

SYNCTHING_CONFIG="/mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml"
SYNCTHING_FOLDER_ID="sfqzb-cvm5v"

# Minimum age in minutes before a file/folder is eligible for deletion.
# Prevents race-condition deletion of actively syncing content.
MIN_AGE_MINUTES=1440  # 24 hours — increase if needed

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() { echo "[$(date '+%H:%M:%S')] $*"; }

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
      -e "sync-cleanup" \
      -s "Discord webhook error" \
      -d "HTTP $HTTP_CODE: $ERROR — Message: $message" \
      -i "warning"
  fi
}

# Returns 0 (true) if the given name appears in the provided history string.
# Uses herestring to avoid broken-pipe on large history payloads.
in_history() {
  local name="$1"
  local history="$2"
  grep -qF "$name" <<< "$history"
}

# Returns age of path in minutes (file or directory mtime).
age_minutes() {
  local path="$1"
  local mtime now
  mtime=$(stat -c %Y "$path" 2>/dev/null) || { echo 9999; return; }
  now=$(date +%s)
  echo $(( (now - mtime) / 60 ))
}

# Returns the mtime of a path formatted as YYYY-MM-DD.
item_date() {
  stat -c %y "$1" 2>/dev/null | cut -d' ' -f1
}

# ---------------------------------------------------------------------------
# Fetch import history from all three apps at startup
# ---------------------------------------------------------------------------

log "Fetching import history from Sonarr..."
SONARR_HISTORY=$(curl -s --max-time 15 \
  "$SONARR/api/v3/history?pageSize=1000&eventType=3" \
  -H "X-Api-Key: $SONARR_KEY") || { log "ERROR: Could not reach Sonarr"; exit 1; }

log "Fetching import history from Radarr..."
RADARR_HISTORY=$(curl -s --max-time 15 \
  "$RADARR/api/v3/history?pageSize=1000&eventType=3" \
  -H "X-Api-Key: $RADARR_KEY") || { log "ERROR: Could not reach Radarr"; exit 1; }

log "Fetching import history from Lidarr..."
LIDARR_HISTORY=$(curl -s --max-time 15 \
  "$LIDARR/api/v1/history?pageSize=1000&eventType=3" \
  -H "X-Api-Key: $LIDARR_KEY") || { log "ERROR: Could not reach Lidarr"; exit 1; }

# Validate — if any response is empty or not JSON, abort
for label in SONARR RADARR LIDARR; do
  hist_var="${label}_HISTORY"
  if ! echo "${!hist_var}" | jq -e '.records' > /dev/null 2>&1; then
    log "ERROR: $label history response invalid or empty. Aborting."
    exit 1
  fi
done

log "History fetched. Running in $( $LIVE && echo 'LIVE' || echo 'DRY-RUN' ) mode."
echo ""

# ---------------------------------------------------------------------------
# Main cleanup loop
# ---------------------------------------------------------------------------

DELETED=()
SKIPPED_AGE=()
SKIPPED_NOT_IN_HISTORY=()

process_item() {
  local path="$1"
  local name="$2"
  local history="$3"
  local type="$4"  # "dir" or "file"

  # Age guard
  local age date_str
  age=$(age_minutes "$path")
  date_str=$(item_date "$path")
  if [ "$age" -lt "$MIN_AGE_MINUTES" ]; then
    log "  SKIP (too new, ${age}m): $name"
    SKIPPED_AGE+=("$name")
    return
  fi

  # History check
  if in_history "$name" "$history"; then
    if $LIVE; then
      if [ "$type" = "dir" ]; then
        rm -rf "$path"
      else
        rm -f "$path"
      fi
      log "  DELETED [$date_str]: $name"
    else
      log "  WOULD DELETE [$date_str]: $name"
    fi
    DELETED+=("$date_str  $name")
  else
    log "  SKIP (not in history): $name"
    SKIPPED_NOT_IN_HISTORY+=("$name")
  fi
}

# --- Sonarr subfolders ---
log "=== Sonarr subfolders ==="
for item in "$SYNC_SONARR"/*/; do
  [ -d "$item" ] || continue
  name=$(basename "$item")
  process_item "$item" "$name" "$SONARR_HISTORY" "dir"
done

# --- Sonarr loose .mkv files ---
log "=== Sonarr loose .mkv files ==="
for mkv in "$SYNC_SONARR"/*.mkv; do
  [ -f "$mkv" ] || continue
  name=$(basename "$mkv")
  process_item "$mkv" "$name" "$SONARR_HISTORY" "file"
done

# --- Radarr subfolders ---
log "=== Radarr subfolders ==="
for item in "$SYNC_RADARR"/*/; do
  [ -d "$item" ] || continue
  name=$(basename "$item")
  process_item "$item" "$name" "$RADARR_HISTORY" "dir"
done

# --- Radarr loose .mkv files ---
log "=== Radarr loose .mkv files ==="
for mkv in "$SYNC_RADARR"/*.mkv; do
  [ -f "$mkv" ] || continue
  name=$(basename "$mkv")
  process_item "$mkv" "$name" "$RADARR_HISTORY" "file"
done

# --- Lidarr subfolders ---
log "=== Lidarr subfolders ==="
for item in "$SYNC_LIDARR"/*/; do
  [ -d "$item" ] || continue
  name=$(basename "$item")
  process_item "$item" "$name" "$LIDARR_HISTORY" "dir"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
log "=== Summary ==="
log "  Eligible for deletion : ${#DELETED[@]}"
log "  Skipped (too new)     : ${#SKIPPED_AGE[@]}"
log "  Skipped (not imported): ${#SKIPPED_NOT_IN_HISTORY[@]}"

if $LIVE && [ "${#DELETED[@]}" -gt 0 ]; then
  # Trigger Syncthing revert to clear locally-changed-items
  log "Triggering Syncthing revert to clear locally changed items..."
  STKEY=$(grep -o '<apikey>[^<]*' "$SYNCTHING_CONFIG" | cut -d'>' -f2)
  REVERT_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://localhost:8384/rest/db/revert?folder=$SYNCTHING_FOLDER_ID" \
    -H "X-API-Key: $STKEY")
  if [ "$REVERT_CODE" = "200" ]; then
    log "Syncthing revert triggered successfully."
  else
    log "WARNING: Syncthing revert returned HTTP $REVERT_CODE"
  fi

  # Discord notification
  DELETED_LIST=$(printf '%s\n' "${DELETED[@]}" | head -20 | sed 's/^/  • /')
  EXTRA=""
  [ "${#DELETED[@]}" -gt 20 ] && EXTRA="  …and $((${#DELETED[@]} - 20)) more"
  send_notification "🧹 **sync-cleanup**: Removed ${#DELETED[@]} imported item(s) from sync folders and triggered Syncthing revert.
\`\`\`
$DELETED_LIST
$EXTRA
\`\`\`"

elif ! $LIVE && [ "${#DELETED[@]}" -gt 0 ]; then
  log "(Dry-run — rerun with --live to actually delete)"
else
  log "Nothing to delete."
fi
```

### 7.5 Design Notes

**Dry-run by default** — no files are touched and no Discord message is sent unless `--live` is passed. Always run dry-run first to review what will be removed.

**24-hour age guard** — items newer than `MIN_AGE_MINUTES` (1440 = 24h) are skipped. Adjust the value at the top of the config section if a longer buffer is needed. This prevents race-condition deletion of content that is still actively syncing or mid-import.

**History API import check** — same `grep -qF "$name" <<< "$history"` herestring pattern as arr-rescans v4.2. If a folder or file name appears anywhere in the `downloadFolderImported` history payload, it is considered safe to delete.

**Lidarr uses `/api/v1/`** — consistent with the rest of the pipeline.

**Automatic Syncthing revert** — after a live deletion run, the script calls the Syncthing REST API to trigger a revert, clearing the locally-changed-items pile without manual intervention.

**Discord notification includes dates** — each line in the Discord summary is prefixed with the item's mtime (`YYYY-MM-DD`), showing when the content arrived on Caladan.

**Items skipped (not in history)** — these are either genuinely un-imported content (arr-rescans hasn't processed them yet) or edge cases where the folder name doesn't match the `droppedPath` recorded by the *arr app. Do not force-delete these; investigate via arr-rescans logs.

---

## 8. Known Issues & Workarounds

### 8.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 8.2 Anime Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most via alias matching. The jq payload builder handles bracket characters in SubsPlease folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 8.3 Syncthing Race Condition

arr-rescans retries every 5 minutes. Files mid-sync when a scan fires will be caught on the next run once the transfer completes.

### 8.4 Syncthing Locally Changed Items

After files are deleted from the sync folder, Syncthing tracks them as "Locally Changed Items". sync-cleanup handles this automatically via the Syncthing revert API. For manual recovery, see Section 3.5.

### 8.5 Season Pack Imports

Require Interactive Import in Sonarr. Use Wanted > Manual Import > folder > Interactive Import.

### 8.6 Fake/Malicious Torrents

arr-rescans detects .exe and other suspicious files, sends a Discord alert, and skips import. Blocklist the release in Sonarr/Radarr to trigger a search for a valid release.

### 8.7 Remote Path Mapping Host

qBittorrent remote path mapping host must be `ibiza.seedhost.eu`. Remote path must be `/home18/scytale1953/Media-sync` without trailing slash or app subfolder.

### 8.8 Foreign Language Series Title Mismatches

Sonarr stores the TVDB canonical title regardless of search term used when adding. If a series is only available under a foreign title (e.g. "La Oficina" vs "The Office (MX)"), submit the alias to TVDB. Once approved, refresh the series in Sonarr to pull in the alias.

### 8.9 Ghost Queue Entries

Completed downloads can leave orphaned queue records in `importPending` state. arr-import-monitor alerts on these. To diagnose manually:

```bash
# Check for files that have hasFile: true but are still in queue
curl -s "http://192.168.1.12:8989/api/v3/queue?pageSize=200" \
  -H "X-Api-Key: $SONARR_KEY" | jq '.records[] | select(.status == "completed") | {id, title, status}'
```

Fix — bulk delete ghost entries (does not remove from client or blocklist):

```bash
curl -s -X DELETE "http://192.168.1.12:8989/api/v3/queue/bulk?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $SONARR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"ids": [ID1, ID2]}'
```

### 8.10 Stale Radarr Queue Entries

When imports happen via DownloadedMoviesScan rather than through the normal queue flow, Radarr may retain stale "completed" queue entries. Clear manually via Radarr → Activity → Queue or via API:

```bash
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

### 8.11 Lidarr API Version

Lidarr uses `/api/v1/` not `/api/v3/`. All scripts that call Lidarr must account for this explicitly.

### 8.12 Items Not Cleaned by sync-cleanup

If a folder appears in the "Skipped (not imported)" list consistently across multiple runs, the folder name on disk may not match what's recorded in the *arr app's `droppedPath` history. Check the history directly:

```bash
source /boot/config/arr-rescans.conf
curl -s "http://192.168.1.12:8989/api/v3/history?pageSize=50&eventType=3" \
  -H "X-Api-Key: $SONARR_KEY" | jq -r '.records[].data.droppedPath // empty' | grep -i "FOLDERNAME"
```

---

## 9. Maintenance Procedures

### 9.1 Running sync-cleanup

```bash
# Dry-run first
bash /boot/config/plugins/user.scripts/scripts/sync-cleanup/script

# Live run when satisfied with dry-run output
bash /boot/config/plugins/user.scripts/scripts/sync-cleanup/script --live
```

### 9.2 Manual Sync Folder Cleanup (Nuclear Option)

When you need to wipe all sync folders entirely (e.g. after a rebuild):

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

After cleaning both sides, trigger Syncthing revert (Section 3.5).

### 9.3 Checking Import Logs

```bash
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30
docker logs sonarr --since 1h 2>&1 | grep Error | tail -20
```

### 9.4 Forcing a Manual arr-rescans Run

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

### 9.5 Running arr-import-monitor Manually

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-import-monitor/script
```

### 9.6 Resetting arr-import-monitor Alert State

Clears all deduplication state so alerts will fire again immediately on next run:

```bash
rm /tmp/arr-import-monitor.state
```

### 9.7 Checking Sync Folder Contents

```bash
ls /mnt/user/media/download/sync/sonarr/
ls /mnt/user/media/download/sync/radarr/
ls /mnt/user/media/download/sync/lidarr/
```

### 9.8 Checking Syncthing Sync Status

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

### 9.9 Updating Discord Webhook or API Keys

```bash
nano /boot/config/arr-rescans.conf
```

### 9.10 Clearing Stale Radarr Queue Entries

```bash
# Get queue IDs
curl -s "http://192.168.1.12:7878/api/v3/queue?apikey=$RADARR_KEY" | jq '.records[] | {id, title, status}'

# Delete a specific entry
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

---

## 10. Rebuild Checklist

### 10.1 Unraid Containers

- [ ] Deploy binhex-syncthing with host networking on port 8384
- [ ] Deploy Sonarr (linuxserver/sonarr) on port 8989
- [ ] Deploy Radarr (linuxserver/radarr) on port 7878
- [ ] Deploy Lidarr (linuxserver/lidarr) on port 8686
- [ ] Configure all volume mounts per Section 4.1
- [ ] **Manually add /downloads mapping to Lidarr**

### 10.2 Syncthing

- [ ] Add Media sync folder with ID `sfqzb-cvm5v`
- [ ] Set folder type to **Receive Only**
- [ ] Set folder path to `/media/sync` (container path)
- [ ] Set Rescan Interval to **0** (disabled)
- [ ] Add seedbox as remote device
- [ ] Create `/mnt/user/media/download/sync/.stignore` per Section 3.3
- [ ] **Verify ignore pattern order: exceptions FIRST, wildcard LAST**

### 10.3 *arr Apps

- [ ] Add qBittorrent download client per Section 4.2
- [ ] Add remote path mappings per Section 4.3
- [ ] Configure quality profiles
- [ ] Verify /downloads container mount present in all three apps
- [ ] Connect Discord notifications in Sonarr/Radarr

### 10.4 Seedbox

- [ ] Verify qBittorrent save path is `/home18/scytale1953/Media-sync/`
- [ ] Verify qBittorrent seeding limits (20160 min, remove torrent and files)
- [ ] Verify Syncthing cron is present
- [ ] Verify Syncthing connected to Caladan device ID

### 10.5 User Scripts

- [ ] Install User Scripts plugin in Unraid
- [ ] Create `/boot/config/arr-rescans.conf` with API keys and Discord webhook
- [ ] `chmod 600 /boot/config/arr-rescans.conf`
- [ ] Create `arr-rescans` script — retrieve from running system or git
- [ ] Set arr-rescans schedule to `*/5 * * * *`
- [ ] Create `arr-import-monitor` script — retrieve from running system or git
- [ ] Set arr-import-monitor schedule to `*/10 * * * *`
- [ ] Create `sync-cleanup` script per Section 7.4
- [ ] Set sync-cleanup schedule to `0 3 * * *`
- [ ] Test each script manually before enabling schedules
- [ ] Verify Discord notifications received from arr-rescans and arr-import-monitor

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*  
*Note: Never commit arr-rescans.conf to git — it contains sensitive credentials*
