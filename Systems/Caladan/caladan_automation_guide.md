# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** April 2026  
**Server:** Caladan (192.168.1.12) — Unraid  

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Rescan Script (arr-rescans)](#5-rescan-script-arr-rescans)
6. [Import Monitor (arr-import-monitor)](#6-import-monitor-arr-import-monitor)
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

## 5. Rescan Script (arr-rescans)

**Current version: v4.2**

### 5.1 External Config File

Sensitive values are stored outside the script in `/boot/config/arr-rescans.conf`. This file persists across reboots and is never committed to git.

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

**History API for import detection** — at startup the script fetches `downloadFolderImported` history (eventType=3) from Sonarr and Radarr and holds it in memory. Per-folder/file checks use herestring grep (`grep -qF "$name" <<< "$history"`) to skip already-imported items. This replaces the marker-file approach entirely.

**Why herestring, not echo pipe** — `grep -qF "$name" <<< "$history"` is required to avoid broken pipe errors when grep exits early against large strings. The echo pipe pattern breaks on large history payloads.

**Marker files completely removed** — `.imported` and `.first_seen` files are wiped by server restarts and parity operations, causing re-import loops. History API polling is the robust replacement.

**Alerting delegated to arr-import-monitor** — this script only triggers scans. Stuck-import detection and Discord alerts are handled entirely by arr-import-monitor (Section 6). Clean separation of concerns.

**DownloadedEpisodesScan / DownloadedMoviesScan per folder** — core import mechanism. Scans each subfolder individually and handles loose .mkv files directly.

**jq `--arg` payload builder** — safely handles special characters in folder names including brackets, spaces, and apostrophes common in anime and foreign language releases.

**Suspicious file detection** — alerts Discord and skips import for folders containing .exe, .bat, .com, .scr, .js, or .vbs files.

**Lidarr uses `/api/v1/`** — all Lidarr API calls must use `/api/v1/` not `/api/v3/`. Sonarr and Radarr use `/api/v3/`.

**`--max-time 10` on all curls** — prevents script from hanging if an *arr app is unresponsive.

> To retrieve the canonical current script: `cat /boot/config/plugins/user.scripts/scripts/arr-rescans/script`

---

## 6. Import Monitor (arr-import-monitor)

**Current version: v2.0**

### 6.1 Purpose

Runs every 15 minutes, queries the Sonarr/Radarr/Lidarr queue APIs for items stuck in `importPending` or `importFailed` state, and sends Discord alerts with deduplication. This script only alerts — it never triggers scans.

### 6.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-import-monitor/script`
- **Schedule:** `*/15 * * * *` (every 15 minutes)

### 6.3 State File

- **Path:** `/tmp/arr-import-monitor.state`
- Cleared on reboot (intentional — fresh alert state after restarts)
- Format: `app:id=timestamp` for alert deduplication, `app:id_first=timestamp` for age tracking
- An empty state file after reboot is normal

### 6.4 Script Contents

```bash
#!/bin/bash
# arr-import-monitor v2.0
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
  local -n _keys_ref=$1
  local tmp=$(mktemp)
  while IFS='=' read -r key ts; do
    [ -z "$key" ] && continue
    local found=0
    for active in "${_keys_ref[@]}"; do
      [ "$active" = "$key" ] && found=1 && break
    done
    [ $found -eq 1 ] && echo "${key}=${ts}" >> "$tmp"
  done < "$STATE_FILE"
  mv "$tmp" "$STATE_FILE"
}

# Process queue for a single *arr instance
# Args: $1=app_name $2=base_url $3=api_key $4=api_version (optional, default v3)
check_queue() {
  local app="$1"
  local url="$2"
  local key="$3"
  local api_ver="${4:-v3}"
  local now=$(date +%s)
  local active_keys=()

  local queue
  queue=$(curl -s -H "X-Api-Key: $key" \
    "${url}/api/${api_ver}/queue?pageSize=200&includeUnknownMovieItems=true&includeUnknownSeriesItems=true")

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

  # Prune state entries for items no longer in queue
  prune_state active_keys
}

check_queue "Sonarr" "$SONARR" "$SONARR_KEY"
check_queue "Radarr" "$RADARR" "$RADARR_KEY"
check_queue "Lidarr" "$LIDARR" "$LIDARR_KEY" "v1"

echo "arr-import-monitor complete"
```

### 6.5 Script Design Notes

**Separation of concerns** — this script only alerts; it never triggers scans. arr-rescans only scans; it never alerts. Each script does one thing.

**First-seen tracking** — age is calculated from when the monitor first noticed the item in a stuck state, stored in the state file as `key_first`. More reliable than API time fields, which are inconsistent across *arr versions.

**Per-item deduplication** — each queue item gets an `app:id` key in the state file. Alerts are suppressed until `IMPORT_REALERT_SECONDS` has elapsed since the last alert for that item (default 1 hour).

**State file pruning** — `prune_state` removes entries for items that have left the queue, keeping the state file from growing unboundedly.

**Lidarr uses `/api/v1/`** — `check_queue` accepts an optional 4th argument for the API version, defaulting to `v3`. The Lidarr call passes `"v1"` explicitly. Sonarr and Radarr use the default `v3`.

**`prune_state` nameref pattern** — uses `local -n _keys_ref=$1` (note the distinct name `_keys_ref`) to avoid a bash circular nameref error that occurs if the nameref parameter name matches the caller's local variable name (`active_keys`).

**Ghost queue entries** — when a replacement release is grabbed and imported, the original queue entry can remain orphaned in `importPending` state. Diagnose with the library API (`hasFile: true`); clear via `/queue/bulk` with `removeFromClient=false`. See Section 7.9.

---

## 7. Known Issues & Workarounds

### 7.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 7.2 Anime Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most via alias matching. The jq payload builder handles bracket characters in SubsPlease folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 7.3 Syncthing Race Condition

arr-rescans retries every 5 minutes, so files mid-sync will be caught on subsequent runs.

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

### 7.9 Ghost Queue Entries

When a replacement release is grabbed and imported, the original queue entry can remain orphaned in `importPending` state indefinitely. arr-import-monitor will alert on these after the threshold.

Diagnose — confirm the file is actually in the library:
```bash
# Check if Sonarr already has the file
curl -s "http://192.168.1.12:8989/api/v3/queue" -H "X-Api-Key: $SONARR_KEY" \
  | jq '.records[] | select(.status=="importPending") | {id, title}'
```

Clear the orphaned entry:
```bash
curl -s -X DELETE \
  "http://192.168.1.12:8989/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $SONARR_KEY"
```

Same pattern applies to Radarr (port 7878, `DownloadedMoviesScan`).

### 7.10 Stale Radarr Queue Entries

When imports happen via DownloadedMoviesScan rather than through the normal queue flow, Radarr may retain stale "completed" queue entries. Clear manually via Radarr → Activity → Queue or via API:

```bash
# Get queue IDs
curl -s "http://192.168.1.12:7878/api/v3/queue" \
  -H "X-Api-Key: $RADARR_KEY" | jq '.records[] | {id, title, status}'

# Delete a specific entry
curl -s -X DELETE \
  "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

### 7.11 Lidarr API Version

Lidarr uses `/api/v1/` — not `/api/v3/` like Sonarr and Radarr. Any script or manual curl hitting Lidarr must use the correct path or will get a silent empty response.

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

### 8.4 Running Import Monitor Manually

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-import-monitor/script
```

### 8.5 Resetting Import Monitor Alert State

```bash
# Clear all alert state (next run will re-evaluate everything fresh)
> /tmp/arr-import-monitor.state
```

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

### 8.8 Updating Discord Webhook or API Keys

```bash
nano /boot/config/arr-rescans.conf
```

### 8.9 Bulk Queue Clear

```bash
# Get all stuck queue IDs from Sonarr
curl -s "http://192.168.1.12:8989/api/v3/queue?pageSize=200" \
  -H "X-Api-Key: $SONARR_KEY" \
  | jq '[.records[] | select(.status=="importPending") | .id]'

# Bulk delete by ID array
curl -s -X DELETE "http://192.168.1.12:8989/api/v3/queue/bulk?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $SONARR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"ids":[ID1,ID2,ID3]}'
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
- [ ] **Verify Lidarr API calls use `/api/v1/` not `/api/v3/`**

### 9.4 Seedbox

- [ ] Verify qBittorrent save path is `/home18/scytale1953/Media-sync/`
- [ ] Verify qBittorrent seeding limits (20160 min, remove torrent and files)
- [ ] Verify Syncthing cron is present
- [ ] Verify Syncthing connected to Caladan device ID

### 9.5 User Scripts

- [ ] Install User Scripts plugin in Unraid
- [ ] Create `/boot/config/arr-rescans.conf` with API keys and Discord webhook
- [ ] `chmod 600 /boot/config/arr-rescans.conf`
- [ ] Create `arr-rescans` script at `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
- [ ] Set arr-rescans schedule to `*/5 * * * *`
- [ ] Create `arr-import-monitor` script per Section 6.4
- [ ] Set arr-import-monitor schedule to `*/15 * * * *`
- [ ] Test both scripts by running manually from the Unraid UI
- [ ] Verify Discord alerts received

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*  
*Note: Never commit arr-rescans.conf to git — it contains sensitive credentials*
