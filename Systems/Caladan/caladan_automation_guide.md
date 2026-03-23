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

### 5.3 Script Contents

```bash
#!/bin/bash

# Load external config - API keys and webhook URL
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

# Clean up orphaned .imported and .first_seen marker files for loose .mkv files
for marker in /mnt/user/media/download/sync/sonarr/*.mkv.imported \
              /mnt/user/media/download/sync/sonarr/*.mkv.first_seen; do
  [ -f "$marker" ] || continue
  base="${marker%.imported}"
  base="${base%.first_seen}"
  [ -f "$base" ] || rm -f "$marker"
done
for marker in /mnt/user/media/download/sync/radarr/*.mkv.imported \
              /mnt/user/media/download/sync/radarr/*.mkv.first_seen; do
  [ -f "$marker" ] || continue
  base="${marker%.imported}"
  base="${base%.first_seen}"
  [ -f "$base" ] || rm -f "$marker"
done

# Check sonarr folders for suspicious files
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

# Check radarr folders for suspicious files
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

# Alert on sonarr folders stuck unimported for 2+ hours
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

# Alert on radarr folders stuck unimported for 2+ hours
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
  if [ $(find "$item" -maxdepth 2 -mmin -60 -not -name ".imported" -not -name ".first_seen" | wc -l) -eq 0 ]; then
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
  if [ $(find "$item" -maxdepth 2 -mmin -60 -not -name ".imported" -not -name ".first_seen" | wc -l) -eq 0 ]; then
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
  if [ ! -f "${mkv}.first_seen" ]; then
    touch "${mkv}.first_seen"
  fi
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
  if [ ! -f "${mkv}.first_seen" ]; then
    touch "${mkv}.first_seen"
  fi
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

### 5.4 Script Design Notes

**External config file** — API keys and Discord webhook stored in `/boot/config/arr-rescans.conf`, separate from the script. Update credentials by editing only the conf file. Never commit the conf file to git.

**send_notification function** — sends to Discord and falls back to Unraid native notification if Discord returns a non-204 response. Covers invalid webhook URL, network issues, and rate limiting.

**DownloadedEpisodesScan per folder** — core import mechanism. Several other approaches tested and found unreliable (see Known Issues section).

**`.imported` marker file** — prevents re-scanning already-imported folders, avoiding delete/re-import cycles every 5 minutes.

**`.first_seen` marker file** — reliable 2-hour import delay detection. Directory mtimes are unreliable on Unraid's filesystem so a marker file timestamp is used instead.

**`-mmin -60` timestamp check** — only recently synced folders are scanned, giving Syncthing time to fully deliver files.

**jq `--arg` payload builder** — safely handles special characters in folder names (brackets, spaces) common in anime releases.

**Suspicious file detection** — alerts Discord and skips import for folders containing .exe, .bat, .com, .scr, .js, or .vbs files.

---

## 6. Known Issues & Workarounds

### 6.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 6.2 Anime Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most via alias matching. The jq payload builder handles bracket characters in SubsPlease folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 6.3 Syncthing Race Condition

The rescan script's 60-minute window and `.imported` marker handle timing races. Files mid-sync on first pass are caught on subsequent runs.

### 6.4 Syncthing Local Additions

After deleting imported files locally, Syncthing tracks these as "Locally Changed Items". Click Revert Local Changes to reset when needed.

### 6.5 Season Pack Imports

Require Interactive Import in Sonarr. Use Wanted > Manual Import > folder > Interactive Import.

### 6.6 Fake/Malicious Torrents

The rescan script detects .exe and other suspicious files, sends a Discord alert, and skips import. Blocklist the release in Sonarr/Radarr to trigger a search for a valid release.

### 6.7 Remote Path Mapping Host

qBittorrent remote path mapping host must be `ibiza.seedhost.eu`. Remote path must be `/home18/scytale1953/Media-sync` without trailing slash or app subfolder.

### 6.8 Resetting a Stuck Import

If a folder has an `.imported` marker but the file never actually imported:
```bash
rm "/mnt/user/media/download/sync/sonarr/FOLDERNAME/.imported"
touch "/mnt/user/media/download/sync/sonarr/FOLDERNAME/"
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

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
- [ ] Create `arr-rescans` script per Section 5.3
- [ ] Set schedule to `*/5 * * * *`
- [ ] Test by running manually
- [ ] Verify Discord alert received

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*
*Note: Never commit arr-rescans.conf to git — it contains sensitive credentials*
