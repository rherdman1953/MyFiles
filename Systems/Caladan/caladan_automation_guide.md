# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** March 2026  
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
ruTorrent (Seedbox) → Syncthing → /downloads (Caladan) → Sonarr / Radarr / Lidarr → Plex
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

### 2.1 ruTorrent Download Paths

Each *arr app has a label in ruTorrent that routes completed downloads to the correct subdirectory of `~/Media-sync/`. Configure in ruTorrent Settings > Autotools or via the label plugin.

| Label | Save Path |
|-------|-----------|
| sonarr | /home18/scytale1953/Media-sync/sonarr/ |
| radarr | /home18/scytale1953/Media-sync/radarr/ |
| lidarr | /home18/scytale1953/Media-sync/lidarr/ |

### 2.2 ruTorrent Ratio Groups

Ratio group 1 (ratioDef) is set as the default for all torrents:

| Setting | Value |
|---------|-------|
| Min Ratio % | 0 |
| Max Ratio % | 0 |
| Min Upload | 0 |
| Seed Time | 336 hours (14 days) |
| Action | Remove torrent |
| Default Group | 1 (ratioDef) |

> **Note:** Ratio groups remove the torrent from ruTorrent but do NOT delete files from Media-sync. The cleanup cron handles file deletion.

### 2.3 qBittorrent Configuration

qBittorrent is available at: https://ibiza.seedhost.eu/scytale1953/qbittorrent/

**Tools → Options → Downloads:**
- Default Save Path: /home18/scytale1953/Media-sync/

**Tools → Options → BitTorrent (Seeding Limits):**
- When ratio reaches: disabled (0)
- When seeding time reaches: 20160 minutes (14 days)
- Then: Remove torrent and files

> **Important:** The ruTorrent ratio plugin conf.php has MAX_RATIO set to 9999 to prevent it from removing torrents before the 14 day limit. If switching back to ruTorrent, verify this setting.

### 2.4 Seedbox Cleanup Cron Job

Runs nightly at 2am, removes files older than 2 days from the *arr sync folders. Prevents old imported files from re-syncing to Caladan after a Syncthing revert.

Edit with `crontab -e` on the seedbox:

```cron
MAILTO=""
*/5 * * * * /bin/bash ~/software/cron/syncthing
0 2 * * * find /home18/scytale1953/Media-sync/sonarr /home18/scytale1953/Media-sync/radarr /home18/scytale1953/Media-sync/lidarr -maxdepth 1 -mindepth 1 -mtime +7 -exec rm -rf {} \;
```

> The first entry is a pre-existing Syncthing watchdog that restarts Syncthing if it stops. Do not remove it.

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

**CRITICAL:** The exceptions must come BEFORE the wildcard. Order matters — first match wins.

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

When Syncthing shows "Local Additions" or "Locally Changed Items" and is not syncing new content, use the **Revert Local Changes** button in the Syncthing UI. This is safe because:

- Caladan is Receive Only — it will not delete media library files
- The seedbox cron ensures only current content exists in Media-sync
- Reverting clears Syncthing's tracking of deleted files, allowing correct resync

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

> **Note:** Lidarr does not include a /downloads mapping by default when deployed — it must be added manually.

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

> **Note:** Enable Advanced Settings in the dialog to see the URL Base field.

### 4.3 Remote Path Mappings

Required because seedbox paths differ from what *arr containers see. The Local Path must be the **container-side** path, not the host path.

| App | Remote Path (Seedbox) | Local Path (Container) |
|-----|-----------------------|------------------------|
| Sonarr | /home18/scytale1953/Media-sync/sonarr/ | /downloads/ |
| Radarr | /home18/scytale1953/Media-sync/radarr/ | /downloads/ |
| Lidarr | /home18/scytale1953/Media-sync/lidarr/ | /downloads/ |

### 4.4 API Keys

| Application | API Key |
|-------------|---------|
| Sonarr | b9440275020240a09ea857d4f77e6e75 |
| Radarr | 8fddd6564061499dbee5fe0510b0d43c |
| Lidarr | 73796d3440444db6892269434eeba795 |

### 4.5 Quality Profile (HD-1080p)

- Upgrades Allowed: Yes
- Upgrade Until: Bluray-1080p
- Quality order (most preferred first): Remux-1080p, Bluray-1080p, WEB 1080p (WEBRip + WEBDL), HDTV-1080p

---

## 5. Rescan Script (Unraid User Scripts)

### 5.1 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
- **Schedule:** `*/5 * * * *` (every 5 minutes)

### 5.2 Script Contents

```bash
#!/bin/bash
SONARR_KEY="b9440275020240a09ea857d4f77e6e75"
RADARR_KEY="8fddd6564061499dbee5fe0510b0d43c"
LIDARR_KEY="73796d3440444db6892269434eeba795"
SONARR="http://192.168.1.12:8989"
RADARR="http://192.168.1.12:7878"
LIDARR="http://192.168.1.12:8686"

# Refresh tracked queue items
curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$SONARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$RADARR/api/v3/command" > /dev/null
curl -s -X POST -H "X-Api-Key: $LIDARR_KEY" -H "Content-Type: application/json" \
  -d '{"name":"RefreshMonitoredDownloads"}' "$LIDARR/api/v3/command" > /dev/null

# Scan sonarr subfolders - skip if already marked as imported
for item in /mnt/user/media/download/sync/sonarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  if [ $(find "$item" -maxdepth 2 -mmin -60 -not -name ".imported" | wc -l) -eq 0 ]; then
    continue
  fi
  folder=$(basename "$item")
  # jq safely handles special characters in folder names (brackets, spaces, etc)
  PAYLOAD=$(jq -n --arg name "DownloadedEpisodesScan" --arg path "/downloads/$folder" \
    "{name: \$name, path: \$path}")
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$SONARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    touch "${item}.imported"
    echo "Sonarr scan: $folder"
  fi
done

# Scan radarr subfolders - skip if already marked as imported
for item in /mnt/user/media/download/sync/radarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  if [ $(find "$item" -maxdepth 2 -mmin -60 -not -name ".imported" | wc -l) -eq 0 ]; then
    continue
  fi
  folder=$(basename "$item")
  PAYLOAD=$(jq -n --arg name "DownloadedMoviesScan" --arg path "/downloads/$folder" \
    "{name: \$name, path: \$path}")
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $RADARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$RADARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    touch "${item}.imported"
    echo "Radarr scan: $folder"
  fi
done

# Handle loose .mkv files in sonarr sync folder
for mkv in /mnt/user/media/download/sync/sonarr/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  if [ $(find "$mkv" -mmin -60 | wc -l) -eq 0 ]; then
    continue
  fi
  filename=$(basename "$mkv")
  PAYLOAD=$(jq -n --arg name "DownloadedEpisodesScan" --arg path "/downloads/$filename" \
    "{name: \$name, path: \$path}")
  RESPONSE=$(curl -s -X POST -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD" "$SONARR/api/v3/command")
  if echo "$RESPONSE" | grep -q '"status"'; then
    touch "${mkv}.imported"
    echo "Sonarr scan: $filename"
  fi
done

# Handle loose .mkv files in radarr sync folder
for mkv in /mnt/user/media/download/sync/radarr/*.mkv; do
  [ -f "$mkv" ] || continue
  [ -f "${mkv}.imported" ] && continue
  if [ $(find "$mkv" -mmin -60 | wc -l) -eq 0 ]; then
    continue
  fi
  filename=$(basename "$mkv")
  PAYLOAD=$(jq -n --arg name "DownloadedMoviesScan" --arg path "/downloads/$filename" \
    "{name: \$name, path: \$path}")
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

### 5.3 Why DownloadedEpisodesScan per folder


### 5.3 Why DownloadedEpisodesScan Per Folder

The key insight from extensive testing: `DownloadedEpisodesScan` with a **specific subfolder path** reliably imports orphaned files. Several other approaches were tested and found unreliable:

- `DownloadedEpisodesScan` with root `/downloads` path — Sonarr does not recurse into subdirectories, returns empty
- `manualimport` POST API with `importMode: auto` or `move` — API returns success but never actually moves the file (confirmed bug in Sonarr v4.0.16-4.0.17)
- `RefreshMonitoredDownloads` alone — only works for files actively tracked in the queue, ignores orphaned files

Scanning each subfolder individually with `DownloadedEpisodesScan` works because Sonarr treats each call as a targeted import request for that specific directory, bypassing the queue tracking requirement entirely.

**The `jq --arg` payload builder** safely handles folder names with special characters (square brackets, spaces, apostrophes) that are common in anime releases like SubsPlease. Without this, bash variable expansion breaks the JSON payload for folders like `[SubsPlease] Sousou no Frieren S2 - 09 (1080p) [A3A99C65]`.

**The `.imported` marker file** is critical — without it, the script re-scans every folder on every 5-minute run. Each re-scan causes Sonarr/Radarr to treat the file as an upgrade, triggering delete/re-import cycles and flooding Discord with notifications. The marker file ensures each folder is scanned exactly once. When qBittorrent removes the folder after 14 days seeding, the marker is automatically cleaned up with it.

**The `-mmin -60` timestamp check** provides a secondary guard — only folders with files modified in the last 60 minutes are eligible for scanning, giving Syncthing enough time to fully deliver files before the import attempt.

**RefreshMonitoredDownloads:** Re-checks rTorrent for download status. Only works for files actively tracked in the queue. No path parameter needed.

**DownloadedEpisodesScan / DownloadedMoviesScan:** Scans the specified path for video files and imports them regardless of queue tracking. **Requires a path parameter** — omitting it causes a fatal `ArgumentException` error in Sonarr v4.0.16+. Catches files that arrived after the *arr app closed out download tracking.

---

## 6. Known Issues & Workarounds

### 6.1 TorrentLeech Timezone Mismatch

TorrentLeech RSS feeds via the Cardigann indexer in Prowlarr report negative ages (e.g. -284 minutes). This is cosmetic only and does not affect downloading or importing. No fix is available in indexer settings.

### 6.2 Anime Series Name Mismatches

Anime releases often use alternate names (e.g. "Trigun Stargaze" vs "Trigun Stampede", "Jujutsu Kaisen" vs "JUJUTSU KAISEN"). Sonarr handles most cases via alias matching automatically (Series Match Type: Alias). When auto-import fails due to name mismatch, use Wanted > Manual Import > Interactive Import.

### 6.3 Syncthing Race Condition

When a torrent completes on the seedbox, rTorrent notifies Sonarr/Radarr which immediately tries to import from /downloads. If Syncthing hasn't finished transferring yet, the import fails silently. The rescan script's 3-minute sleep and second pass addresses this.

If a file still fails to auto-import, check Activity > Queue. Remove the error entry (without deleting files) and the next rescan will pick it up fresh.

### 6.4 Syncthing Local Additions / Revert Loop

After deleting imported files locally, Syncthing tracks these as "Locally Changed Items". The seedbox cleanup cron prevents re-sync accumulation by removing files from the seedbox within 2 days. After a Revert Local Changes, only currently active content re-syncs.

### 6.5 Season Pack Imports

Season pack folders require Interactive Import in Sonarr. The automatic scanner cannot reliably map files inside a season pack to individual episodes. Use Wanted > Manual Import > navigate to the folder > Interactive Import.

### 6.6 DownloadedEpisodesScan Path Requirement

Sonarr v4.0.16+ requires a `path` parameter when calling `DownloadedEpisodesScan` via API. Always include it as shown in the rescan script.

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

After cleaning both sides, click **Revert Local Changes** in Caladan's Syncthing UI to reset state.

### 7.2 Checking Import Logs

```bash
# Recent Sonarr import activity
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30

# Check for errors
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

---

## 8. Rebuild Checklist

Complete these steps in order when rebuilding Caladan from scratch.

### 8.1 Unraid Containers

- [ ] Deploy binhex-syncthing with host networking on port 8384
- [ ] Deploy Sonarr (linuxserver/sonarr) on port 8989
- [ ] Deploy Radarr (linuxserver/radarr) on port 7878
- [ ] Deploy Lidarr (linuxserver/lidarr) on port 8686
- [ ] Configure all volume mounts per Section 4.1
- [ ] **Manually add /downloads mapping to Lidarr** (not added by default)

### 8.2 Syncthing

- [ ] Add Media sync folder with ID `sfqzb-cvm5v`
- [ ] Set folder type to **Receive Only**
- [ ] Set folder path to `/media/sync` (container path)
- [ ] Add seedbox as remote device
- [ ] Create `/mnt/user/media/download/sync/.stignore` with ignore patterns from Section 3.3
- [ ] **Verify ignore pattern order: exceptions FIRST, wildcard LAST**

### 8.3 *arr Apps

- [ ] Add rTorrent download client per Section 4.2
- [ ] Add remote path mappings per Section 4.3
- [ ] Configure quality profiles
- [ ] Verify /downloads container mount is present in all three apps

### 8.4 Seedbox

- [ ] Verify ruTorrent label save paths per Section 2.1
- [ ] Configure ratio group per Section 2.2
- [ ] Add cleanup cron job per Section 2.3
- [ ] Verify Syncthing is running and connected to Caladan device ID

### 8.5 User Scripts

- [ ] Install User Scripts plugin in Unraid
- [ ] Create `arr-rescans` script with contents from Section 5.2
- [ ] Set schedule to `*/5 * * * *`
- [ ] Test by running manually and checking `docker logs sonarr`

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*
