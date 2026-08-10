# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** August 10, 2026
**Server:** Caladan (192.168.1.12) — Unraid

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Rescan Script (arr-rescans v4.5.1)](#5-rescan-script-arr-rescans-v451)
6. [Import Monitor (arr-import-monitor v2.0)](#6-import-monitor-arr-import-monitor-v20)
7. [Known Issues & Workarounds](#7-known-issues--workarounds)
8. [Maintenance Procedures](#8-maintenance-procedures)
9. [Rebuild Checklist](#9-rebuild-checklist)

---

## 1. Infrastructure Overview

### Architecture

```
qBittorrent (Seedbox) → Syncthing → /downloads (Caladan) → Sonarr / Radarr / Lidarr → Plex / Jellyfin
```

Imports happen through **two lanes**, both of which must work:

1. **arr-rescans script** — triggers `DownloadedEpisodesScan` / `DownloadedMoviesScan` per folder every 5 minutes. Primary lane.
2. **Sonarr/Radarr queue tracking** — `RefreshMonitoredDownloads` matches qBittorrent queue items to synced files via remote path mapping. Requires the app-specific remote path mappings in Section 4.3; with the pre-Aug-2026 base-path mapping this lane failed silently on every import.

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

> qBittorrent automatically cleans up Media-sync files after 14 days seeding. No manual cleanup or cron job is needed. Deletions propagate to Caladan through Syncthing — this is the **only** sanctioned deletion path for the sync folder (see Section 7.4).

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

**CRITICAL — ordering:** first match wins. Every exclusion rule must come **before** the `!` include rules; any exclusion placed after `!/sonarr/**` etc. is dead code. This exact mistake caused the sync-conflict rule to silently not function for months (see Section 7.5).

**`(?d)` prefix:** marks the pattern as deletable — Syncthing may remove matching files when they are the only thing blocking a parent directory deletion. Without `(?d)`, ignored-but-present files block deletion propagation from the seedbox, stranding directories forever ("directory not empty" loop).

File location: `/mnt/user/media/download/sync/.stignore`

```
// Exclusions MUST precede the ! includes — first match wins
// (?d) = ignore, but allow Syncthing to delete when removing a parent dir
(?d)(?i)*sample*
(?d)(?i)screens
(?d)*.nfo
(?d)*.srr
(?d)*.sync-conflict-*
// Image rules scoped to VIDEO trees only — a bare *.jpg would break Lidarr art
(?d)/sonarr/*.jpg
(?d)/sonarr/*.jpeg
(?d)/sonarr/**/*.jpg
(?d)/sonarr/**/*.jpeg
(?d)/radarr/*.jpg
(?d)/radarr/*.jpeg
(?d)/radarr/**/*.jpg
(?d)/radarr/**/*.jpeg
// Legacy cleanup — v4.4+ creates no new markers; these clear pre-v4.4 leftovers
(?d)*.imported
(?d)*.first_seen
!/sonarr
!/sonarr/**
!/radarr
!/radarr/**
!/lidarr
!/lidarr/**
*
```

> Editing `.stignore` triggers a full folder rescan. With a large local file count this takes several minutes before syncing resumes.

### 3.4 Checking Sync Status via CLI

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

Bash alias (note: not persistent across reboots unless added via `/boot/config/go`):

```bash
alias syncstatus='STKEY=$(grep -o "<apikey>[^<]*" /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d">" -f2) && curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"'
```

Reading the output: `needBytes`/`needItems` = content still to download; `needDeletes` = deletions still to apply locally. `completion` below 100 with `needBytes: 0` means only deletions are pending. `remoteState: unknown` means the seedbox device is not currently connected — "nothing needed" is then based on the last known global state, not live data.

### 3.5 Revert Local Changes

When Syncthing shows "Local Additions" and is not syncing new content, the **Revert Local Changes** button resets local state to match the seedbox. **Caution:** this deletes every locally-changed file. With a large Locally Changed count, verify what those items are before reverting — in Aug 2026 the count was 1,797 items / 572 GiB, most of which turned out to be sync-conflict debris (cleaned manually instead; see Section 8.8).

---

## 4. *arr Application Configuration

### 4.1 Docker Container Path Mappings

Verified via `docker inspect` (authoritative over UI assumptions):

| App | Host Path | Container Path | Port |
|-----|-----------|---------------|------|
| Sonarr | /mnt/user/media/download/sync/sonarr/ | /downloads | 8989 |
| Radarr | /mnt/user/media/download/sync/radarr/ | /downloads | 7878 |
| Lidarr | /mnt/user/media/download/sync/lidarr/ | /downloads | 8686 |

Media library mounts:
- Sonarr: `/mnt/user/media/tv/` → `/tv` (also `/mnt/user/media/trash/sonarr/` → `/trash`)
- Radarr: `/mnt/user/media/films/` → `/movies`
- Lidarr: `/mnt/user/media/mp3/Rock/` → `/music`

> **Note:** Lidarr does not include a /downloads mapping by default — add it manually.
>
> **Key consequence of these mounts:** `/downloads` inside each container already points *inside* the app subfolder. A path like `/downloads/sonarr/Release` does not exist in the Sonarr container — the correct container path for a release is `/downloads/Release`. This drives the remote path mapping in Section 4.3.

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

**Updated Aug 2026.** Mappings must be **app-specific**, including the category subfolder:

| App | Remote Path (Seedbox) | Local Path (Container) |
|-----|-----------------------|------------------------|
| Sonarr | /home18/scytale1953/Media-sync/sonarr/ | /downloads/ |
| Radarr | /home18/scytale1953/Media-sync/radarr/ | /downloads/ |
| Lidarr | /home18/scytale1953/Media-sync/lidarr/ | /downloads/ |

Host must be `ibiza.seedhost.eu`. Both paths end with a trailing slash.

**Why:** qBittorrent reports save paths like `/home18/scytale1953/Media-sync/sonarr/Release`. The old base-path mapping (`/Media-sync` → `/downloads/`) translated this to `/downloads/sonarr/Release` — a path that does not exist inside the container (Section 4.1). Every queue-based import failed with "path does not exist or is not accessible," repeatedly, on every `RefreshMonitoredDownloads`. The failure was masked for a long time because the arr-rescans lane performed the actual imports first. The app-specific mapping translates to `/downloads/Release`, which is correct, making the queue lane functional.

### 4.4 API Keys & Shared Config

Stored in `/boot/config/arr-rescans.conf` — see Section 5.1. This file is shared by arr-rescans and arr-import-monitor.

### 4.5 Quality Profile (HD-1080p)

- Upgrades Allowed: Yes
- Upgrade Until: Bluray-1080p
- Quality order: Remux-1080p, Bluray-1080p, WEB 1080p, HDTV-1080p

---

## 5. Rescan Script (arr-rescans v4.5.1)

### 5.1 External Config File

Sensitive values and shared settings live outside the script in `/boot/config/arr-rescans.conf`. This file persists across reboots and is never committed to git.

```bash
# /boot/config/arr-rescans.conf
SONARR_KEY="your_sonarr_api_key"
RADARR_KEY="your_radarr_api_key"
LIDARR_KEY="your_lidarr_api_key"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
VIDEO_EXTENSIONS="mkv mp4 avi m4v"
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

`VIDEO_EXTENSIONS` is used by both the loose-file scanner and the RAR guard — keep it as the single source of truth for what counts as a video file.

### 5.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
- **Schedule:** `*/5 * * * *` (every 5 minutes)

### 5.3 Design Overview

- **Import detection via history API** — each run fetches Sonarr/Radarr import history (`eventType=3`, `downloadFolderImported`) once per app and skips anything already imported. No marker files. Note `pageSize=1000` can miss records if `totalRecords` exceeds 1000.
- **Single-pass loop per app** — imported-check, sync-conflict guard, suspicious-file check, RAR guard, and the scan itself run in one loop so a skip is a real skip.
- **Sync-conflict guard (both loops)** — release folders *and* loose files whose names contain `sync-conflict` are never fed to the *arrs. Conflict copies importing as real releases was the cause of the Apr–Jul 2026 false-import incident and a repeat on Aug 9–10.
- **Empty-dir skip** — leftover empty `_unpackerred` husks and other empty directories are skipped instead of scanned (they otherwise generate "path does not exist" errors every cycle).
- **RAR guard** — defers scanning a folder while a `.rar` set is present **and** no settled video file exists (settled = mtime ≥ 5 minutes old). This protects a partially-extracted file mid-Unpackarr without deferring forever after extraction completes. v4.4's guard checked rar presence alone; because the rar set persists until weekly cleanup, every rar'd release deferred indefinitely — the single largest import-blocking bug found to date.
- **Suspicious-file detection** — folders containing .exe/.bat/.com/.scr/.js/.vbs alert Discord once (deduplicated via `/tmp/arr-rescans-suspicious.state`) and are skipped. State entries prune automatically when folders disappear.
- **Discord with Unraid fallback** — non-204 webhook responses fall back to Unraid native notifications.
- **jq `--arg` payload builder** — safely handles brackets, spaces, apostrophes in release names.

Version check: the final log line prints the running version (`arr-rescans v4.5.1 complete.`). If deployed version and documented version disagree, trust the log line.

### 5.4 Script Contents

```bash
#!/bin/bash
# arr-rescans v4.5.1
# Core function: trigger *arr scans on synced download folders.
# Import detection via Sonarr/Radarr history API — no marker files required.
# Alerting on stuck imports is handled separately by arr-import-monitor.
#
# Schedule: */5 * * * *
#
# Changes from v4.5:
#   - FIX: sync-conflict guard extended to scan_subfolders (folder-shaped
#     conflicts), not just loose files.
#
# Changes from v4.4:
#   - FIX: RAR guard deferred forever on extracted releases. v4.4 deferred on
#     rar presence alone — but the rar set persists after extraction (until
#     weekly cleanup), so every rar'd release deferred indefinitely and never
#     imported. v4.5 defers only while the rar set is present AND no settled
#     video file exists (settled = mtime older than 5 minutes, so a
#     mid-extraction .mkv is still protected).
#   - FIX: empty directories (e.g. leftover _unpackerred husks) are skipped
#     instead of scanned. v4.4 queued scans against them every cycle,
#     producing repeated "path does not exist" errors in the *arr logs.
#   - FIX: scan_loose_files now refuses sync-conflict files. The .stignore
#     (?d)*.sync-conflict-* rule prevents new conflicts, but any existing
#     conflict file at the sync root was fed to the *arrs as a real release
#     (the Apr–Jul 2026 false-import pattern). Belt-and-braces skip.
#
# Changes from v4.3:
#   - FIX: suspicious folders are now actually skipped. In v4.3 the suspicious
#     check ran in its own loop and only notified; the scan loop below it had no
#     suspicious check and scanned the folder anyway. The "Import skipped"
#     message was false. Merged into a single pass per app so the skip is real.
#   - FIX: suspicious alerts are deduplicated via a state file. In v4.3 a
#     suspicious folder never enters import history, so it re-alerted every
#     5 minutes indefinitely. (The .imported marker used to suppress this.)
#   - NEW: optional RAR guard — defer scanning folders still holding a .rar set
#     so Sonarr cannot import a partially-extracted .mkv mid-Unpackarr.
#     Delete the marked block to disable.

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

SYNC_ROOT="/mnt/user/media/download/sync"
SUSPICIOUS_STATE="/tmp/arr-rescans-suspicious.state"
touch "$SUSPICIOUS_STATE"

# Send Discord notification with Unraid fallback
send_notification() {
  local message="$1"
  local MSG=$(jq -n --arg msg "$message" '{content: $msg}')
  local HTTP_CODE=$(curl -s --max-time 30 -o /tmp/discord_response.json -w "%{http_code}" \
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

# Fetch import history once per app — eventType 3 = downloadFolderImported
# pageSize 1000 covers all but the most extreme history volumes
echo "Fetching Sonarr import history..."
SONARR_HISTORY=$(curl -s --max-time 30 \
  "$SONARR/api/v3/history?pageSize=1000&eventType=3&apikey=$SONARR_KEY" | \
  jq -r '.records[].data.droppedPath // empty')

echo "Fetching Radarr import history..."
RADARR_HISTORY=$(curl -s --max-time 30 \
  "$RADARR/api/v3/history?pageSize=1000&eventType=3&apikey=$RADARR_KEY" | \
  jq -r '.records[].data.droppedPath // empty')

# Returns 0 (true) if the given name appears in the provided history string
in_history() {
  local name="$1"
  local history="$2"
  grep -qF "$name" <<< "$history"
}

# Returns 0 (true) if the directory contains executable/script files
count_suspicious() {
  find "$1" -type f \( -iname "*.exe" -o -iname "*.bat" -o -iname "*.com" \
    -o -iname "*.scr" -o -iname "*.js" -o -iname "*.vbs" \) | wc -l
}

# Alert once per suspicious folder, not once per 5-minute run
already_alerted() {
  grep -qFx "$1" "$SUSPICIOUS_STATE"
}
mark_alerted() {
  echo "$1" >> "$SUSPICIOUS_STATE"
}

# --- RAR GUARD (optional — delete this function and its two callers to disable)
# Defers the scan while a .rar set is present AND no settled video file exists,
# so Sonarr cannot pick up a partially-extracted .mkv while Unpackarr works.
# v4.5: v4.4 deferred on rar presence alone — but the rar set persists after
# extraction (until weekly cleanup), so every rar'd release deferred forever.
# "Settled" = video file mtime at least 5 minutes old, protecting a file that
# Unpackarr is still writing at the cost of one extra scan cycle of latency.
awaiting_unpack() {
  local dir="$1"
  # No rar set → nothing to wait for
  compgen -G "${dir}*.rar" > /dev/null || return 1
  # Rar set present: if a settled video file exists, extraction is done
  local ext vid now age
  now=$(date +%s)
  for ext in $VIDEO_EXTENSIONS; do
    for vid in "${dir}"*."$ext"; do
      [ -f "$vid" ] || continue
      age=$(( now - $(stat -c %Y "$vid") ))
      [ "$age" -ge 300 ] && return 1
    done
  done
  # Rars only, or video still being written → defer
  return 0
}
# --- END RAR GUARD

# Refresh tracked queue items
curl -s --max-time 30 -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$SONARR/api/v3/command" > /dev/null
curl -s --max-time 30 -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$RADARR/api/v3/command" > /dev/null
curl -s --max-time 30 -X POST -H "X-Api-Key: $LIDARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$LIDARR/api/v1/command" > /dev/null

# Scan subfolders for one app.
#   $1 = app label   $2 = sync subdir   $3 = command name
#   $4 = API key     $5 = base URL      $6 = history blob
scan_subfolders() {
  local label="$1" subdir="$2" command="$3" key="$4" url="$5" history="$6"

  for item in "$SYNC_ROOT/$subdir"/*/; do
    [ -d "$item" ] || continue

    # Empty dir (e.g. leftover _unpackerred husk) — nothing to scan
    if ! find "$item" -mindepth 1 -print -quit | grep -q .; then
      continue
    fi

    local folder
    folder=$(basename "$item")

    # Never feed Syncthing conflict copies to the *arrs — folder-shaped variant
    # of the loose-file guard below
    case "$folder" in
      *sync-conflict*)
        echo "$label skip (sync-conflict): $folder"
        continue
        ;;
    esac

    # Already imported — nothing to do
    if in_history "$folder" "$history"; then
      echo "$label skip (imported): $folder"
      continue
    fi

    # Suspicious content — alert once, and genuinely skip the scan
    local suspicious
    suspicious=$(count_suspicious "$item")
    if [ "$suspicious" -gt 0 ]; then
      if ! already_alerted "$folder"; then
        send_notification "🚨 **Suspicious files in $label download**: \`$folder\` contains $suspicious potentially malicious file(s). Import skipped — manual review required."
        mark_alerted "$folder"
      fi
      echo "$label SUSPICIOUS, skipping: $folder"
      continue
    fi

    # --- RAR GUARD caller (delete these 4 lines to disable)
    if awaiting_unpack "$item"; then
      echo "$label defer (awaiting unpack): $folder"
      continue
    fi
    # --- END RAR GUARD caller

    local PAYLOAD
    PAYLOAD=$(jq -n --arg name "$command" --arg path "/downloads/$folder" \
      '{name: $name, path: $path}')
    curl -s --max-time 30 -X POST -H "X-Api-Key: $key" -H "Content-Type: application/json" \
      -d "$PAYLOAD" "$url/api/v3/command" > /dev/null
    echo "$label scan queued: $folder"
  done
}

# Scan loose video files at the root of one app's sync dir.
#   $1 = app label   $2 = sync subdir   $3 = command name
#   $4 = API key     $5 = base URL      $6 = history blob
scan_loose_files() {
  local label="$1" subdir="$2" command="$3" key="$4" url="$5" history="$6"

  for ext in $VIDEO_EXTENSIONS; do
    for vid in "$SYNC_ROOT/$subdir"/*."$ext"; do
      [ -f "$vid" ] || continue
      local filename
      filename=$(basename "$vid")

      # Never feed Syncthing conflict copies to the *arrs — these are the
      # source of the Apr–Jul 2026 false-import incident
      case "$filename" in
        *sync-conflict*)
          echo "$label skip (sync-conflict): $filename"
          continue
          ;;
      esac

      if in_history "$filename" "$history"; then
        echo "$label skip (imported): $filename"
        continue
      fi

      local PAYLOAD
      PAYLOAD=$(jq -n --arg name "$command" --arg path "/downloads/$filename" \
        '{name: $name, path: $path}')
      curl -s --max-time 30 -X POST -H "X-Api-Key: $key" -H "Content-Type: application/json" \
        -d "$PAYLOAD" "$url/api/v3/command" > /dev/null
      echo "$label scan queued: $filename"
    done
  done
}

scan_subfolders  "Sonarr" "sonarr" "DownloadedEpisodesScan" "$SONARR_KEY" "$SONARR" "$SONARR_HISTORY"
scan_subfolders  "Radarr" "radarr" "DownloadedMoviesScan"   "$RADARR_KEY" "$RADARR" "$RADARR_HISTORY"

scan_loose_files "Sonarr" "sonarr" "DownloadedEpisodesScan" "$SONARR_KEY" "$SONARR" "$SONARR_HISTORY"
scan_loose_files "Radarr" "radarr" "DownloadedMoviesScan"   "$RADARR_KEY" "$RADARR" "$RADARR_HISTORY"

# Prune state entries for folders that no longer exist, so a re-download of the
# same release can alert again rather than being silently suppressed forever.
if [ -s "$SUSPICIOUS_STATE" ]; then
  while read -r name; do
    [ -n "$name" ] || continue
    if [ -d "$SYNC_ROOT/sonarr/$name" ] || [ -d "$SYNC_ROOT/radarr/$name" ]; then
      echo "$name"
    fi
  done < "$SUSPICIOUS_STATE" > "${SUSPICIOUS_STATE}.tmp"
  mv "${SUSPICIOUS_STATE}.tmp" "$SUSPICIOUS_STATE"
fi

echo "arr-rescans v4.5.1 complete."
```

---

## 6. Import Monitor (arr-import-monitor v2.0)

Separate script; alerting on stuck imports lives here, not in arr-rescans.

- **Schedule:** every 15 minutes
- Queries Sonarr/Radarr/Lidarr queue APIs for `importPending` / `importFailed` states
- Deduplicates alerts via a state file with prefixed keys (`fs:`, `queue:`); auto-clears resolved entries
- **Known blind spots:**
  - Only watches the active queue. If a series is removed from Sonarr, its downloads are stranded permanently with no alert.
  - If downloads never reach the queue at all (e.g. Syncthing folder stopped — Aug 2026 incident), the monitor stays silent. Silence from the monitor means "nothing is stuck in the queue," not "everything is arriving."

---

## 7. Known Issues & Workarounds

### 7.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 7.2 Anime / Foreign Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End", "La Oficina" vs "The Office (MX)"). Sonarr handles most via alias matching; the jq payload builder handles bracketed folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 7.3 Syncthing Race Condition

The rescan script retries every 5 minutes, so files mid-sync are caught on subsequent runs. The RAR guard's 5-minute settle time additionally protects mid-extraction files.

### 7.4 Receive Only Folder — Deletion Rules

Never delete **tracked** files locally from the Receive Only folder: Syncthing re-downloads them on the next pull and generates `sync-conflict` copies (the cause of ~100 false imports Apr–Jul 2026). Deletions must originate on the seedbox (14-day qBittorrent cleanup) and propagate through Syncthing.

**Exception:** files that global state already shows as deleted (the seedbox copy is gone) and files matched by ignore patterns (e.g. sync-conflict debris) are safe to remove locally — there is nothing to re-download.

### 7.5 Sync-Conflict Files (root-caused Aug 2026)

**Mechanism:** when local state diverges from announced global state in a Receive Only folder (interrupted syncs, local metadata changes, shfs hiccups), Syncthing preserves the divergent copy under a `*.sync-conflict-YYYYMMDD-HHMMSS-*` name. These files are byte-copies of legitimate releases, so when fed to the *arrs they import successfully under the conflict name — polluting history and masking their origin.

**History:** the `(?d)*.sync-conflict-*` ignore rule existed but sat **below** the `!` includes — dead code (Section 3.3 ordering). Conflicts accumulated for a month: 830 files / 361 GiB found and deleted on Aug 10, 2026, which also explained the inflated Locally Changed count and dozens of stuck directory deletions.

**Current defenses (three layers):**
1. `.stignore` rule, correctly ordered — new conflicts are ignored and deletable
2. arr-rescans v4.5.1 refuses conflict-named folders and files
3. Untracked conflict files no longer block seedbox-originated directory deletions (via `(?d)`)

**Watch signal:** any *new* `sync-conflict` file appearing post-fix means the ignore ordering regressed or something is mutating files locally — investigate immediately:
```bash
find /mnt/user/media/download/sync/ -name "*sync-conflict*" -newermt "2026-08-10"
```

### 7.6 Sticky Folder Error State ("Stopped")

When Syncthing hits a folder-level error (e.g. `stat /media/sync/.stfolder: permission denied`), it stops the folder and **caches the error indefinitely** — it does not retry even after the underlying cause resolves. Seen Aug 2026: a transient error during a boot window kept the folder stopped for a day while host and container permissions checked out perfectly.

**Diagnosis:** verify the path from both sides —
```bash
ls -ld /mnt/user/media/download/sync/.stfolder
docker exec binhex-syncthing stat /media/sync/.stfolder
```
If both succeed but the folder shows Stopped, the error is stale.

**Fix:** `docker restart binhex-syncthing` (or Pause → Resume the folder).

### 7.7 Season Pack Imports

Require Interactive Import in Sonarr. Use Wanted > Manual Import > folder > Interactive Import.

### 7.8 Fake/Malicious Torrents

The rescan script detects .exe and other suspicious files, sends a single Discord alert, and skips import. Blocklist the release in Sonarr/Radarr to trigger a search for a valid release.

### 7.9 Stale Queue Entries / Ghost Entries

When imports happen via the scan lane rather than the queue, stale "completed" queue entries can remain, as can orphaned `importPending` records where the episode already has a file. Clear via UI or API:
```bash
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```
Bulk variant: `/api/v3/queue/bulk` DELETE with `removeFromClient=false&blocklist=false`.

### 7.10 API Verification Gotchas

- **`/api/v3/parse` does not populate `episodeFile`** — checking `hasFile` through the parse endpoint always reads false. Use `/api/v3/episode?seriesId=N` (authoritative) or `/api/v3/episodefile?seriesId=N`.
- **Sourcing the conf is per-shell** — an empty `$SONARR_KEY` makes the API return an auth error object, which jq filters silently drop, producing empty output that looks like "no results." Check `echo "${SONARR_KEY:0:4}"` before trusting an empty API response.
- **`dateAdded` vs file mtime can legitimately disagree** — Syncthing and archive extraction preserve source mtimes.

---

## 8. Maintenance Procedures

### 8.1 Checking Import Logs

```bash
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30
docker logs sonarr --since 1h 2>&1 | grep Error | tail -20
```

### 8.2 Checking Recent Imports via API

```bash
source /boot/config/arr-rescans.conf
curl -s "http://192.168.1.12:8989/api/v3/history?pageSize=20&eventType=3&apikey=$SONARR_KEY" | \
  jq -r '.records[] | "\(.date)  \(.sourceTitle)"'
```

### 8.3 Forcing a Manual Rescan

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

Useful filtered view (hides the imported-skip noise):
```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script 2>&1 | grep -vE "skip \(imported\)"
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

### 8.6 Checking Syncthing Folder Health / Deletions

```bash
docker logs binhex-syncthing --since 1h 2>&1 | grep -iE "delete|failed to sync|error"
```

Recurring "directory not empty" on the same directory = untracked local files blocking a propagated deletion. Inspect with `find <dir> -mindepth 1` and resolve per Section 7.4/7.5.

### 8.7 Updating Discord Webhook, API Keys, or Video Extensions

```bash
nano /boot/config/arr-rescans.conf
```

### 8.8 Sync-Conflict Sweep

Count and size first (dry-run pattern):
```bash
find /mnt/user/media/download/sync/ -name "*sync-conflict*" -type f -printf '%s\n' | \
  awk '{s+=$1} END {printf "%d files, %.1f GiB\n", NR, s/1073741824}'
```

Then delete (safe — conflict files are ignored and untracked; no re-download risk):
```bash
find /mnt/user/media/download/sync/ -name "*sync-conflict*" -type f -delete
```

Expected result post-Aug-2026: zero files. Any nonzero count is the watch signal from Section 7.5.

### 8.9 Verifying Container Mounts

When path behavior seems wrong, ask Docker rather than the UI or documentation:
```bash
docker inspect sonarr --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
```

### 8.10 Verifying Queue-Lane Health (Remote Path Mapping)

```bash
source /boot/config/arr-rescans.conf
curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "http://192.168.1.12:8989/api/v3/command" > /dev/null
sleep 20
docker logs sonarr --since 1m 2>&1 | grep -c "path does not exist"
```

`0` = mapping healthy. Nonzero = remote path mapping regression (Section 4.3).

### 8.11 Manual Sync Folder Cleanup (full reset)

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

After cleaning both sides, click **Revert Local Changes** in Caladan's Syncthing UI. Only appropriate as a full reset — for routine operation, rely on the seedbox 14-day cleanup.

---

## 9. Rebuild Checklist

### 9.1 Unraid Containers

- [ ] Deploy binhex-syncthing with host networking on port 8384
- [ ] Deploy Sonarr (linuxserver/sonarr) on port 8989
- [ ] Deploy Radarr (linuxserver/radarr) on port 7878
- [ ] Deploy Lidarr (linuxserver/lidarr) on port 8686
- [ ] Configure all volume mounts per Section 4.1
- [ ] **Manually add /downloads mapping to Lidarr**
- [ ] Verify mounts via `docker inspect` (Section 8.9)

### 9.2 Syncthing

- [ ] Add Media sync folder with ID `sfqzb-cvm5v`
- [ ] Set folder type to **Receive Only**
- [ ] Set folder path to `/media/sync` (container path)
- [ ] Add seedbox as remote device
- [ ] Create `/mnt/user/media/download/sync/.stignore` per Section 3.3
- [ ] **Verify ignore pattern order: ALL exclusions FIRST, includes next, wildcard LAST**
- [ ] Verify `(?d)*.sync-conflict-*` is present and above the includes

### 9.3 *arr Apps

- [ ] Add qBittorrent download client per Section 4.2
- [ ] Add **app-specific** remote path mappings per Section 4.3 (include the category subfolder)
- [ ] Verify queue-lane health per Section 8.10 (expect 0 path errors)
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
- [ ] Create `/boot/config/arr-rescans.conf` with API keys, Discord webhook, and VIDEO_EXTENSIONS (Section 5.1)
- [ ] `chmod 600 /boot/config/arr-rescans.conf`
- [ ] Create `arr-rescans` script per Section 5.4 (v4.5.1)
- [ ] Set schedule to `*/5 * * * *`
- [ ] Create `arr-import-monitor` script, schedule every 15 minutes
- [ ] Test arr-rescans manually — confirm version line reads v4.5.1
- [ ] Verify Discord alert path (real event, not the Test button)

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*
*Note: Never commit arr-rescans.conf to git — it contains sensitive credentials*
