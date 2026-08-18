# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** 18 August 2026
**Server:** Caladan (192.168.1.12) — Unraid 7.2.4

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Content Lifecycle](#2-content-lifecycle)
3. [Seedbox Configuration](#3-seedbox-configuration-seedhosteu)
4. [Syncthing Configuration](#4-syncthing-configuration)
5. [*arr Application Configuration](#5-arr-application-configuration)
6. [Unpackerr](#6-unpackerr)
7. [Automation Scripts](#7-automation-scripts)
8. [Known Issues & Workarounds](#8-known-issues--workarounds)
9. [Maintenance Procedures](#9-maintenance-procedures)
10. [Rebuild Checklist](#10-rebuild-checklist)

---

## 1. Infrastructure Overview

### Architecture

```
qBittorrent (seedbox) ──▶ Syncthing (Send Only ▶ Receive Only) ──▶ /mnt/user/media/download/sync/
                                                                          │
                                                                          ▼
                                                              Unpackerr (rar extraction)
                                                                          │
                                    ┌─────────────────────────────────────┤
                                    ▼                                     ▼
                        Lane 1: arr-rescans                  Lane 2: *arr queue
                        (DownloadedScan per folder)          (RefreshMonitoredDownloads
                                    │                         via remote path mappings)
                                    └──────────────┬──────────────────────┘
                                                   ▼
                                    Sonarr / Radarr / Lidarr (move-import)
                                                   │
                                                   ▼
                                        Plex / Jellyfin (+ Tdarr transcode)
```

Two import lanes run in parallel. Lane 1 (arr-rescans) fires targeted `DownloadedEpisodesScan`/`DownloadedMoviesScan` commands per folder every 5 minutes. Lane 2 is the *arrs' native completed-download handling, which depends on the remote path mappings (§5.3) being correct. Whichever lane imports first wins; the history API check in arr-rescans and Sonarr/Radarr's own dedup make the race harmless.

### Key Infrastructure

| Component | Value |
|-----------|-------|
| Caladan IP | 192.168.1.12 |
| Caladan OS | Unraid 7.2.4 |
| Seedbox Host | ibiza.seedhost.eu |
| Seedbox User | scytale1953 |
| Seedbox Base Path | /home18/scytale1953/ |
| Media Sync Path (Seedbox) | ~/Media-sync/ |
| Media Sync Path (Caladan) | /mnt/user/media/download/sync/ |
| Syncthing Folder ID | sfqzb-cvm5v |
| Caladan Syncthing Port | 8384 |
| Sonarr / Radarr / Lidarr Ports | 8989 / 7878 / 8686 |
| Shared script config | /boot/config/arr-rescans.conf |
| Git repo | /MyFiles/Systems/Caladan (arr-rescans.conf gitignored) |

---

## 2. Content Lifecycle

Understanding the full lifecycle prevents most classes of "why is this still here" confusion:

1. **Grab** — *arr sends the release to qBittorrent with a category (sonarr/radarr/lidarr).
2. **Download** — qBittorrent writes into `~/Media-sync/<category>/` on the seedbox.
3. **Sync** — Syncthing (seedbox Send Only → Caladan Receive Only) mirrors the release into `/mnt/user/media/download/sync/<app>/`.
4. **Extraction** — if the release is a rar set, Unpackerr (§6) detects it via the *arr queue and extracts in place. The rar set remains alongside the extracted video.
5. **Import** — arr-rescans or the queue lane triggers the *arr, which **moves** the video into the library. The move deletes the source file locally.
6. **Pinned local delete** — in a Receive Only folder, that local deletion becomes a pinned "locally changed" entry. Syncthing does **not** re-fetch move-imported files (delete of a tracked file pins; it does not resurrect).
7. **Seedbox removal** — qBittorrent removes torrent + files after 14 days seeding.
8. **Propagation** — the seedbox deletion propagates to Caladan; remaining files (rars, sfv) disappear and the pin resolves naturally.
9. **Residue** — anything local-only (extracted files the *arr didn't take, `_unpackerred` husks, legacy markers) is invisible to the global index and never propagates away. arr-cleanup (§7.4) removes it safely.

**Counters are flow, not stock.** `receiveOnlyChangedFiles`/`receiveOnlyChangedDeletes` measure churn through the pinned-change state, not a backlog. Health looks like oscillation around a baseline with nothing pinned older than ~14 days — not zero.

**Never delete tracked content locally.** Deleting a still-seeding file from the Receive Only tree makes Syncthing re-fetch it and mint `sync-conflict-*` copies — the Apr–Jul 2026 false-import incident. Local deletion of *tracked* content is always wrong; rely on seedbox removal to propagate. (This is why sync-cleanup was retired and replaced by the global-state-aware arr-cleanup.)

---

## 3. Seedbox Configuration (seedhost.eu)

### 3.1 qBittorrent

qBittorrent is the active download client: `https://ibiza.seedhost.eu/scytale1953/qbittorrent/`

**Tools → Options → Downloads:**
- Default Save Path: `/home18/scytale1953/Media-sync/`

**Tools → Options → BitTorrent (Seeding Limits):**
- When ratio reaches: disabled (0)
- When seeding time reaches: 20160 minutes (14 days)
- Then: **Remove torrent and files**

> The 14-day removal is the deletion engine for the whole pipeline (§2 step 7). No manual cleanup or cron is needed for synced content.

### 3.2 qBittorrent Download Categories

| Category | Save Path |
|----------|-----------|
| sonarr | /home18/scytale1953/Media-sync/sonarr/ |
| radarr | /home18/scytale1953/Media-sync/radarr/ |
| lidarr | /home18/scytale1953/Media-sync/lidarr/ |

> **Save paths must be set explicitly in the qBittorrent WebUI** (Categories sidebar → edit each category). Categories left with an implicit/blank save path cause the *arrs to log download-client path warnings and can surface as Docker health-check noise. Fixed August 2026 — verify all three categories show the explicit path.

### 3.3 Seedbox Cron

Only one cron entry — the Syncthing watchdog:

```cron
MAILTO=""
*/5 * * * * /bin/bash ~/software/cron/syncthing
```

### 3.4 ruTorrent (Legacy)

ruTorrent is installed but unused. If ever switching back: ratio plugin `MAX_RATIO=9999`; conf at `~/www/scytale1953.ibiza.seedhost.eu/scytale1953/rutorrent/plugins/ratio/conf.php`; ratio group 1: Min% 0, Max% 0, UL 0, Time 336h, Action: Remove.

### 3.5 Media-sync Folder Structure

| Directory | Purpose |
|-----------|---------|
| sonarr/ | TV — synced |
| radarr/ | Movies — synced |
| lidarr/ | Music — synced |
| freeleech/ | NOT synced (ignored) |
| prowlarr/ | NOT synced (ignored) |
| radarr-4k/ | NOT synced (ignored) |
| foo/ | NOT synced (ignored) |

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
| Folder Name | Media sync |
| Caladan Path | /mnt/user/media/download/sync/ (host) = /media/sync (container) |
| Seedbox Path | ~/Media-sync/ |
| Folder Type (Caladan) | **Receive Only** |
| Folder Type (Seedbox) | Send Only |
| Rescan Interval | **0 (disabled)** |

> Rescan interval is deliberately 0. Periodic full rescans re-flag move-imported deletions as fresh local changes and churn the pinned-change state for no benefit. Change detection still works via fs watching and remote index updates.

### 4.3 Ignore Patterns

**Ordering is load-bearing: first match wins.** All exclusions (with `(?d)` so Syncthing may delete them when removing a parent) come first, then the `!` includes, then the catch-all `*`. Any exclusion placed below an include is dead code — this exact mistake made `(?d)*.sync-conflict-*` inert for months.

File: `/mnt/user/media/download/sync/.stignore` (deployed, verbatim):

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
// Legacy cleanup — v4.4 creates no new markers; these clear pre-v4.4 leftovers
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

Notes:
- Image rules exist in **both** root-level (`/sonarr/*.jpg`) and recursive (`/sonarr/**/*.jpg`) forms — the recursive form alone does not match files at the tree root.
- Only `.jpg`/`.jpeg` are excluded, and only in the video trees, to preserve Lidarr album art.
- Comments use `//`.

### 4.4 Checking Sync Status via CLI

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

Bash alias for `~/.bashrc`:

```bash
alias syncstatus='STKEY=$(grep -o "<apikey>[^<]*" /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d">" -f2) && curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"'
```

Inspect pinned local changes (deletes awaiting seedbox propagation):

```bash
curl -s "http://localhost:8384/rest/db/localchanged?folder=sfqzb-cvm5v&perpage=1000" -H "X-API-Key: $STKEY" | \
  jq -r '.files[] | select(.deleted) | .name' | head -30
```

### 4.5 Revert Local Changes — EMERGENCY ONLY

**Revert Local Changes is not routine maintenance.** It re-downloads every move-imported file whose deletion is currently pinned — potentially hundreds of GB — and those re-fetched copies then need importing/cleaning again. Pinned deletes are the *normal* steady state of this pipeline and resolve themselves when the seedbox removes torrents (§2).

Use Revert only when the folder is genuinely wedged and the index-reset procedure (§9.6) is not applicable.

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

> **Note:** Lidarr does not include a /downloads mapping by default — add it manually.

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

| App | Host | Remote Path (Seedbox) | Local Path (Container) |
|-----|------|-----------------------|------------------------|
| Sonarr | ibiza.seedhost.eu | /home18/scytale1953/Media-sync/sonarr/ | /downloads/ |
| Radarr | ibiza.seedhost.eu | /home18/scytale1953/Media-sync/radarr/ | /downloads/ |
| Lidarr | ibiza.seedhost.eu | /home18/scytale1953/Media-sync/lidarr/ | /downloads/ |

Both paths end with a trailing slash.

**Why app-specific:** qBittorrent reports save paths like `/home18/scytale1953/Media-sync/sonarr/Release`. The old base-path mapping (`/Media-sync` → `/downloads/`) translated this to `/downloads/sonarr/Release` — a path that does not exist inside the *arr container (§5.1 mounts the app subfolder *as* `/downloads`). Every queue-lane import failed silently for months, masked by Lane 1 importing first. The app-specific mapping translates to `/downloads/Release`, which is correct.

**Downstream consequence:** the *arrs now report `outputPath` as `/downloads/<Release>` with no app segment. Unpackerr must be configured to compensate (§6).

### 5.4 API Keys & Shared Config

Stored in `/boot/config/arr-rescans.conf` (§7.1). Shared by all three scripts.

### 5.5 Quality Profile (HD-1080p)

- Upgrades Allowed: Yes
- Upgrade Until: Bluray-1080p
- Quality order: Remux-1080p, Bluray-1080p, WEB 1080p, HDTV-1080p

---

## 6. Unpackerr

Unpackerr extracts rar'd releases in place. It does **not** watch the filesystem for this pipeline — it polls the Sonarr/Radarr queues, takes each queued item's reported `outputPath`, and looks for that path inside its own container. If the literal path doesn't exist, it falls back to trying the item's base folder name under each configured `paths` entry.

### 6.1 Container Configuration

| Setting | Value |
|---------|-------|
| Mount | /mnt/user/media/download/sync → /downloads |
| delete_orig | false (rars persist until seedbox removal — expected) |
| delete_delay | 5m |
| protos | torrent |

### 6.2 Environment Variables (exact deployed names)

| Variable | Value |
|----------|-------|
| UN_SONARR_0_URL | http://192.168.1.12:8989 |
| UN_SONARR_0_API_KEY | (from arr-rescans.conf SONARR_KEY) |
| **UN_SONARR_0_PATHS_0** | **/downloads/sonarr** |
| UN_RADARR_0_URL | http://192.168.1.12:7878 |
| UN_RADARR_0_API_KEY | (from arr-rescans.conf RADARR_KEY) |
| **UN_RADARR_0_PATHS_0** | **/downloads/radarr** |

> **The `_0` suffix on PATHS is mandatory.** `paths` is a list field; Unpackerr's env parser only reads indexed names (`..._PATHS_0`, `..._PATHS_1`, …). An unindexed `UN_SONARR_0_PATHS` is **silently ignored** — no error, no warning — and the instance falls back to the default `/downloads`, which no longer matches anything under the app-specific mappings (§5.3). See Known Issue §8.1.

### 6.3 Path Resolution (three views of one release)

For `Release.X` grabbed by Sonarr:

| Lens | Path |
|------|------|
| qBittorrent (seedbox) | /home18/scytale1953/Media-sync/sonarr/Release.X |
| Sonarr container (`outputPath` after mapping) | /downloads/Release.X |
| Unpackerr container (via PATHS_0 fallback) | /downloads/sonarr/Release.X |

Unpackerr takes the base name from Sonarr's `outputPath` and finds it under `/downloads/sonarr` — its own view of the same folder.

### 6.4 Verification

**Trust the startup config dump, not the Docker template.** After any change:

```bash
docker logs unpackerr 2>&1 | head -60 | grep -iE "sonarr|radarr"
```

The proof of a correctly parsed config is `paths:["/downloads/sonarr"]` (and radarr equivalent) in the per-instance config lines. If it shows the default or an empty list, the env var names are wrong.

Healthy extraction sequence in the logs: `Extraction Queued` → `Extraction Started` → `Extracting ... (n%)` → completion, followed by arr-rescans' RAR guard releasing on its next pass.

---

## 7. Automation Scripts

All three scripts live under `/boot/config/plugins/user.scripts/scripts/<name>/script` and share one config file. The User Scripts plugin copies scripts to `/tmp/user.scripts/tmpScripts/` before execution — after editing, trigger a fresh run for changes to apply. The plugin cannot pass command-line arguments; runtime switches live in the conf file.

| Script | Version | Schedule | Role |
|--------|---------|----------|------|
| arr-rescans | v4.5.1 | `*/5 * * * *` | Trigger imports |
| arr-import-monitor | v1.2 | `*/15 * * * *` | Alert on stuck queue items |
| arr-cleanup | v2.0 | daily | Remove local-only residue |

### 7.1 Shared Config File

`/boot/config/arr-rescans.conf` — persists across reboots, **never committed to git** (in .gitignore).

```bash
# /boot/config/arr-rescans.conf
SONARR_KEY="your_sonarr_api_key"
RADARR_KEY="your_radarr_api_key"
LIDARR_KEY="your_lidarr_api_key"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"

# Space-separated, no dots — used by arr-rescans loose-file scanning and RAR guard
VIDEO_EXTENSIONS="mkv mp4 avi m4v"

# --- arr-import-monitor (optional overrides) ---
# IMPORT_ALERT_THRESHOLD=30      # minutes before alerting (default 30)
# IMPORT_REALERT_SECONDS=3600    # re-alert interval (seconds)

# --- arr-cleanup ---
# CLEANUP_LIVE=1                 # arm deletions; absent/0 = dry run
# CLEANUP_GRACE_DAYS=2           # min age before residue is eligible
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

If any script produces empty API output, the first check is always the conf: `echo "${SONARR_KEY:0:4}"` — empty output means a missing/unsourced key, not a genuinely empty API result.

### 7.2 arr-rescans v4.5.1

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
**Schedule:** `*/5 * * * *`

**Design:**
- **Import detection via history API** — each run fetches Sonarr/Radarr import history (`eventType=3`, `downloadFolderImported`) once per app and skips anything already imported. No marker files. `pageSize=1000` can miss records if `totalRecords` exceeds 1000 (§8.4).
- **Single-pass loop per app** — imported-check, sync-conflict guard, suspicious-file check, RAR guard, and the scan itself run in one loop, so a skip is a real skip.
- **Guards, in evaluation order per subfolder:** empty dir → skip · `sync-conflict` name → skip · in import history → skip · suspicious files (.exe/.bat/.com/.scr/.js/.vbs) → alert once (deduplicated via `/tmp/arr-rescans-suspicious.state`, pruned when the folder disappears) and skip · rar set present without a settled video (mtime ≥ 5 min) → defer for Unpackerr.
- **RAR guard tests extraction *completion*, not rar presence** — the rar set persists on disk until seedbox removal, so presence-only (v4.4) deferred every rar'd release forever. "Settled" = video mtime at least 5 minutes old, protecting a file Unpackerr is still writing.
- **Loose video files** at the app root get the conflict and history guards, iterating `$VIDEO_EXTENSIONS`.
- **Lidarr** uses `/api/v1/` for its refresh call.
- The final log line prints the running version. If deployed and documented versions disagree, trust the log line.

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

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-import-monitor/script`
**Schedule:** `*/15 * * * *`

**Design:**
- Queries all three *arr queues (Lidarr via `/api/v1/`) for items whose **`trackedDownloadState`** is `importPending`, `importBlocked`, or `importFailed`. The `status` field carries download-client state and never holds import states — matching on it (v1.1) meant the monitor could never fire.
- Per-item first-seen tracking; alerts only after `IMPORT_ALERT_THRESHOLD` minutes (default 30), re-alerts after `IMPORT_REALERT_SECONDS` (default 3600 — raise to 14400 to quiet known-benign zombies).
- Alert includes the item's `statusMessages` content (e.g. "Found archive file, might need to be extracted") — this is what surfaces an Unpackerr failure (§8.1) directly in Discord.
- State pruning is **app-scoped** — v1.1's global prune wiped other apps' dedup state on every pass, causing re-alert spam.
- Only watches the queue: a series removed from Sonarr strands its downloads invisibly (§8.5).

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

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-cleanup/script`
**Schedule:** daily. **Dry-run by default** — set `CLEANUP_LIVE=1` in the conf to arm.

**Design:**
- Removes **local-only residue** from the Receive Only tree: `_unpackerred` renamed folders, extracted videos the *arrs didn't take, stale legacy markers, empty husks.
- **Never deletes seedbox-tracked content.** The discriminator is Syncthing's global index (`/rest/db/file`): if the seedbox still announces a path (`200` and not globally deleted), the item is skipped and the 14-day removal owns its lifecycle. `404` or `global.deleted: true` = residue, safe to remove. Any ambiguity fails safe (skip).
- Deleting residue *resolves* pending local changes and drains the receiveOnlyChanged counters — the opposite of deleting tracked content, which pins.
- Age gate (`CLEANUP_GRACE_DAYS`, default 2) uses newest file mtime inside a directory, not directory mtime (unreliable on Unraid user shares).
- Aborts outright (no deletions) if the Syncthing API key can't be read or the API doesn't answer ping — an "untracked" verdict is only trustworthy when Syncthing is up.
- Discord notification only on live runs that deleted something or errored. Dry runs are console-only.

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

### 8.1 Unpackerr Silently Ignores Unindexed List Env Vars ⚠ (Aug 2026 incident)

`paths` is a list field in Unpackerr's config; its env parser only reads **indexed** variable names. `UN_SONARR_0_PATHS=/downloads/sonarr` parses as nothing — no error, no warning — and the instance silently falls back to the default `/downloads`. Under the app-specific remote path mappings (§5.3), the *arrs report `outputPath` without the app segment, so the default path matches nothing.

**Symptom:** every rar'd release loops forever in the Unpackerr log as `(Waiting, pre-Queue, elapsed: …) no progress yet`, with periodic `no extractable files found at: /downloads/<Release> (stat err: … no such file or directory)`. Meanwhile arr-rescans' RAR guard (correctly) defers the folder, and arr-import-monitor alerts `importPending — Found archive file, might need to be extracted`.

**Fix:** `UN_SONARR_0_PATHS_0` / `UN_RADARR_0_PATHS_0` (§6.2).
**Verify:** the startup config dump must show `paths:["/downloads/sonarr"]` — the Docker template proves nothing (§6.4).

### 8.2 Ghost / Stale Queue Entries

Imports via the DownloadedScan lane can leave stale "completed" queue entries. Recurring maintenance item — clear via bulk delete (§9.4) with `removeFromClient=false&blocklist=false`.

### 8.3 Lidarr API Version

Lidarr requires `/api/v1/`, not `/api/v3/`. A `/api/v3/` call returns empty — which looks identical to a missing API key. Both scripts handle this (arr-rescans posts the Lidarr refresh to v1; the monitor passes `"v1"` to `check_queue`).

### 8.4 History Fetch Page Size

`pageSize=1000` history fetches miss records when `totalRecords` exceeds 1000 — check `totalRecords` in the response when history-based logic misbehaves. (A missed record makes arr-rescans re-scan an already-imported release; harmless but noisy.)

### 8.5 Removing a Series Strands Its Downloads

arr-import-monitor only watches the queue. Removing a series from Sonarr removes its queue items, so in-flight downloads for it are stranded permanently and invisibly. Check the sync folder manually after removing any series with pending downloads.

### 8.6 Local Deletion of Tracked Content Creates Conflicts

Deleting a still-seeding file from the Receive Only tree cannot work — Syncthing re-fetches and mints `sync-conflict-*` copies, which (pre-v4.5) were imported as real releases. This killed the old sync-cleanup script. Defense in depth now: `.stignore` conflict exclusion + sync-conflict guards in both arr-rescans scanners + arr-cleanup's global-state discriminator.

### 8.7 Empty API Output = Missing Conf Key

Empty output from an *arr API call in a script almost always means the conf wasn't sourced or a key is blank — check `echo "${SONARR_KEY:0:4}"` before debugging anything else.

### 8.8 Directory mtime Is Unreliable

On Unraid user shares, directory mtime is not a proxy for content age. Use newest file mtime (as arr-cleanup does) for any age-based decision.

### 8.9 Stuck "Locally Changed Items" Deadlock

If pinned items refuse to drain and the state looks wedged, force a clean re-index: stop the Syncthing container, delete the index DB, start — Syncthing rebuilds the index with ignore patterns applied from scratch (§9.6). Prefer this over Revert Local Changes (§4.5).

### 8.10 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 8.11 Anime / Foreign-Language Title Mismatches

Releases under alternate names ("Sousou no Frieren" vs "Frieren: Beyond Journey's End"; "La Oficina" vs "The Office (MX)"). Sonarr resolves most via alias matching; the jq `--arg` payload builder handles brackets/apostrophes in SubsPlease-style names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 8.12 Season Pack Imports

Require Interactive Import: Wanted → Manual Import → folder → Interactive Import.

### 8.13 Fake / Malicious Torrents

arr-rescans detects executable payloads, alerts Discord once, and genuinely skips the folder. Blocklist the release in the *arr to trigger a search for a valid replacement, then remove the folder.

---

## 9. Maintenance Procedures

### 9.1 Sync Status & Pinned Changes

```bash
syncstatus    # alias, §4.4
# Pinned deletes older than the oldest live torrent (~14d) indicate propagation failure:
curl -s "http://localhost:8384/rest/db/localchanged?folder=sfqzb-cvm5v&perpage=1000" -H "X-API-Key: $STKEY" | \
  jq -r '.files[] | select(.deleted) | .name'
```

### 9.2 Import Logs

```bash
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30
docker logs sonarr --since 1h 2>&1 | grep Error | tail -20
docker logs unpackerr --since 1h 2>&1 | grep -iE "queued|started|extract|error" | tail -30
```

### 9.3 Manual Script Runs

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
bash /boot/config/plugins/user.scripts/scripts/arr-import-monitor/script
bash /boot/config/plugins/user.scripts/scripts/arr-cleanup/script       # dry run unless CLEANUP_LIVE=1
```

### 9.4 Clearing Ghost / Stale Queue Entries

```bash
source /boot/config/arr-rescans.conf
# List
curl -s "http://192.168.1.12:7878/api/v3/queue?pageSize=200" -H "X-Api-Key: $RADARR_KEY" | \
  jq '.records[] | {id, title, status, trackedDownloadState}'
# Single
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
# Bulk
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/bulk?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"ids":[ID1,ID2,ID3]}'
```

### 9.5 Verifying Unpackerr After Any Change

```bash
docker logs unpackerr 2>&1 | head -60 | grep -iE "sonarr|radarr"   # paths:[...] must be app-specific
docker logs unpackerr -f 2>&1 | grep -iE "queued|extract"          # watch a live pickup
```

### 9.6 Syncthing Index Reset (stuck-state breaker)

```bash
docker stop binhex-syncthing
rm -rf /mnt/user/appdata/binhex-syncthing/syncthing/config/index-v0.14.0.db
docker start binhex-syncthing
```

Forces a clean re-index with `.stignore` applied from scratch. Expect a full scan; safe on a Receive Only folder.

### 9.7 Updating Credentials / Runtime Switches

```bash
nano /boot/config/arr-rescans.conf
```

Never edit keys into the scripts themselves.

### 9.8 Stuck-Import Triage Order

1. **Is it in the *arr queue?** (`/api/v3/queue`, Lidarr v1) — check `trackedDownloadState` and `statusMessages`.
2. **`importPending` + archive message** → Unpackerr lane: `docker logs unpackerr`, look for stat errors (§8.1) vs. active extraction.
3. **Not in queue at all** → was the series/movie removed (§8.5)? Ghost entry already cleared? Check history for a prior import.
4. **Folder present but never scanned** → arr-rescans console output: which guard is firing? (sync-conflict / history / suspicious / awaiting unpack / empty dir)
5. **Folder absent on Caladan** → Syncthing: `syncstatus`, ignore patterns (§4.3), folder paused/errored?
6. Confirm state with API calls, not filesystem appearance or UI Test buttons.

---

## 10. Rebuild Checklist

### 10.1 Unraid Containers

- [ ] binhex-syncthing — host networking, port 8384, mounts per §4.1
- [ ] Sonarr (8989) / Radarr (7878) / Lidarr (8686) — mounts per §5.1
- [ ] **Manually add /downloads mapping to Lidarr**
- [ ] Unpackerr — mount `/mnt/user/media/download/sync` → `/downloads`
- [ ] Unpackerr env vars with **indexed** names: `UN_SONARR_0_PATHS_0=/downloads/sonarr`, `UN_RADARR_0_PATHS_0=/downloads/radarr` (§6.2)
- [ ] Verify Unpackerr startup log shows app-specific `paths:[...]` (§6.4)

### 10.2 Syncthing

- [ ] Add Media sync folder with ID `sfqzb-cvm5v`, type **Receive Only**, path `/media/sync`
- [ ] **Rescan interval 0**
- [ ] Add seedbox as remote device
- [ ] Deploy `.stignore` verbatim from §4.3
- [ ] **Verify ordering: exclusions (with `(?d)`) FIRST, includes second, `*` LAST**

### 10.3 *arr Apps

- [ ] qBittorrent download client per §5.2 (Advanced Settings for URL Base)
- [ ] **App-specific remote path mappings per §5.3** — trailing slashes, host `ibiza.seedhost.eu`
- [ ] Quality profiles per §5.5
- [ ] /downloads mount present in all three
- [ ] Discord notifications connected in Sonarr/Radarr

### 10.4 Seedbox

- [ ] qBittorrent default save path `/home18/scytale1953/Media-sync/`
- [ ] **Explicit save paths on all three categories** (§3.2)
- [ ] Seeding limits: 20160 min → Remove torrent and files
- [ ] Syncthing watchdog cron present
- [ ] Syncthing connected to Caladan device ID (Send Only)

### 10.5 User Scripts

- [ ] Install User Scripts plugin
- [ ] Create `/boot/config/arr-rescans.conf` per §7.1 (keys, webhook, VIDEO_EXTENSIONS); `chmod 600`
- [ ] arr-rescans v4.5.1 — `*/5 * * * *`
- [ ] arr-import-monitor v1.2 — `*/15 * * * *`
- [ ] arr-cleanup v2.0 — daily; leave `CLEANUP_LIVE` unset until first dry-run reviewed

### 10.6 Validation (do not skip)

- [ ] Grab a rar'd release; watch Unpackerr extract (`Extraction Queued → Started → %`) and the *arr import end-to-end
- [ ] arr-import-monitor console shows per-app queue counts
- [ ] Temporarily set `IMPORT_ALERT_THRESHOLD=0`, confirm a Discord alert arrives, restore
- [ ] arr-cleanup dry-run output sane against the qBittorrent torrent list
- [ ] `syncstatus` returns completion; no pins older than ~14 days

---

*Caladan Media Automation Guide — stored in git at /MyFiles/Systems/Caladan*
*Never commit arr-rescans.conf — it contains credentials*
*Canonical source: caladan_automation_guide.md — HTML companion: caladan_automation_guide.html*
