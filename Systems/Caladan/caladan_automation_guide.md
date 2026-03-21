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
ruTorrent/qBittorrent (Seedbox) → Syncthing → /downloads (Caladan) → Sonarr / Radarr / Lidarr → Plex
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

| Label | Save Path |
|-------|-----------|
| sonarr | /home18/scytale1953/Media-sync/sonarr/ |
| radarr | /home18/scytale1953/Media-sync/radarr/ |
| lidarr | /home18/scytale1953/Media-sync/lidarr/ |

### 2.3 Seedbox Cron

Only one cron entry is needed — the Syncthing watchdog that restarts Syncthing if it stops:

```cron
MAILTO=""
*/5 * * * * /bin/bash ~/software/cron/syncthing
```

> No cleanup cron is needed. qBittorrent handles file cleanup after 14 days seeding.

### 2.4 ruTorrent (Legacy — no longer used as download client)

ruTorrent is still installed but qBittorrent is used for all *arr downloads. If switching back to ruTorrent:

- The ratio plugin conf.php has `MAX_RATIO` set to 9999 to prevent early removal
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
- qBittorrent manages file lifecycle — files only exist in Media-sync while actively seeding
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
| Sonarr | /home18/scytale1953/Media-sync | /downloads/ |
| Radarr | /home18/scytale1953/Media-sync | /downloads/ |
| Lidarr | /home18/scytale1953/Media-sync | /downloads/ |

> **Important:** The remote path must be the base path `/home18/scytale1953/Media-sync` without the app subfolder or trailing slash. qBittorrent reports the base path and appends the category subfolder separately.
> The host must be `ibiza.seedhost.eu` (not `scytale1953.ibiza.seedhost.eu`) to match the qBittorrent connection.

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
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"

# Clean up orphaned .imported marker files for loose .mkv files
for marker in /mnt/user/media/download/sync/sonarr/*.mkv.imported; do
  [ -f "$marker" ] || continue
  mkv="${marker%.imported}"
  [ -f "$mkv" ] || rm -f "$marker"
done
for marker in /mnt/user/media/download/sync/radarr/*.mkv.imported; do
  [ -f "$marker" ] || continue
  mkv="${marker%.imported}"
  [ -f "$mkv" ] || rm -f "$marker"
done

# Check sonarr folders for suspicious files
for item in /mnt/user/media/download/sync/sonarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  SUSPICIOUS=$(find "$item" -type f \( -iname "*.exe" -o -iname "*.bat" -o -iname "*.com" -o -iname "*.scr" -o -iname "*.js" -o -iname "*.vbs" \) | wc -l)
  if [ "$SUSPICIOUS" -gt 0 ]; then
    folder=$(basename "$item")
    MSG=$(jq -n --arg msg "🚨 **Suspicious files in Sonarr download**: \`$folder\` contains $SUSPICIOUS potentially malicious file(s). Import skipped — manual review required." '{content: $msg}')
    curl -s -X POST -H "Content-Type: application/json" -d "$MSG" "$DISCORD_WEBHOOK" > /dev/null
    touch "${item}.imported"
    echo "SUSPICIOUS: $folder"
  fi
done

# Check radarr folders for suspicious files
for item in /mnt/user/media/download/sync/radarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  SUSPICIOUS=$(find "$item" -type f \( -iname "*.exe" -o -iname "*.bat" -o -iname "*.com" -o -iname "*.scr" -o -iname "*.js" -o -iname "*.vbs" \) | wc -l)
  if [ "$SUSPICIOUS" -gt 0 ]; then
    folder=$(basename "$item")
    MSG=$(jq -n --arg msg "🚨 **Suspicious files in Radarr download**: \`$folder\` contains $SUSPICIOUS potentially malicious file(s). Import skipped — manual review required." '{content: $msg}')
    curl -s -X POST -H "Content-Type: application/json" -d "$MSG" "$DISCORD_WEBHOOK" > /dev/null
    touch "${item}.imported"
    echo "SUSPICIOUS: $folder"
  fi
done

# Alert on sonarr folders stuck unimported for 2+ hours
for item in /mnt/user/media/download/sync/sonarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  if [ $(find "$item" -maxdepth 0 -mmin +120 | wc -l) -gt 0 ]; then
    folder=$(basename "$item")
    MSG=$(jq -n --arg msg "⚠️ **Sonarr**: \`$folder\` has not imported after 2+ hours" '{content: $msg}')
    curl -s -X POST -H "Content-Type: application/json" -d "$MSG" "$DISCORD_WEBHOOK" > /dev/null
    echo "Discord alert: $folder"
  fi
done

# Alert on radarr folders stuck unimported for 2+ hours
for item in /mnt/user/media/download/sync/radarr/*/; do
  [ -d "$item" ] || continue
  [ -f "${item}.imported" ] && continue
  if [ $(find "$item" -maxdepth 0 -mmin +120 | wc -l) -gt 0 ]; then
    folder=$(basename "$item")
    MSG=$(jq -n --arg msg "⚠️ **Radarr**: \`$folder\` has not imported after 2+ hours" '{content: $msg}')
    curl -s -X POST -H "Content-Type: application/json" -d "$MSG" "$DISCORD_WEBHOOK" > /dev/null
    echo "Discord alert: $folder"
  fi
done

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
  PAYLOAD=$(jq -n --arg name "DownloadedEpisodesScan" --arg path "/downloads/$folder" \
    '{name: $name, path: $path}')
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
    '{name: $name, path: $path}')
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
    '{name: $name, path: $path}')
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

### 5.3 Script Design Notes

**DownloadedEpisodesScan per folder** is the core import mechanism. Several other approaches were tested and found unreliable:

- `DownloadedEpisodesScan` with root `/downloads` path — Sonarr does not recurse into subdirectories
- `manualimport` POST API — API acknowledges but never actually moves files (bug in Sonarr v4.0.16-4.0.17)
- `RefreshMonitoredDownloads` alone — only works for queue-tracked files, ignores orphaned files

**The `.imported` marker file** prevents re-scanning already-imported folders. Without it the script triggers delete/re-import cycles every 5 minutes. Markers are automatically cleaned up when qBittorrent removes folders after 14 days.

**The `-mmin -60` timestamp check** ensures only recently synced folders are scanned, giving Syncthing enough time to fully deliver files.

**jq `--arg` payload builder** safely handles special characters in folder names (brackets, spaces) common in anime releases like `[SubsPlease] Sousou no Frieren S2 - 09 (1080p) [A3A99C65]`.

**Suspicious file detection** alerts Discord and skips import for folders containing .exe, .bat, .com, .scr, .js, or .vbs files. These indicate fake/malicious torrents.

**Discord alerts** fire when folders remain unimported after 2+ hours, providing visibility into import failures that Sonarr's "Manual Interaction Required" notification misses for orphaned files.

**To update the Discord webhook** — change only the `DISCORD_WEBHOOK` variable at the top of the script.

---

## 6. Known Issues & Workarounds

### 6.1 TorrentLeech Timezone Mismatch

TorrentLeech RSS feeds via the Cardigann indexer in Prowlarr report negative ages (e.g. -284 minutes). Cosmetic only, does not affect downloading or importing.

### 6.2 Anime Series Name Mismatches

Anime releases often use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most cases via alias matching automatically. When auto-import fails, use Wanted > Manual Import > Interactive Import. The jq payload builder in the script handles the bracket characters in SubsPlease folder names.

### 6.3 Syncthing Race Condition

When a torrent completes, qBittorrent notifies the *arr app which immediately tries to import. If Syncthing hasn't finished transferring yet, the import fails. The rescan script's 60-minute window and `.imported` marker handle this — files that were mid-sync will be caught on subsequent runs.

### 6.4 Syncthing Local Additions / Revert Loop

After deleting imported files locally, Syncthing tracks these as "Locally Changed Items". Since qBittorrent removes files after 14 days, this resolves naturally. Click Revert Local Changes when needed to reset sync state.

### 6.5 Season Pack Imports

Season pack folders require Interactive Import in Sonarr. Use Wanted > Manual Import > navigate to the folder > Interactive Import.

### 6.6 Fake/Malicious Torrents

Some releases (particularly for popular shows) contain .exe files instead of video. The rescan script detects these, sends a Discord alert, and skips import. Blocklist the release in Sonarr/Radarr so it searches for a valid release automatically.

### 6.7 Remote Path Mapping Host

The qBittorrent remote path mapping host must be `ibiza.seedhost.eu` (not `scytale1953.ibiza.seedhost.eu`). The remote path must be `/home18/scytale1953/Media-sync` without trailing slash or app subfolder — qBittorrent reports the base path only.

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

### 7.6 Resetting a Stuck Import

If a folder has a `.imported` marker but the file never actually imported:
```bash
rm "/mnt/user/media/download/sync/sonarr/FOLDERNAME/.imported"
touch "/mnt/user/media/download/sync/sonarr/FOLDERNAME/"
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
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

- [ ] Add qBittorrent download client per Section 4.2
- [ ] Add remote path mappings per Section 4.3
- [ ] Configure quality profiles
- [ ] Verify /downloads container mount is present in all three apps
- [ ] Connect Discord notifications

### 8.4 Seedbox

- [ ] Verify qBittorrent save path is `/home18/scytale1953/Media-sync/` per Section 2.1
- [ ] Verify qBittorrent seeding limits per Section 2.1
- [ ] Verify Syncthing cron is present per Section 2.3
- [ ] Verify Syncthing is running and connected to Caladan device ID

### 8.5 User Scripts

- [ ] Install User Scripts plugin in Unraid
- [ ] Create `arr-rescans` script with contents from Section 5.2
- [ ] Set `DISCORD_WEBHOOK` variable to current webhook URL
- [ ] Set schedule to `*/5 * * * *`
- [ ] Test by running manually and checking `docker logs sonarr`
- [ ] Verify Discord alert is received

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*
