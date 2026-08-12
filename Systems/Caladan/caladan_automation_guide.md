# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** August 2026
**Server:** Caladan (192.168.1.12) — Unraid 7.2.4

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Content Lifecycle](#2-content-lifecycle)
3. [Seedbox Configuration](#3-seedbox-configuration-seedhosteu)
4. [Syncthing Configuration](#4-syncthing-configuration)
5. [*arr Application Configuration](#5-arr-application-configuration)
6. [Unpackerr Configuration](#6-unpackerr-configuration)
7. [Automation Scripts](#7-automation-scripts)
8. [Known Issues & Workarounds](#8-known-issues--workarounds)
9. [Maintenance & Triage](#9-maintenance--triage)
10. [Rebuild Checklist](#10-rebuild-checklist)

---

## 1. Infrastructure Overview

### Architecture

```
qBittorrent (seedbox) → Syncthing → /mnt/user/media/download/sync/ (Caladan)
                                        ├─ Unpackerr (extracts rar sets)
                                        └─ arr-rescans (*/5) → Sonarr / Radarr / Lidarr → library → Plex / Jellyfin
Monitoring: arr-import-monitor (*/15, queue) + arr-cleanup (daily, residue) → Discord
```

### Key Infrastructure

| Component | Value |
|-----------|-------|
| Caladan IP | 192.168.1.12 |
| Caladan OS | Unraid 7.2.4 |
| Hardware | Supermicro X10SRL-F, Xeon E5-2630 v3, 32 GiB DDR4 ECC, RTX 3060 |
| Seedbox Host | scytale1953.ibiza.seedhost.eu |
| Seedbox User | scytale1953 |
| Seedbox Base Path | /home18/scytale1953/ |
| Media Sync Path (Seedbox) | ~/Media-sync/ |
| Media Sync Path (Caladan) | /mnt/user/media/download/sync/ |
| Syncthing Folder ID | sfqzb-cvm5v |
| Caladan Syncthing Port | 8384 |
| Shared config file | /boot/config/arr-rescans.conf |

### Deployed Script Versions

| Script | Version | Schedule | Role |
|--------|---------|----------|------|
| arr-rescans | v4.5.1 | */5 * * * * | Trigger *arr scans on synced folders |
| arr-import-monitor | v1.2 | */15 * * * * | Alert on queue items stuck in import states |
| arr-cleanup | v2.0 | daily | Remove local-only residue from sync tree |

---

## 2. Content Lifecycle

**This is the single most important mental model for operating the pipeline.** Several
"problems" observed on this system are normal phases of this lifecycle, and several
plausible-looking interventions (Revert Local Changes, manual sync-tree deletion)
actively cause harm. Validated empirically August 2026.

```
1. Grab       *arr sends torrent to seedbox qBittorrent (category sonarr/radarr/lidarr)
2. Download   qBittorrent saves under ~/Media-sync/<app>/
3. Sync       Syncthing (send-only) → Caladan sync tree (Receive Only)
4. Extract    If rar'd: Unpackerr extracts (extracted mkv = LOCAL ADDITION,
              never existed on seedbox)
5. Import     arr-rescans triggers DownloadedEpisodesScan/DownloadedMoviesScan.
              Import is a MOVE (payload sets no importMode; different physical
              disks under unionfs, so no hardlink either way). The source file
              leaves the sync tree → Syncthing pins it as a LOCAL DELETE.
6. Age out    Seedbox qBittorrent removes torrent+files at 14 days seeding
              (20160 min, validated: fires on schedule)
7. Resolve    Seedbox-side deletion propagates; global state now matches
              Caladan's local delete → pin clears automatically
8. Residue    Anything the seedbox never tracked (extracted mkvs, _unpackerred
              renamed folders, empty husk dirs) is invisible to propagation.
              arr-cleanup removes it once Syncthing global state confirms
              the seedbox no longer references the path.
```

### Consequences of the lifecycle

- **`receiveOnlyChangedFiles` / `receiveOnlyChangedDeletes` climbing is the
  signature of imports working, not a fault.** These counters are a *flow*:
  imports create pins, seedbox age-out resolves them. Healthy steady state is
  oscillation around a baseline, with no pin older than ~14 days.
- **Pinned local deletes do NOT trigger re-downloads.** `needFiles` stays 0.
  (The historical re-download/conflict incident had a different mechanism;
  see §8.6.)
- **Revert Local Changes is an emergency tool, not maintenance.** Pressing it
  mid-window re-downloads *every file imported in the last 14 days* (26+ items,
  potentially tens of GB) and deletes all local additions. Only use it when the
  folder is genuinely wedged and you accept the re-transfer.
- **Never manually delete seedbox-tracked files from the sync tree.** Let the
  14-day removal propagate. Local-only residue is arr-cleanup's job, and it
  verifies tracking state via the Syncthing API before touching anything.

---

## 3. Seedbox Configuration (seedhost.eu)

### 3.1 qBittorrent

qBittorrent is the active download client: `https://ibiza.seedhost.eu/scytale1953/qbittorrent/`

**Tools → Options → Downloads:**
- Default Save Path: `/home18/scytale1953/Media-sync/`

**Tools → Options → BitTorrent (Seeding Limits):**
- When ratio reaches: disabled (0)
- When seeding time reaches: 20160 minutes (14 days)
- Then: Remove torrent and files

> Validated Aug 2026: torrents are removed within hours of crossing 14.0 days
> seeding. All torrents carry `max_seeding_time: 20160` (no per-torrent
> overrides from the *arrs). Verify anytime via the API check in §9.4.

### 3.2 qBittorrent Download Categories

| Category | Save Path |
|----------|-----------|
| sonarr | /home18/scytale1953/Media-sync/sonarr/ |
| radarr | /home18/scytale1953/Media-sync/radarr/ |
| lidarr | /home18/scytale1953/Media-sync/lidarr/ |

### 3.3 Seedbox Cron

Only the Syncthing watchdog:

```cron
MAILTO=""
*/5 * * * * /bin/bash ~/software/cron/syncthing
```

### 3.4 Media-sync Folder Structure

| Directory | Purpose |
|-----------|---------|
| sonarr/ | TV downloads — synced to Caladan |
| radarr/ | Movie downloads — synced to Caladan |
| lidarr/ | Music downloads — synced to Caladan |
| freeleech/, prowlarr/, radarr-4k/, foo/ | NOT synced (ignored) |

### 3.5 ruTorrent (Legacy)

Installed but unused. If ever switching back: ratio plugin MAX_RATIO 9999,
`~/www/.../rutorrent/plugins/ratio/conf.php`, ratio group 1 Time 336h →
Remove.

---

## 4. Syncthing Configuration

### 4.1 Caladan Syncthing Container

| Setting | Value |
|---------|-------|
| Container Name | binhex-syncthing |
| Image | binhex/arch-syncthing |
| Network Mode | host |
| Web UI Port | 8384 |
| Config Path | /mnt/user/appdata/binhex-syncthing/ |
| Sync Mount | /mnt/user/media/download/sync/ → /media/sync |

### 4.2 Folder Configuration

| Setting | Value |
|---------|-------|
| Folder ID | sfqzb-cvm5v |
| Folder Type (Caladan) | Receive Only |
| Folder Type (Seedbox) | Send Only |
| Rescan Interval | 1 hour |

### 4.3 Ignore Patterns

File: `/mnt/user/media/download/sync/.stignore`

**CRITICAL — first match wins.** All exclusions must precede the includes; any
exclusion placed below `!/sonarr/**` etc. is unreachable dead code. Structure:

```
# 1. Exclusions — (?d) prefix allows Syncthing to delete them when removing
#    a parent directory
(?d)(?i)*sample*
(?d)(?i)screens
(?d)*.nfo
(?d)*.srr
(?d)*.sync-conflict-*
# Tree-scoped image excludes for sonarr/radarr ONLY — Lidarr album art must sync
(?d)/sonarr/**/*.jpg
(?d)/sonarr/**/*.png
(?d)/radarr/**/*.jpg
(?d)/radarr/**/*.png
# Vestigial marker rules (pre-v4.4 era; harmless)
(?d)*.imported
(?d)*.first_seen

# 2. Includes
!/sonarr
!/sonarr/**
!/radarr
!/radarr/**
!/lidarr
!/lidarr/**

# 3. Catch-all — everything else ignored
*
```

> The exclusion block above is reconstructed from the working configuration —
> when rebuilding, prefer copying the live `.stignore` if available. The
> structural rule (exclusions → includes → `*`) is the invariant.

### 4.4 Checking Sync Status via CLI

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/status?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY" \
  | jq '{state, needFiles, needBytes, receiveOnlyChangedFiles, receiveOnlyChangedDeletes}'
```

Reading it (per §2): nonzero `receiveOnlyChanged*` is normal; `needFiles`
nonzero means an actual pending transfer; pins older than the oldest live
torrent (~14 days) indicate propagation failure. List the pins:

```bash
curl -s "http://localhost:8384/rest/db/localchanged?folder=sfqzb-cvm5v&perpage=1000" -H "X-API-Key: $STKEY" \
  | jq -r '.files[] | [(if .deleted then "DELETED" else "modified/added" end), .name] | @tsv' | sort
```

### 4.5 Revert Local Changes — EMERGENCY USE ONLY

Superseded guidance: earlier revisions of this guide recommended Revert Local
Changes as routine maintenance. **Under the current move-import pipeline this
is wrong** — see §2. Reverting re-downloads everything imported inside the
14-day window and deletes all local additions. Use only for a genuinely wedged
folder, with the re-transfer cost understood. For stuck locally-changed-items
deadlocks where the Revert button is unavailable, the recovery path is wiping
the index DB (`index-v0.14.0.db`) with the container stopped.

---

## 5. *arr Application Configuration

### 5.1 Docker Container Path Mappings

| App | Host Path | Container Path | Port |
|-----|-----------|---------------|------|
| Sonarr | /mnt/user/media/download/sync/sonarr/ | /downloads | 8989 |
| Radarr | /mnt/user/media/download/sync/radarr/ | /downloads | 7878 |
| Lidarr | /mnt/user/media/download/sync/lidarr/ | /downloads | 8686 |

Media library mounts:
- Sonarr: `/mnt/user/media/tv/` → `/tv`
- Radarr: `/mnt/user/media/films/` → `/movies`
- Lidarr: `/mnt/user/media/mp3/Rock/` → `/music`

> Lidarr does not include a /downloads mapping by default — add it manually.

> Import mode note: DownloadedEpisodesScan/DownloadedMoviesScan import by
> **move** (arr-rescans payloads set no importMode). Sync folder and library
> are on different physical disks under unionfs, so hardlinks are not possible
> regardless. Move is the intended behavior — it feeds the pinned-delete
> lifecycle (§2). Do not "fix" it to Copy: that doubles disk usage for up to
> 14 days per item with no benefit.

### 5.2 Download Client Configuration (All *arrs)

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

### 5.3 Remote Path Mappings — APP-SPECIFIC

| App | Remote Path (Seedbox) | Local Path (Container) |
|-----|-----------------------|------------------------|
| Sonarr | /home18/scytale1953/Media-sync/sonarr/ | /downloads/ |
| Radarr | /home18/scytale1953/Media-sync/radarr/ | /downloads/ |
| Lidarr | /home18/scytale1953/Media-sync/lidarr/ | /downloads/ |

> Host must be `ibiza.seedhost.eu`. Mappings must be **app-specific** (include
> the app subfolder), because each app's /downloads mount points at its own
> subfolder. A base-path mapping (`/Media-sync` → `/downloads/`) fails
> *silently*: the scan lane (arr-rescans) still imports everything, masking
> the broken queue lane for months. Fixed 2026; do not regress.

### 5.4 API Keys

Stored in `/boot/config/arr-rescans.conf` — see §7.1.

### 5.5 Quality Profile (HD-1080p)

- Upgrades Allowed: Yes; Upgrade Until: Bluray-1080p
- Quality order: Remux-1080p, Bluray-1080p, WEB 1080p, HDTV-1080p

### 5.6 API Version Reference

| App | API base | Queue endpoint |
|-----|----------|----------------|
| Sonarr | /api/v3/ | /api/v3/queue |
| Radarr | /api/v3/ | /api/v3/queue |
| Lidarr | **/api/v1/** | /api/v1/queue |

Key field facts (hard-won):
- Import states (`importPending`, `importBlocked`, `importFailed`) live in
  **`trackedDownloadState`**, NOT `status`. `status` carries download-client
  state (`completed`, `downloading`, …) and never holds import states.
- `statusMessages[].messages[]` carries the human-readable reason (e.g.
  "Found archive file, might need to be extracted").
- `/api/v3/parse` never populates `episodeFile` — use
  `/api/v3/episode?seriesId=N` for hasFile checks.
- Empty API output almost always means a missing/unloaded config key, not an
  empty result. Verify with `echo "${SONARR_KEY:0:4}"` first.
- `pageSize=1000` history fetches can miss records if `totalRecords` > 1000.

---

## 6. Unpackerr Configuration

Unpackerr polls the *arr queues and extracts rar sets so the *arrs can import.
It is **queue-driven only** — an item whose queue entry has expired is
invisible to it (see §8.3).

### 6.1 Container

| Setting | Value |
|---------|-------|
| Container Name | unpackerr |
| Volume Mount | /mnt/user/media/download/sync → /downloads |

### 6.2 Environment Variables

| Variable | Value |
|----------|-------|
| UN_SONARR_0_URL | http://192.168.1.12:8989 |
| UN_SONARR_0_API_KEY | (Sonarr key) |
| **UN_SONARR_0_PATHS_0** | **/downloads/sonarr** |
| UN_RADARR_0_URL | http://192.168.1.12:7878 |
| UN_RADARR_0_API_KEY | (Radarr key) |
| **UN_RADARR_0_PATHS_0** | **/downloads/radarr** |

> **The PATHS variables are load-bearing and easy to get wrong.** The *arrs
> report queue paths from their own container view (`/downloads/Release.Name`);
> Unpackerr stats that literal string in *its* container, misses (its
> /downloads is the sync *base*), then falls back to searching every
> `PATHS_0` entry. Two failure modes observed Aug 2026:
> 1. Wrong variable name: `UN_SONARR_0_PATH` (singular) is not a recognized
>    key — Unpackerr silently ignores it.
> 2. Wrong value: paths are absolute in-container paths; `/sonarr` points at
>    a nonexistent root directory.
> With either mistake, every rar'd release logs "no extractable files found …
> stat err: no such file or directory" forever, and no monitoring layer fired
> (see §8.2). Correct values above; validate with a rar'd release end-to-end.

### 6.3 Behavior Notes

- On success, Unpackerr renames the folder to `<name>_unpackerred` after the
  *arr imports — that rename is a **local-only name** Syncthing global state
  has never seen, so seedbox deletion propagation can never remove it.
  These husks are arr-cleanup's responsibility (§7.4).
- `delete orig: false` — rar sets are left in place for the seedbox lifecycle.
- Unpackerr may delete the extracted mkv after import. This is safe in the
  Receive Only tree: the extracted file was a local addition, so
  local-add-then-local-delete nets to zero divergence — no re-fetch, no pin.

---

## 7. Automation Scripts

All three scripts live under
`/boot/config/plugins/user.scripts/scripts/<name>/script` and share one config
file. The User Scripts plugin copies scripts to `/tmp/user.scripts/tmpScripts/`
before execution — after editing, trigger a fresh run for changes to apply.
The plugin cannot pass command-line arguments; runtime switches live in the
conf file.

### 7.1 Shared Config File

`/boot/config/arr-rescans.conf` — persists across reboots, never committed to
git (excluded via .gitignore in the Caladan repo).

```bash
# /boot/config/arr-rescans.conf
SONARR_KEY="your_sonarr_api_key"
RADARR_KEY="your_radarr_api_key"
LIDARR_KEY="your_lidarr_api_key"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"

# Space-separated, no dots — used by arr-rescans loose-file scanning and RAR guard
VIDEO_EXTENSIONS="mkv mp4 avi"

# --- arr-import-monitor (optional overrides) ---
# IMPORT_ALERT_THRESHOLD=30      # minutes before alerting (default 30)
# IMPORT_REALERT_SECONDS=3600    # re-alert interval; raise to 14400 to quiet
                                 # known-benign zombie entries (§8.4)

# --- arr-cleanup ---
# CLEANUP_LIVE=1                 # arm deletions; absent/0 = dry run
# CLEANUP_GRACE_DAYS=2           # min age before residue is eligible
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

### 7.2 arr-rescans v4.5.1

**Schedule:** `*/5 * * * *`
**Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`

Design: import detection via the history API (eventType 3,
`downloadFolderImported`) — no marker files. Single pass per app merges the
suspicious-file check with the scan decision. Guards, in evaluation order per
folder: empty dir → skip; sync-conflict name → skip; already in import
history → skip; suspicious files (.exe/.bat/.com/.scr/.js/.vbs) → alert once
(deduplicated via `/tmp/arr-rescans-suspicious.state`, pruned when the folder
disappears) and skip; rar set present without a settled video file (mtime ≥ 5
min) → defer for Unpackerr. Loose video files at the app root get the
conflict and history guards.

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

### 7.3 arr-import-monitor v1.2

**Schedule:** `*/15 * * * *`
**Path:** `/boot/config/plugins/user.scripts/scripts/arr-import-monitor/script`

Watches the *arr queue APIs for items stuck in `importPending`,
`importBlocked`, or `importFailed` (read from **`trackedDownloadState`** —
the v1.1 bug was matching on `status`, which never carries import states, so
the monitor could never fire; see §8.2). Alerts to Discord after 30 minutes
(configurable), re-alerts hourly (configurable), includes the
`statusMessages` reason. Per-app state pruning (v1.1 wiped other apps'
dedup state on every pass).

```bash
#!/bin/bash

# arr-import-monitor v1.2
# Queries *arr queue APIs for items stuck in import states and sends
# Discord alerts with per-item deduplication.
# Schedule: */15 * * * *
#
# v1.2 changes:
#   - FIX: match on trackedDownloadState (importPending/importBlocked/importFailed)
#     instead of status. The status field carries download-client state
#     (completed/downloading/etc.) and NEVER holds import states — v1.1 could
#     not fire on any stuck import.
#   - Include statusMessages content in the Discord alert (e.g. "Found archive
#     file, might need to be extracted").
#   - FIX: prune_state is now app-scoped. v1.1 pruned ALL state entries not in
#     the current app's active list, so each app's pass wiped the other apps'
#     dedup state, causing re-alert spam.

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
# IMPORT_ALERT_THRESHOLD=30      # minutes before alerting (default 30)
# IMPORT_REALERT_SECONDS=3600    # seconds before re-alerting same item (default 1 hour)
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

# Remove stale state entries belonging to ONE app only.
# Args: $1=app_prefix, remaining args = active keys for that app
# Entries for other apps pass through untouched.
prune_state() {
  local app_prefix="$1"
  shift
  local -a actives=("$@")
  local tmp=$(mktemp)
  while IFS='=' read -r key ts; do
    [ -z "$key" ] && continue
    # Not this app's entry — keep it, don't judge it
    case "$key" in
      "${app_prefix}:"*) ;;
      *) echo "${key}=${ts}" >> "$tmp"; continue ;;
    esac
    local found=0
    for active in "${actives[@]}"; do
      [ "$active" = "$key" ] && found=1 && break
    done
    [ $found -eq 1 ] && echo "${key}=${ts}" >> "$tmp"
  done < "$STATE_FILE"
  mv "$tmp" "$STATE_FILE"
}

# Process queue for a single *arr instance
# Args: $1=app_name $2=base_url $3=api_key $4=api_version (default v3)
check_queue() {
  local api_ver="${4:-v3}"
  local app="$1"
  local url="$2"
  local key="$3"
  local now=$(date +%s)
  local active_keys=()

  # Fetch full queue (pageSize 200 should cover all normal cases)
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
    local id title status tracked_state tracked_status error_msg status_msg

    id=$(echo "$record"             | jq -r '.id')
    title=$(echo "$record"          | jq -r '.title // "Unknown"')
    status=$(echo "$record"         | jq -r '.status // ""')
    tracked_state=$(echo "$record"  | jq -r '.trackedDownloadState // ""')
    tracked_status=$(echo "$record" | jq -r '.trackedDownloadStatus // ""')
    error_msg=$(echo "$record"      | jq -r '.errorMessage // ""')
    status_msg=$(echo "$record"     | jq -r '[.statusMessages[]?.messages[]?] | first // ""')

    # Import states live in trackedDownloadState, NOT status.
    # status holds download-client state (completed/downloading/queued/...)
    case "$tracked_state" in
      importPending|importBlocked|importFailed) ;;
      *) continue ;;
    esac

    local state_key="${app}:${id}"
    active_keys+=("$state_key")

    # Get first-seen time for age calculation
    local first_seen
    first_seen=$(grep "^${state_key}_first=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    if [ -z "$first_seen" ]; then
      echo "${state_key}_first=${now}" >> "$STATE_FILE"
      first_seen=$now
    fi
    active_keys+=("${state_key}_first")

    local age_minutes=$(( (now - first_seen) / 60 ))

    if [ "$age_minutes" -lt "$THRESHOLD" ]; then
      echo "${app}: '${title}' in ${tracked_state} for ${age_minutes}m — below threshold, skipping"
      continue
    fi

    if should_alert "$state_key"; then
      local icon="⚠️"
      local label="pending"
      case "$tracked_state" in
        importBlocked) icon="🚫"; label="blocked" ;;
        importFailed)  icon="❌"; label="failed" ;;
      esac

      local msg="${icon} **${app}**: \`${title}\` import ${label} for ${age_minutes} minutes"
      if [ -n "$status_msg" ] && [ "$status_msg" != "null" ]; then
        msg="${msg} — ${status_msg}"
      elif [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
        msg="${msg} — ${error_msg}"
      fi

      send_notification "$msg"
      record_alert "$state_key"
      echo "${app}: alerted for '${title}' (${tracked_state}, ${age_minutes}m)"
    else
      echo "${app}: '${title}' (${tracked_state}, ${age_minutes}m) — suppressed, recently alerted"
    fi

  done < <(echo "$queue" | jq -c '.records[]')

  # Prune stale entries for THIS app only
  prune_state "$app" "${active_keys[@]}"
}

check_queue "Sonarr" "$SONARR" "$SONARR_KEY"
check_queue "Radarr" "$RADARR" "$RADARR_KEY"
check_queue "Lidarr" "$LIDARR" "$LIDARR_KEY" "v1"

echo "arr-import-monitor complete"
```

### 7.4 arr-cleanup v2.0

**Schedule:** daily
**Path:** `/boot/config/plugins/user.scripts/scripts/arr-cleanup/script`

Removes **local-only residue** from the sync tree: `_unpackerred` husks,
leftover extracted mkvs, stale marker files, empty directories whose contents
already propagated away. Safety discriminator is Syncthing's global index
(`/rest/db/file`): seedbox-tracked paths are always skipped (propagation owns
their lifecycle). Deleting residue *resolves* pending local changes rather
than creating them. **Dry-run by default** — set `CLEANUP_LIVE=1` in the conf
to arm (User Scripts cannot pass CLI arguments). Fails safe: aborts entirely
if the Syncthing API is unreachable; any ambiguous API response is treated as
tracked. Grace period (`CLEANUP_GRACE_DAYS`, default 2) uses newest *file*
mtime inside directories — directory mtimes are unreliable on Unraid user
shares.

> v1.x history: the previous cleanup gated every deletion on `.imported`
> marker files, which arr-rescans stopped creating at v4.4 — it had become a
> permanent no-op while residue accumulated for a month.

```bash
#!/bin/bash

# arr-cleanup v2.0
# Removes LOCAL-ONLY residue from the Receive Only sync tree:
#   - _unpackerred renamed folders (local rename; global state never knew the name)
#   - extracted mkvs / stale .imported/.first_seen markers left behind
#   - empty husk directories whose tracked contents already propagated away
#
# NEVER deletes seedbox-tracked content. The discriminator is Syncthing's
# global index (/rest/db/file): if the seedbox still announces a path, we skip
# it and let the 14-day seedbox removal + deletion propagation handle it.
# Deleting tracked files would create pinned local deletes; deleting residue
# instead RESOLVES pending local changes and drains receiveOnlyChanged counters.
#
# DRY-RUN BY DEFAULT. Set CLEANUP_LIVE=1 in arr-rescans.conf to arm deletions
# (User Scripts plugin cannot pass command-line arguments).
# Suggested schedule: daily.
#
# v2.0 changes vs v1.x:
#   - v1.x gated every deletion on .imported marker files, which arr-rescans
#     v4.4 no longer creates — the script had become a permanent no-op.
#   - Deletion safety now determined by Syncthing global state, not markers.
#   - Dry-run default with conf-armed live mode added.
# Config additions (optional, in arr-rescans.conf):
#   CLEANUP_LIVE=1         # arm deletions; absent or 0 = dry run (default 0)
#   CLEANUP_GRACE_DAYS=2   # min age before residue is eligible (default 2)

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

LIVE="${CLEANUP_LIVE:-0}"
GRACE_DAYS="${CLEANUP_GRACE_DAYS:-2}"
SYNC_BASE="/mnt/user/media/download/sync"
ST_FOLDER="sfqzb-cvm5v"
ST_URL="http://localhost:8384"

STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
if [ -z "$STKEY" ]; then
  echo "FATAL: could not read Syncthing API key — aborting (no deletions attempted)"
  exit 1
fi

# Sanity: Syncthing must be answering before we trust "untracked" verdicts
if ! curl -s -f -H "X-API-Key: $STKEY" "$ST_URL/rest/system/ping" > /dev/null 2>&1; then
  echo "FATAL: Syncthing API not responding — aborting (no deletions attempted)"
  exit 1
fi

DELETED=0
SKIPPED_TRACKED=0
SKIPPED_YOUNG=0
ERRORS=0
now=$(date +%s)

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

# Query Syncthing global index for a relative path.
# Echoes: tracked | residue
#   tracked = seedbox still announces this path (skip it)
#   residue = globally deleted, or global index has never heard of it (safe)
# On any ambiguity, echoes tracked (fail safe).
global_state() {
  local rel="$1"
  local code body
  body=$(curl -s -w '\n%{http_code}' -G -H "X-API-Key: $STKEY" \
    --data-urlencode "folder=$ST_FOLDER" \
    --data-urlencode "file=$rel" \
    "$ST_URL/rest/db/file")
  code=$(echo "$body" | tail -1)
  body=$(echo "$body" | sed '$d')

  if [ "$code" = "404" ]; then
    echo "residue"   # global index has no such object
    return
  fi
  if [ "$code" != "200" ]; then
    echo "tracked"   # unexpected response — fail safe, skip
    return
  fi
  local gdeleted
  gdeleted=$(echo "$body" | jq -r '.global.deleted // empty' 2>/dev/null)
  if [ "$gdeleted" = "true" ]; then
    echo "residue"   # seedbox tracked it once, has since deleted it
  else
    echo "tracked"
  fi
}

# Newest mtime inside a directory (falls back to dir mtime if empty).
# Directory mtimes alone are unreliable on Unraid user shares.
newest_mtime() {
  local path="$1"
  local newest
  if [ -d "$path" ]; then
    newest=$(find "$path" -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
    [ -z "$newest" ] && newest=$(stat -c %Y "$path" 2>/dev/null)
  else
    newest=$(stat -c %Y "$path" 2>/dev/null)
  fi
  echo "${newest:-$now}"
}

do_delete() {
  local path="$1"
  local label="$2"
  if [ "$LIVE" -eq 1 ]; then
    if rm -rf "$path"; then
      echo "DELETED: $label"
      DELETED=$((DELETED + 1))
    else
      echo "ERROR deleting: $label"
      ERRORS=$((ERRORS + 1))
    fi
  else
    echo "WOULD DELETE: $label"
    DELETED=$((DELETED + 1))
  fi
}

cleanup_dir() {
  local app="$1"
  local dir="$SYNC_BASE/$app"
  [ -d "$dir" ] || return

  # All depth-1 entries: subfolders AND loose files (mkvs, stale markers, nfo strays)
  local entry name rel
  for entry in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$entry" ] || continue
    name=$(basename "$entry")
    rel="$app/$name"

    # Age gate — avoid racing content that is mid-sync / just arrived
    local mtime age_days
    mtime=$(newest_mtime "$entry")
    age_days=$(( (now - mtime) / 86400 ))
    if [ "$age_days" -lt "$GRACE_DAYS" ]; then
      echo "skip (age ${age_days}d < ${GRACE_DAYS}d): $rel"
      SKIPPED_YOUNG=$((SKIPPED_YOUNG + 1))
      continue
    fi

    # Seedbox-tracked? Then propagation owns its lifecycle — hands off.
    local state
    state=$(global_state "$rel")
    if [ "$state" = "tracked" ]; then
      echo "skip (seedbox-tracked): $rel"
      SKIPPED_TRACKED=$((SKIPPED_TRACKED + 1))
      continue
    fi

    do_delete "$entry" "$rel (${age_days}d, $state)"
  done
}

MODE="DRY RUN"
[ "$LIVE" -eq 1 ] && MODE="LIVE"
echo "arr-cleanup v2.0 — $MODE — grace ${GRACE_DAYS}d"
echo "---"

cleanup_dir "sonarr"
cleanup_dir "radarr"
cleanup_dir "lidarr"

echo "---"
echo "Summary ($MODE): $DELETED residue item(s), $SKIPPED_TRACKED seedbox-tracked skipped, $SKIPPED_YOUNG too-young skipped, $ERRORS errors"

# Notify only on live runs that did something
if [ "$LIVE" -eq 1 ] && { [ "$DELETED" -gt 0 ] || [ "$ERRORS" -gt 0 ]; }; then
  msg="🧹 **Sync cleanup**: removed $DELETED local residue item(s) (seedbox-tracked content untouched: $SKIPPED_TRACKED)"
  [ "$ERRORS" -gt 0 ] && msg="$msg — ⚠️ $ERRORS deletion error(s), check logs"
  send_notification "$msg"
fi
```

---

## 8. Known Issues & Workarounds

### 8.1 Zombie Queue Entries (Superseded Grabs)

When two releases of the same episode are grabbed and one imports, the loser's
queue entry lingers in `importPending` ("Not a quality revision upgrade for
existing episode file(s)") — and is **re-created by RefreshMonitoredDownloads
even after deletion**, as long as the torrent remains in qBittorrent's
category. These entries self-resolve when the seedbox's 14-day removal drops
the torrent. arr-import-monitor will alert on them (correctly — they *are*
stuck); expect re-alerts at the `IMPORT_REALERT_SECONDS` cadence until
age-out. If the noise grates, raise the re-alert interval (e.g. 14400) rather
than deleting queue entries that will just respawn.

Manual clear of a genuinely stale entry (won't stick if the torrent remains):

```bash
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

Bulk pattern: `/api/v3/queue/bulk` DELETE with
`removeFromClient=false&blocklist=false`.

### 8.2 Aug 2026 Incident — Layered Silent Failures (case study)

A rar'd episode sat unimported overnight with no alert. Root causes, layered:
1. **Unpackerr misconfigured** (`UN_SONARR_0_PATH` — wrong name, wrong value;
   see §6.2): every rar'd release since at least Aug 2 silently never
   extracted.
2. **arr-import-monitor v1.1 watched the wrong field** (`status` instead of
   `trackedDownloadState`): structurally incapable of alerting on any stuck
   import, ever.
3. No layer watches items whose queue entries expire (§8.3).

Outcome: zero media lost — competing grabs covered every gap — but only by
luck. Fixes: Unpackerr PATHS corrected, monitor v1.2, cleanup v2.0. Lesson:
verify each monitoring layer can actually fire (inject a test condition);
a monitor that has never alerted may be broken, not lucky.

### 8.3 Orphaned Downloads (Expired Queue Entries)

Everything downstream of the queue — Unpackerr, arr-import-monitor — is blind
to an item whose queue entry has aged out or was removed (including the
"removing a series strands its downloads" case). arr-rescans' history check
partially covers this for scannable folders, but a rar-only folder with no
queue entry has no automated path to import. Recovery: extract manually, then
directed scan:

```bash
cd /mnt/user/media/download/sync/sonarr/FOLDER/
unrar x NAME.rar
curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"DownloadedEpisodesScan","path":"/downloads/FOLDER"}' \
  "http://192.168.1.12:8989/api/v3/command"
```

**Always check `hasFile` first** (§9.2) — most "stuck" folders belong to
superseded releases whose episodes already imported from elsewhere, and need
no recovery at all.

### 8.4 Monitor Alert Noise During Torrent Lifetime

A superseded release alerts as import-pending until its torrent ages out (up
to 14 days). This is by design — the monitor cannot distinguish "benign
zombie" from "genuinely stuck" without the library check a human does in
seconds. Tune with `IMPORT_REALERT_SECONDS`.

### 8.5 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 8.6 Historical: Sync-Conflict False Imports (Apr–Jul 2026)

A retired cleanup script deleted seedbox-tracked files locally under
conditions that produced `sync-conflict` copies, which arr-rescans then fed
to the *arrs as real releases; 361 GiB of conflict debris accumulated before
the `.stignore` fix. Defenses now: `(?d)*.sync-conflict-*` ignore rule +
belt-and-braces skips in arr-rescans (both loose files and folders). Note the
distinction from §2: ordinary import-driven local deletes do NOT cause
re-downloads or conflicts; the historical incident involved a different
mechanism. If conflict files ever reappear, something new is wrong — investigate,
don't just clean.

### 8.7 Anime / Foreign Title Mismatches

Releases under alternate names ("Sousou no Frieren" vs "Frieren: Beyond
Journey's End"; "La Oficina" vs "The Office (MX)"): Sonarr handles most via
TVDB alias matching; the jq `--arg` payload builder handles brackets/spaces/
apostrophes in folder names. For unresolved cases, submit the alias to TVDB
and refresh the series after approval.

### 8.8 Season Pack Imports

Require Interactive Import: Wanted → Manual Import → folder → Interactive
Import.

### 8.9 Fake/Malicious Torrents

arr-rescans detects executable files, alerts once (deduplicated), and skips
the scan. Blocklist the release in the *arr to trigger a replacement search.

### 8.10 Syncthing "Stopped" After Boot

A transient permission denial during the boot window can put the folder in a
"Stopped" error state that does not self-recover — restart the
binhex-syncthing container.

---

## 9. Maintenance & Triage

### 9.1 Stuck-Import Triage Flow

1. **Get the queue record** (the monitor alert gives the title):
   ```bash
   curl -s -H "X-Api-Key: $SONARR_KEY" "http://192.168.1.12:8989/api/v3/queue?pageSize=200" \
     | jq '.records[] | select(.title | test("SEARCH"; "i"))
           | {id, status, trackedDownloadState, trackedDownloadStatus, statusMessages}'
   ```
2. **"Found archive file"** → Unpackerr's job. Check:
   ```bash
   docker logs unpackerr --since 2h 2>&1 | grep -iE "SEARCH|error"
   ```
   "no extractable files found … stat err" = path config regression (§6.2).
3. **"Not a quality revision upgrade"** → benign zombie (§8.1). Verify with
   the hasFile check below; if the episode has a file, no action — it ages out.
4. **No queue record at all** → orphan (§8.3) or already resolved. hasFile
   check decides.

### 9.2 hasFile Check (always before manual recovery)

```bash
# Find series ID
curl -s -H "X-Api-Key: $SONARR_KEY" "http://192.168.1.12:8989/api/v3/series" \
  | jq '.[] | select(.title | test("NAME"; "i")) | {id, title}'
# Episode file state
curl -s -H "X-Api-Key: $SONARR_KEY" "http://192.168.1.12:8989/api/v3/episode?seriesId=ID" \
  | jq '.[] | select(.seasonNumber==S and .episodeNumber==E) | {episodeNumber, hasFile}'
```

Radarr equivalent: `/api/v3/movie` → `.hasFile`.

### 9.3 Import Logs

```bash
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30
docker logs unpackerr --since 1h 2>&1 | grep -iE "extract|error" | tail -30
```

### 9.4 Seedbox Torrent Ages (cleanup-rule verification)

```bash
read -s QBPASS   # run ALONE, then type password
curl -s -c /tmp/qb.cookie --data-urlencode "username=scytale1953" --data-urlencode "password=$QBPASS" \
  "https://ibiza.seedhost.eu/scytale1953/qbittorrent/api/v2/auth/login"   # expect: Ok.
curl -s -b /tmp/qb.cookie "https://ibiza.seedhost.eu/scytale1953/qbittorrent/api/v2/torrents/info" \
  | jq -r '.[] | [(.seeding_time/86400*10|floor/10), .state, .max_seeding_time, .category, .name] | @tsv' \
  | sort -rn | head -25
```

Healthy: nothing above 14.0 days; `max_seeding_time` = 20160 everywhere.
Watch for `missingFiles`/`error` states — those torrents never age out on
their own.

### 9.5 Sync Status & Pins

See §4.4. Healthy: `needFiles: 0`, pins younger than the oldest live torrent.

### 9.6 Forcing a Manual Rescan

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

### 9.7 Sync Tree Cleanup

Do NOT hand-delete. Run arr-cleanup: dry-run output first (default), review
WOULD DELETE lines against the qBittorrent listing (§9.4 — tracked skips
should correlate with live torrents), then set `CLEANUP_LIVE=1` and re-run.

### 9.8 Updating Credentials

```bash
nano /boot/config/arr-rescans.conf
```

---

## 10. Rebuild Checklist

### 10.1 Unraid Containers

- [ ] binhex-syncthing, host networking, port 8384
- [ ] Sonarr (8989), Radarr (7878), Lidarr (8686), volume mounts per §5.1
- [ ] **Manually add /downloads mapping to Lidarr**
- [ ] Unpackerr with `/mnt/user/media/download/sync → /downloads` and env vars per §6.2 — **PATHS_0 plural, absolute container paths**

### 10.2 Syncthing

- [ ] Folder `sfqzb-cvm5v`, type **Receive Only**, path `/media/sync`
- [ ] Seedbox as remote device
- [ ] `.stignore` per §4.3 — **exclusions first, includes second, `*` last**

### 10.3 *arr Apps

- [ ] qBittorrent download client per §5.2
- [ ] Remote path mappings per §5.3 — **app-specific paths, host ibiza.seedhost.eu**
- [ ] Quality profiles; /downloads mounts verified in all three apps
- [ ] Discord notifications connected

### 10.4 Seedbox

- [ ] qBittorrent save path `/home18/scytale1953/Media-sync/`
- [ ] Seeding limits: 20160 min → Remove torrent and files
- [ ] Categories with per-app save paths per §3.2
- [ ] Syncthing cron present; device connected to Caladan

### 10.5 User Scripts

- [ ] Install User Scripts plugin
- [ ] Create `/boot/config/arr-rescans.conf` per §7.1 (including VIDEO_EXTENSIONS); `chmod 600`
- [ ] arr-rescans v4.5.1, schedule `*/5 * * * *`
- [ ] arr-import-monitor v1.2, schedule `*/15 * * * *`
- [ ] arr-cleanup v2.0, schedule daily, leave `CLEANUP_LIVE` unset until first dry-run reviewed
- [ ] Test each manually; verify a Discord alert path end-to-end

### 10.6 Validation (do not skip)

- [ ] Grab a rar'd release; watch Unpackerr extract and the *arr import
- [ ] Confirm arr-import-monitor console output shows per-app queue counts
- [ ] Temporarily set `IMPORT_ALERT_THRESHOLD=0`, confirm a Discord alert
      arrives, restore
- [ ] arr-cleanup dry-run output sane against qBittorrent torrent list

---

*Caladan Media Automation Guide — stored in git at /MyFiles/Systems/Caladan*
*Never commit arr-rescans.conf — it contains credentials*
*Companion: caladan_automation_guide.html (same content + diagrams)*
