# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** June 2026  
**Server:** Caladan (192.168.1.12) — Unraid  

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

**CRITICAL:** Order matters — **first match wins**, and this cuts both ways:
- The `!` include exceptions must come BEFORE the trailing wildcard `*`.
- **All exclusion rules must come BEFORE the `!` includes.** An exclusion placed *below* `!/sonarr/**` is dead code: any path under `sonarr/` matches the include first and is never tested against it.

File location: `/mnt/user/media/download/sync/.stignore`

```
// EXCLUSIONS FIRST — anything below the ! includes is dead code
// (?d) = ignore, AND allow Syncthing to delete when removing a parent dir.
// Without (?d), a remote-deleted folder containing ignored files stalls with
// "directory has been deleted on a remote device but contains ignored files".
(?d)(?i)*sample*
(?d)(?i)screens
(?d)*.nfo
(?d)*.srr
(?d)*.sync-conflict-*

// Image exclusions are scoped to VIDEO trees only.
// A bare *.jpg would strip cover.jpg / folder.jpg from Lidarr music
// imports and break album art. Do not globalise these.
(?d)/sonarr/*.jpg
(?d)/sonarr/*.jpeg
(?d)/sonarr/**/*.jpg
(?d)/sonarr/**/*.jpeg
(?d)/radarr/*.jpg
(?d)/radarr/*.jpeg
(?d)/radarr/**/*.jpg
(?d)/radarr/**/*.jpeg

// Vestigial: v4.4 creates no marker files. Retained so leftovers from
// older script versions are not flagged as local additions.
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

**Why exclusions must precede the includes**

This was a real, confirmed failure (see Section 6.10). A ruleset with the sample/nfo/screens rules appended *below* the `!` includes silently synced everything it was meant to block — `Sample/` folders and `.nfo` files arrived on Caladan despite matching rules being present in the file. The rules were never reached.

The cheapest way to verify correct ordering: **if `.nfo` files are syncing, the ordering is wrong.**

**Sample suppression — `(?i)*sample*`**

Sample subdirectories (`Sample/`) and loose sample files (`sample.mkv`, `RELEASE-sample.mkv`) are a latent source of bad imports in Sonarr/Radarr, and a certain source of wasted bandwidth and disk. Excluding them at the Syncthing layer is the robust fix: the sample never lands on Caladan, so there is nothing for the rescan scanner to misimport and nothing to clean up. Deleting samples from the sync folder via script is *not* robust — a delete on a Receive Only folder is flagged as a local change and can be re-pulled unless the file is also ignored here. Sonarr/Radarr native sample rejection remains the second layer (see Section 6.11).

How the pattern behaves (per Syncthing ignore semantics):
- A bare name matches at any depth, so `(?i)*sample*` matches any path component containing "sample" anywhere under the synced root.
- `*` does not cross `/`, so it only matches within a single component — it will not match across the whole path.
- A matched directory ignores everything inside it, so `Sample/` and its contents are skipped in one rule.
- Because it sits before the first `!` negation, matched directories are skipped entirely rather than traversed (also faster).
- It does not match `sonarr`/`radarr`/`lidarr` themselves (no "sample" substring), so those still fall through to their `!` includes. A normal episode (`Show.S01E01-GROUP.mkv`) has no "sample" component and is unaffected.

**Three pattern-syntax traps to avoid**

- **Never globalise image exclusions.** A bare `*.jpg` matches inside `lidarr/` too and strips `cover.jpg` / `folder.jpg` from music releases, breaking Lidarr album art. Scope image rules to `/sonarr/` and `/radarr/` explicitly. Each needs both a root-level form (`/sonarr/*.jpg`) and a nested form (`/sonarr/**/*.jpg`), since `**` may not match zero path components.
- **No trailing slash on directory patterns.** `**/[Ss]ample/` matches the *contents* of the directory but NOT the directory itself, leaving an empty `Sample/` dir behind. Omit the slash — `(?i)*sample*` matches the directory and everything under it.
- **Use `(?i)`, not character classes.** `[Ss]ample` covers only two casings; `SAMPLE/` and `sAmple/` slip through. `(?i)` is case-insensitive across the board.

> **On `**/` prefixes:** these are unnecessary. Syncthing auto-expands a bare pattern to cover both root and nested positions — `(?i)screens` expands to `(?i)screens`, `(?i)**/screens`, `(?i)screens/**`, and `(?i)**/screens/**`. Writing `**/screens` yields the same expansion, so the bare form is preferred for readability.

> **Edge case:** content literally titled with "sample" as a substring would be dropped silently. This is vanishingly rare for TV/film. For a conservative variant, replace `(?i)*sample*` with the directory-only form plus loose-file conventions: `(?i)sample`, `(?i)sample-*`, `(?i)*-sample.*`.

> **`*.imported` / `*.first_seen`:** vestigial as of arr-rescans v4.4, which creates no marker files. Retained so that leftovers from older script versions are not flagged as local additions on the Receive Only folder. Harmless.

**Verifying the ruleset actually parsed**

Do not trust the file on disk — ask Syncthing what it loaded. The `expanded` array is authoritative and will reveal typos or bad ordering:

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s -X POST "http://localhost:8384/rest/db/scan?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
curl -s "http://localhost:8384/rest/db/ignores?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY" | jq
```

Check that `"error": null`, that every exclusion appears in `expanded` **above** the `!/sonarr` entries, and that no bare `*.jpg` / `*.jpeg` appears (it would hit Lidarr).

**Live canary:** the next release to land should arrive with **no `.nfo` file and no `Sample/` directory**. If a `.nfo` shows up, the ordering is wrong again.

**Reloading ignores + clearing existing samples**

Editing the file directly means Syncthing reloads ignores on its next scan. With the rescan interval disabled, trigger a scan so the rule takes effect *before* deleting anything (otherwise deleted samples may be re-pulled):

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s -X POST "http://localhost:8384/rest/db/scan?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
```

Then remove samples already on disk (after the ignore is live):

```bash
find /mnt/user/media/download/sync/{sonarr,radarr,lidarr} -depth -type d -iname 'sample' -exec rm -rf {} +
find /mnt/user/media/download/sync/{sonarr,radarr,lidarr} -type f -iname '*sample*' \
  ! -name '*.imported' ! -name '*.first_seen' -delete
```

> Sonarr/Radarr native sample rejection stays in place as a second layer for anything an unusual naming convention slips past this pattern.

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
- **Current version:** v4.4

> **Deployment note:** User Scripts copies the script to `/tmp/user.scripts/tmpScripts/arr-rescans/` before execution. Edits to the `/boot/config/...` path require a fresh User Scripts trigger to take effect — verify the running version with `head -3` on the boot path, not the tmp copy.

### 5.3 Script Contents

**Current version: v4.4.** Import detection is via the Sonarr/Radarr **history API** (`eventType=3`), not marker files. Marker files (`.imported`, `.first_seen`, `.alerted`) and hardlink-count detection were removed in v4.x — hardlink detection is unreliable on Unraid because unionfs prevents hardlinks across disks, so a successful import that *copies* leaves a link count of 1 and is misread as "not imported".

Stuck-import alerting is **not** handled here — that is `arr-import-monitor`'s job.

```bash
#!/bin/bash
# arr-rescans v4.4
# Core function: trigger *arr scans on synced download folders.
# Import detection via Sonarr/Radarr history API — no marker files required.
# Alerting on stuck imports is handled separately by arr-import-monitor.
#
# Schedule: */5 * * * *
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
# Defers the scan while a .rar set is present, so Sonarr cannot pick up a
# partially-extracted .mkv while Unpackarr is still working. Purely about
# timing; disk footprint of the .rar set is handled by weekly cleanup.
awaiting_unpack() {
  compgen -G "${1}*.rar" > /dev/null
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
    local folder
    folder=$(basename "$item")

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

echo "arr-rescans v4.4 complete."
```

### 5.4 Script Design Notes

**Import detection via history API** — the script queries `/api/v3/history?eventType=3` (downloadFolderImported) once per app and greps the returned `droppedPath` values. A folder already present in history is skipped. This replaced marker files and hardlink-count detection, both of which were unreliable:
- *Hardlink counting* fails because Unraid's unionfs prevents hardlinks across disks. When the sync folder and library land on different physical disks, Sonarr/Radarr **copy** rather than hardlink, leaving the source at link count 1 — indistinguishable from "never imported".
- *`.imported` markers* were stamped on API acknowledgment, not confirmed import, so a scan firing before the real file arrived could permanently block re-scanning.

> **Known limitation:** `in_history()` does an unanchored substring match. A release folder whose name is a strict prefix of another (`Show.S01E01` vs `Show.S01E01.PROPER`) could false-positive as already imported. Low probability, but it fails silently.

**External config file** — API keys, Discord webhook, and `VIDEO_EXTENSIONS` live in `/boot/config/arr-rescans.conf`, separate from the script. Never commit the conf file to git.

**Single pass per app (v4.4)** — suspicious-file detection and scan submission were separate loops in v4.3, which meant a folder flagged as suspicious was still scanned by the loop below. The Discord message claimed "Import skipped" while the import proceeded. They are now one loop, so the skip is real.

**Suspicious-alert deduplication (v4.4)** — a suspicious folder never enters import history, so it never gets skipped by the history check and re-alerted on every 5-minute run. State file `/tmp/arr-rescans-suspicious.state` alerts once per folder, and is pruned each run so a re-downloaded release can alert again.

**RAR guard (`compgen -G "${item}*.rar"`)** — defers scanning any folder still holding a `.rar` set, so Sonarr cannot import a partially-extracted `.mkv` while Unpackarr is working. This is about **timing, not disk** — the `.rar` set's disk footprint is reclaimed by the weekly cleanup. Prophylactic: no bad import has been observed (Sonarr's native sample rejection has caught it so far — see Section 6.11), but the guard removes the failure mode rather than relying on that filter. Delete the two blocks marked `--- RAR GUARD` to disable.

**Lidarr uses `/api/v1/`** — not `/api/v3/` like Sonarr and Radarr. v4.3 posted `RefreshMonitoredDownloads` to `/api/v3/command`, which Lidarr does not serve; that call was silently failing. Fixed in v4.4.

**send_notification function** — sends to Discord and falls back to Unraid native notification if Discord returns a non-204 response.

**jq `--arg` payload builder** — safely handles special characters in folder names including brackets, spaces, and apostrophes common in anime and foreign language releases.

**`--max-time 30` on all curl calls** — prevents a hung API call from stalling the whole run inside a 5-minute cron window.

**Stuck-import alerting is NOT here** — that is `arr-import-monitor`'s job (queue API, `importPending`/`importFailed`, 15-minute schedule). The `.first_seen` / `.alerted` marker logic from older versions has been removed entirely.

**Stale Radarr queue entries** — when imports happen via DownloadedMoviesScan rather than the normal queue flow, Radarr may retain stale "completed" queue entries. Clear via Radarr → Activity → Queue or the API:
```bash
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

### 5.5 sync-cleanup Script

**Current version: v2.1.** Removes imported files from the sync folders. Runs weekly.

- **Path:** `/boot/config/plugins/user.scripts/scripts/sync-cleanup/script`
- **Usage:** `bash sync-cleanup` = DRY-RUN (default). `bash sync-cleanup --live` = delete.

**Four bugs fixed in v2.0 — all were causing real damage:**

| Bug | Effect |
|-----|--------|
| Called Syncthing `/rest/db/revert` after deleting | Revert **restored** everything just deleted, every week (see 6.13) |
| `LIVE=true` hardcoded | `--live` was a no-op; every run deleted for real |
| Age gated on directory mtime | Any touch to a folder reset its clock; weeks-old content read as "15m" (see 6.14) |
| `pageSize=1000` vs 2290 records | Anything older than the window stranded forever (see 6.15) |

**Design:**
- **Per-file deletion.** A partially-imported season pack keeps its un-imported episodes; only the imported ones go.
- **Residue sweep.** Once a folder's imported video files are gone and nothing un-imported remains, the folder is removed — reclaiming the RAR set, sample, nfo, sfv. Never touches a folder it did not delete from, and never touches a folder holding conflict copies.
- **Age from import history**, not the filesystem.
- **Conflict copies reported, never deleted.** Sonarr has imported `sync-conflict-*` files as real episodes; these need review.
- **Orphan reporting (v2.1).** Content un-imported for > `ORPHAN_DAYS` (default 14) is reported to Discord, never auto-deleted. Catches the removed-series case (6.16), which nothing else detects.

**Config additions** (optional, in `/boot/config/arr-rescans.conf`):
```bash
SYNC_MIN_AGE_MINUTES=1440   # min age since import before deleting (24h)
ORPHAN_DAYS=14              # report un-imported content older than this
RECEIVE_ONLY_WARN=500       # Discord note if receiveOnlyChangedItems exceeds
```

```bash
#!/bin/bash
# sync-cleanup v2.1
# Removes successfully imported files from Caladan sync folders.
#
# Usage:
#   bash sync-cleanup          # DRY-RUN (default — lists what would be deleted)
#   bash sync-cleanup --live   # actually deletes
#
# Changes from v1.2 — all four were causing real damage or masking it:
#
#   1. NO SYNCTHING REVERT. v1.2 deleted files and then called /rest/db/revert.
#      On a Receive Only folder a local deletion IS a local change, so revert
#      restored everything the script had just deleted. Confirmed: the same
#      folders were reported "Removed" on 2026-06-30 and again on 2026-07-04
#      and are still on disk. Deleting the revert call is the fix; Receive Only
#      folders do not auto re-pull local deletions, they just flag them.
#
#   2. DRY-RUN ACTUALLY WORKS. v1.2 had `LIVE=true` hardcoded, so --live was a
#      no-op and every invocation deleted for real.
#
#   3. AGE COMES FROM IMPORT HISTORY, NOT DIRECTORY MTIME. Directory mtime
#      changes whenever anything inside is touched — Unpackarr extracting, a
#      cleanup pass, Syncthing re-pulling. v1.2 would see a months-old folder as
#      "too new, 15m" after any such touch and skip it indefinitely.
#
#   4. PAGINATED HISTORY. v1.2 fetched pageSize=1000 against 2290 total records,
#      so anything older than the window could never match and was stranded
#      permanently.
#
# Also new: per-file deletion (partial season packs keep their un-imported
# episodes), sync-conflict reporting, and printed skip reasons.
#
# v2.1 — ORPHAN DETECTION.
#   Un-imported content is never auto-deleted (a stuck import and an abandoned
#   one look identical on disk, and deleting a stuck import loses the file).
#   But un-imported content also accumulates silently and forever. The known
#   cause: removing a series from Sonarr strands its in-flight downloads — they
#   can never import, because there is nothing to import them into.
#   Real case: ~20 Love Island files, 106 GB, invisible for weeks.
#   arr-import-monitor did not catch it (they never enter the queue), and
#   sync-cleanup correctly refused to touch them.
#   v2.1 REPORTS anything un-imported for > ORPHAN_DAYS so it is visible.
#   It still does not delete — that stays a human decision.

set -o pipefail

# ---------------------------------------------------------------------------
# Mode
# ---------------------------------------------------------------------------
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

# Minimum age (minutes) since the IMPORT was recorded, before deleting.
MIN_AGE_MINUTES="${SYNC_MIN_AGE_MINUTES:-1440}"   # 24h

# Warn on Discord if receive-only changed items exceeds this.
RECEIVE_ONLY_WARN="${RECEIVE_ONLY_WARN:-500}"

# Un-imported content older than this many days is reported as a probable
# orphan. Defaults to 14 to match the seedbox seeding window — past that, the
# torrent is gone and nothing new will arrive to complete the import.
ORPHAN_DAYS="${ORPHAN_DAYS:-14}"

VIDEO_EXTENSIONS="${VIDEO_EXTENSIONS:-mkv mp4 avi m4v mov}"
AUDIO_EXTENSIONS="${AUDIO_EXTENSIONS:-flac mp3 m4a ogg opus wav}"

NOW=$(date +%s)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*"; }

send_notification() {
  local message="$1" MSG HTTP_CODE ERROR
  MSG=$(jq -n --arg msg "$message" '{content: $msg}')
  HTTP_CODE=$(curl -s --max-time 30 -o /tmp/discord_response.json -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "$MSG" "$DISCORD_WEBHOOK")
  if [ "$HTTP_CODE" != "204" ]; then
    ERROR=$(cat /tmp/discord_response.json 2>/dev/null)
    /usr/local/emhttp/webGui/scripts/notify \
      -e "sync-cleanup" -s "Discord webhook error" \
      -d "HTTP $HTTP_CODE: $ERROR" -i "warning"
  fi
}

# Fetch ALL downloadFolderImported records, paginating until exhausted.
# Emits TSV: <epoch>\t<droppedPath>
fetch_history() {
  local base="$1" key="$2" apiver="$3"
  local page=1 total fetched=0 resp
  local page_size=1000

  total=$(curl -s --max-time 30 \
    "$base/api/$apiver/history?pageSize=1&eventType=3" \
    -H "X-Api-Key: $key" | jq -r '.totalRecords // 0')

  if ! [[ "$total" =~ ^[0-9]+$ ]]; then
    log "ERROR: could not read totalRecords from $base" >&2
    return 1
  fi

  while [ "$fetched" -lt "$total" ]; do
    resp=$(curl -s --max-time 60 \
      "$base/api/$apiver/history?page=$page&pageSize=$page_size&eventType=3" \
      -H "X-Api-Key: $key")
    echo "$resp" | jq -e '.records' > /dev/null 2>&1 || {
      log "ERROR: invalid history response from $base (page $page)" >&2
      return 1
    }
    echo "$resp" | jq -r '
      .records[]
      | select(.data.droppedPath != null)
      | [(.date | sub("\\..*Z$"; "Z") | fromdateiso8601), .data.droppedPath]
      | @tsv'
    fetched=$(( fetched + page_size ))
    page=$(( page + 1 ))
    [ "$page" -gt 50 ] && break   # hard stop, 50k records
  done
  return 0
}

# Look up the import epoch for a given basename. Echoes epoch, or nothing.
import_epoch() {
  local name="$1" hist="$2"
  grep -F -- "$name" <<< "$hist" | head -1 | cut -f1
}

# ---------------------------------------------------------------------------
# Fetch history
# ---------------------------------------------------------------------------
log "Fetching Sonarr import history (paginated)..."
SONARR_HIST=$(fetch_history "$SONARR" "$SONARR_KEY" "v3") || exit 1
log "Fetching Radarr import history (paginated)..."
RADARR_HIST=$(fetch_history "$RADARR" "$RADARR_KEY" "v3") || exit 1
log "Fetching Lidarr import history (paginated)..."
LIDARR_HIST=$(fetch_history "$LIDARR" "$LIDARR_KEY" "v1") || exit 1

log "History records: Sonarr=$(grep -c . <<< "$SONARR_HIST") Radarr=$(grep -c . <<< "$RADARR_HIST") Lidarr=$(grep -c . <<< "$LIDARR_HIST")"
log "Mode: $($LIVE && echo LIVE || echo DRY-RUN)   Min age: ${MIN_AGE_MINUTES}m"
echo ""

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
DELETED=()        # human-readable lines
FREED_BYTES=0
SKIP_TOO_NEW=0
SKIP_NOT_IMPORTED=0
CONFLICTS=()
DIRS_REMOVED=()
DELETED_DIRS=()   # basenames of dirs we deleted at least one imported file from

# Build the -iname predicate list for a given extension set
find_media() {
  local dir="$1" exts="$2"
  local args=() first=1
  args+=(find "$dir" -type f \()
  for e in $exts; do
    [ $first -eq 0 ] && args+=(-o)
    args+=(-iname "*.$e")
    first=0
  done
  args+=(\))
  "${args[@]}"
}

# Process every media file under one app's sync tree.
process_tree() {
  local label="$1" root="$2" hist="$3" exts="$4"

  [ -d "$root" ] || return 0
  log "=== $label ==="

  local f name epoch age size
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    name=$(basename "$f")

    # Never touch Syncthing conflict copies — report them instead.
    if [[ "$name" == *sync-conflict-* ]]; then
      CONFLICTS+=("$f")
      continue
    fi

    epoch=$(import_epoch "$name" "$hist")
    if [ -z "$epoch" ]; then
      SKIP_NOT_IMPORTED=$(( SKIP_NOT_IMPORTED + 1 ))
      # Probable orphan? Use the FILE mtime here — there is no history record to
      # date it against, and unlike directory mtime a file's mtime is not
      # disturbed by sibling deletions or residue sweeps.
      local fmtime fage_days fsize
      fmtime=$(stat -c %Y "$f" 2>/dev/null || echo "$NOW")
      fage_days=$(( (NOW - fmtime) / 86400 ))
      if [ "$fage_days" -ge "$ORPHAN_DAYS" ]; then
        fsize=$(stat -c %s "$f" 2>/dev/null || echo 0)
        ORPHANS+=("$(printf '%s\t%s\t%s' "$fsize" "$fage_days" "$f")")
        ORPHAN_BYTES=$(( ORPHAN_BYTES + fsize ))
        log "  ORPHAN? (not imported, ${fage_days}d old): $name"
      else
        log "  SKIP (not imported, ${fage_days}d old): $name"
      fi
      continue
    fi

    age=$(( (NOW - epoch) / 60 ))
    if [ "$age" -lt "$MIN_AGE_MINUTES" ]; then
      log "  SKIP (imported ${age}m ago, < ${MIN_AGE_MINUTES}m): $name"
      SKIP_TOO_NEW=$(( SKIP_TOO_NEW + 1 ))
      continue
    fi

    size=$(stat -c %s "$f" 2>/dev/null || echo 0)
    if $LIVE; then
      rm -f "$f" && log "  DELETED (imported ${age}m ago): $name"
    else
      log "  WOULD DELETE (imported ${age}m ago): $name"
    fi
    DELETED+=("$name")
    FREED_BYTES=$(( FREED_BYTES + size ))
    local pd
    pd=$(basename "$(dirname "$f")")
    [[ " ${DELETED_DIRS[*]-} " == *" $pd "* ]] || DELETED_DIRS+=("$pd")
  done < <(find_media "$root" "$exts")

  # Residue sweep.
  #
  # A folder is residue ONLY IF we actually deleted an imported file from it AND
  # nothing of value remains. "Of value" = a media file that is not a sample and
  # not a conflict copy. What's left over then is the RAR set, nfo, sfv, sample
  # and screens — safe to drop, and this is what reclaims the RAR double
  # footprint.
  #
  # Two hard rules, both learned from the fixture test:
  #   - NEVER remove a folder we did not delete from. A folder holding only a
  #     conflict copy, or only un-imported content, must be left completely alone.
  #   - Samples do not count as "of value" when deciding residue, or a leftover
  #     Sample/ dir would pin the whole RAR set on disk forever.
  local d dirname_only kept
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    dirname_only=$(basename "$d")

    # Did we delete anything from this folder this run?
    [[ " ${DELETED_DIRS[*]-} " == *" $dirname_only "* ]] || continue

    # Anything left worth keeping? (excludes samples and conflict copies)
    kept=$(find_media "$d" "$exts" \
      | grep -v -i 'sample' \
      | grep -v 'sync-conflict-' \
      | grep -c . || true)
    [ "$kept" -gt 0 ] && continue

    # Refuse to touch a folder containing conflict copies — they need review.
    if find_media "$d" "$exts" | grep -q 'sync-conflict-'; then
      log "  KEEP (holds conflict copies): $dirname_only"
      continue
    fi

    if $LIVE; then
      rm -rf "$d" && log "  RESIDUE REMOVED: $dirname_only"
    else
      log "  WOULD REMOVE RESIDUE: $dirname_only"
    fi
    DIRS_REMOVED+=("$dirname_only")
  done
}

process_tree "Sonarr" "$SYNC_SONARR" "$SONARR_HIST" "$VIDEO_EXTENSIONS"
process_tree "Radarr" "$SYNC_RADARR" "$RADARR_HIST" "$VIDEO_EXTENSIONS"
process_tree "Lidarr" "$SYNC_LIDARR" "$LIDARR_HIST" "$AUDIO_EXTENSIONS"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
FREED_H=$(numfmt --to=iec "$FREED_BYTES" 2>/dev/null || echo "${FREED_BYTES}B")

echo ""
log "=== Summary ==="
log "  Files deleted        : ${#DELETED[@]}  (${FREED_H})"
log "  Residue dirs removed : ${#DIRS_REMOVED[@]}"
log "  Skipped (too new)    : $SKIP_TOO_NEW"
log "  Skipped (not imported): $SKIP_NOT_IMPORTED"
log "  Sync-conflict files  : ${#CONFLICTS[@]}"
ORPHAN_H=$(numfmt --to=iec "$ORPHAN_BYTES" 2>/dev/null || echo "${ORPHAN_BYTES}B")
log "  Probable orphans     : ${#ORPHANS[@]}  (${ORPHAN_H}, un-imported >${ORPHAN_DAYS}d)"

if [ "${#ORPHANS[@]}" -gt 0 ]; then
  log "  ⚠ Un-imported for >${ORPHAN_DAYS}d — likely a series removed from Sonarr,"
  log "    or a genuinely stuck import. NOT auto-deleted. Review these:"
  printf '%s\n' "${ORPHANS[@]}" | sort -rn | head -10 | while IFS=$'\t' read -r sz d p; do
    log "      $(numfmt --to=iec "$sz")  ${d}d  $(basename "$p")"
  done
fi

if [ "${#CONFLICTS[@]}" -gt 0 ]; then
  log "  ⚠ Conflict copies present — these can be imported as real episodes:"
  printf '      %s\n' "${CONFLICTS[@]:0:10}"
fi

# Receive-only counter — will now climb, since we no longer revert.
STKEY=$(grep -o '<apikey>[^<]*' "$SYNCTHING_CONFIG" | cut -d'>' -f2)
RO_CHANGED=$(curl -s --max-time 15 \
  "http://localhost:8384/rest/db/status?folder=$SYNCTHING_FOLDER_ID" \
  -H "X-API-Key: $STKEY" | jq -r '.receiveOnlyChangedItems // 0')
log "  Receive-only changed : $RO_CHANGED"

if ! $LIVE; then
  echo ""
  log "(DRY-RUN — rerun with --live to actually delete)"
  exit 0
fi

if [ "${#DELETED[@]}" -eq 0 ] && [ "${#CONFLICTS[@]}" -eq 0 ] && [ "${#ORPHANS[@]}" -eq 0 ]; then
  log "Nothing to do."
  exit 0
fi

MSG="🧹 **sync-cleanup**: removed ${#DELETED[@]} imported file(s), freed **${FREED_H}**, cleared ${#DIRS_REMOVED[@]} residue folder(s)."

if [ "${#CONFLICTS[@]}" -gt 0 ]; then
  MSG="$MSG
⚠️ **${#CONFLICTS[@]} Syncthing conflict copies** present — these can be imported as real episodes. Investigate."
fi

if [ "${#ORPHANS[@]}" -gt 0 ]; then
  ORPHAN_TOP=$(printf '%s\n' "${ORPHANS[@]}" | sort -rn | head -8 \
    | while IFS=$'\t' read -r sz d p; do
        printf '  • %s  %sd  %s\n' "$(numfmt --to=iec "$sz")" "$d" "$(basename "$p")"
      done)
  MSG="$MSG
🗑️ **${#ORPHANS[@]} probable orphan(s)** — ${ORPHAN_H} un-imported for >${ORPHAN_DAYS} days. Common cause: the series was removed from Sonarr, so these can never import. Not auto-deleted — review and remove manually if unwanted.
\`\`\`
$ORPHAN_TOP
\`\`\`"
fi

if [ "$RO_CHANGED" -gt "$RECEIVE_ONLY_WARN" ]; then
  MSG="$MSG
📊 Receive-only changed items: **$RO_CHANGED** (> $RECEIVE_ONLY_WARN). Expected to grow after deletions; the seedbox's own cleanup clears it. Investigate only if it keeps climbing."
fi

LIST=$(printf '%s\n' "${DELETED[@]}" | head -20 | sed 's/^/  • /')
[ "${#DELETED[@]}" -gt 20 ] && LIST="$LIST
  …and $(( ${#DELETED[@]} - 20 )) more"

if [ "${#DELETED[@]}" -gt 0 ]; then
  MSG="$MSG
\`\`\`
$LIST
\`\`\`"
fi

send_notification "$MSG"
log "Done."
```

---

## 6. Known Issues & Workarounds

### 6.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 6.2 Anime Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most via alias matching. The jq payload builder handles bracket characters in SubsPlease folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 6.3 Syncthing Race Condition

The rescan script retries every 5 minutes until the `.imported` marker is created, so files mid-sync will be caught on subsequent runs.

### 6.4 Syncthing Local Additions

After deleting imported files locally, Syncthing tracks these as "Locally Changed Items". Click Revert Local Changes to reset when needed.

### 6.5 Season Pack Imports

Require Interactive Import in Sonarr. Use Wanted > Manual Import > folder > Interactive Import.

### 6.6 Fake/Malicious Torrents

The rescan script detects .exe and other suspicious files, sends a Discord alert, and skips import. Blocklist the release in Sonarr/Radarr to trigger a search for a valid release.

### 6.7 Remote Path Mapping Host

qBittorrent remote path mapping host must be `ibiza.seedhost.eu`. Remote path must be `/home18/scytale1953/Media-sync` without trailing slash or app subfolder.

### 6.8 Foreign Language Series Title Mismatches

Sonarr stores the TVDB canonical title regardless of search term used when adding. If a series is only available under a foreign title (e.g. "La Oficina" vs "The Office (MX)"), submit the alias to TVDB. Once approved, refresh the series in Sonarr to pull in the alias.

### 6.9 Resetting a Stuck Import

**Marker files no longer exist as of v4.x.** Deleting a `.imported` file is obsolete advice — if you find one, it is a leftover from an old script version and can simply be removed.

A folder is skipped only if its name appears in the *arr import history (`eventType=3`). To force a re-scan of a folder the script is skipping, check whether it is genuinely in history:

```bash
source /boot/config/arr-rescans.conf
curl -s "http://192.168.1.12:8989/api/v3/history?pageSize=1000&eventType=3&apikey=$SONARR_KEY" \
  | jq -r '.records[].data.droppedPath // empty' | grep -F "FOLDERNAME"
```

- **Match found, but nothing in the library** → the history record is real but the import failed downstream. Remove the history record in Sonarr (Activity → History) or blocklist and re-grab.
- **No match, yet the folder is still skipped** → check for a false-positive substring match (see the `in_history()` limitation in Section 5.4).
- **Suspicious-flagged folder** → it is being skipped by the suspicious check, not history. Clear it from the state file:
  ```bash
  sed -i '/^FOLDERNAME$/d' /tmp/arr-rescans-suspicious.state
  ```

Then trigger a run:
```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

### 6.10 Ignore-Pattern Ordering (CONFIRMED BUG — FIXED)

**Status:** confirmed and fixed, July 2026.

A `.stignore` containing `**/[Ss]ample/`, `*.nfo`, `**/Screens/` synced all of them anyway: the rules were appended *below* the `!/sonarr/**` include, and first-match-wins meant every path under `sonarr/` matched the include and was never tested against the exclusions. The rules were present but unreachable.

**Diagnostic tell:** `.nfo` files landing in the sync folder while `*.nfo` is in `.stignore`. Cheapest canary — check this before suspecting pattern syntax.

**Fix:** all exclusions ABOVE the `!` includes (Section 3.3), plus `(?d)` prefixes (see 6.13).

### 6.11 Sample Import Risk (LATENT — mechanism corrected)

Samples are a latent source of bad imports: if a scan fires when only a sample is present as a playable file, Sonarr could import it.

**No confirmed bad import has occurred.** An earlier analysis in this guide claimed House of the Dragon S03E03 proved Sonarr's sample filter had saved us. That was wrong. Checking `droppedPath` in history showed the ETHEL release **never imported at all** — the 4.1 GB library file came from a *different* release (`...REPACK...-NTb`). The ETHEL folder was superseded, not rescued.

The Syncthing exclusion (3.3) and the RAR guard (5.3) remain justified as defense-in-depth, but not on the strength of that case.

### 6.12 RAR Releases: Double Disk Footprint

Scene releases arrive as a RAR set which Unpackarr extracts in place, leaving both the `.rar` parts and the extracted `.mkv` — an 8.4 GB folder for a 4.3 GB episode. The RAR parts ARE the payload and cannot be excluded in `.stignore`.

**Resolved by sync-cleanup v2.0's residue sweep:** once a folder's imported video files are deleted, anything left (RAR set, nfo, sfv, sample, screens) is residue and the whole folder is removed. This is what reclaims the double footprint.

### 6.13 Syncthing Revert Loop (CONFIRMED — ROOT CAUSE OF DISK BLOAT)

**The single most damaging bug found. Fixed in sync-cleanup v2.0.**

sync-cleanup v1.2 deleted imported files and then called `/rest/db/revert`. On a **Receive Only** folder a local deletion IS a local change — and revert's entire purpose is to discard local changes and restore cluster state. So Syncthing re-downloaded everything the script had just deleted. Every week.

**Evidence:** identical folders (`Anne With An E S01/S02/S03`, `Glee.S06`, `Hacks.S03`) reported as "Removed" in the Discord summary on 2026-06-30 AND again on 2026-07-04 — and still present on disk on 2026-07-13.

**Cascade:** the delete/re-pull cycle raced against the seedbox's 14-day torrent removal, producing `sync-conflict-*` copies — **which Sonarr then imported as real episodes** (visible in `droppedPath` history). Some library files may be conflict-copy imports.

**Fix:** remove the revert call entirely. Receive Only folders do not auto re-pull local deletions; they flag them as locally-changed and leave them alone. `receiveOnlyChangedItems` will climb — this is cosmetic, and the seedbox's own cleanup clears it.

**Result:** sync folder went from 268 GB to 106 GB on the first correct run (127 files, 26 residue folders).

### 6.14 Directory mtime Is Not Content Age

sync-cleanup v1.2 gated deletion on directory mtime. Directory mtime changes whenever *anything* inside is touched — Unpackarr extracting, a cleanup pass, Syncthing re-pulling. After a sample purge, 55 folders that were weeks old all reported "too new, 15m" and were skipped.

**Fix (v2.0):** age comes from the import history record's timestamp, not the filesystem.

### 6.15 History API Pagination

Both scripts fetched `pageSize=1000` while Sonarr held `totalRecords: 2290`. Anything older than the window could never match and was stranded permanently. **Fix (v2.0):** paginate until `totalRecords` is exhausted.

### 6.16 Removing a Series from Sonarr Strands Its Downloads

**Confirmed, July 2026 — 106 GB, ~20 files, invisible for weeks.**

Love Island was removed from Sonarr after its episodes downloaded. The downloads remained in the sync folder, but with no series in the library there is nothing to import them *into*. Sonarr logged only `Folder/File specified for import scan [...] doesn't exist` warnings.

Every component behaved correctly, which is why it was silent:
- `arr-rescans` scanned them; Sonarr had nowhere to put them.
- `arr-import-monitor` saw nothing — these never enter the **queue**, so they are not "stuck imports".
- `sync-cleanup` correctly refused to delete un-imported content.

The result is orphaned content accumulating forever with no alert.

**Mitigation (sync-cleanup v2.1):** report — never auto-delete — any content un-imported for more than `ORPHAN_DAYS` (default 14, matching the seed window). A stuck import and an abandoned one look identical on disk, so deletion stays a human decision.

**When removing a series from Sonarr, check the sync folder for in-flight downloads of that series and remove them manually.**

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

### 7.8 Reloading Ignores / Purging Existing Samples

After editing `.stignore`, force a folder rescan so Syncthing reloads the patterns (rescan interval is disabled), then remove any samples already on disk. Run the rescan FIRST so deleted samples are not re-pulled.

```bash
# Reload ignores via a forced rescan
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s -X POST "http://localhost:8384/rest/db/scan?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"

# Purge existing sample dirs and files (preserves marker files)
find /mnt/user/media/download/sync/{sonarr,radarr,lidarr} -depth -type d -iname 'sample' -exec rm -rf {} +
find /mnt/user/media/download/sync/{sonarr,radarr,lidarr} -type f -iname '*sample*' \
  ! -name '*.imported' ! -name '*.first_seen' -delete
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
- [ ] **Verify ordering: ALL exclusions FIRST, then `!` includes, then wildcard `*` LAST** — exclusions below the includes are dead code
- [ ] Verify directory patterns have NO trailing slash, and use `(?i)` not `[Ss]`
- [ ] **Verify NO bare `*.jpg` / `*.jpeg`** — scope image rules to `/sonarr/` and `/radarr/` or Lidarr album art breaks
- [ ] Verify the parse via `/rest/db/ignores` — check `"error": null` and inspect the `expanded` array
- [ ] Confirm samples are excluded (a `Sample/` subfolder on the seedbox should not sync to Caladan)
- [ ] Confirm `.nfo` files are NOT syncing — if they are, the ordering is wrong
- [ ] Confirm a music release still brings `cover.jpg` through to Lidarr

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
- [ ] Create `arr-rescans` script per Section 5.3
- [ ] Set schedule to `*/5 * * * *`
- [ ] Test by running manually
- [ ] Verify Discord alert received

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*
*Note: Never commit arr-rescans.conf to git — it contains sensitive credentials*
