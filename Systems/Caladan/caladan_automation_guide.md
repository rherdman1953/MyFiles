# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** April 2026  
**Server:** Caladan (192.168.1.12) — Unraid 7.2.4

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Rescan Script](#5-rescan-script-unraid-user-scripts)
6. [Tdarr — Media Track Cleanup](#6-tdarr--media-track-cleanup)
7. [Known Issues & Workarounds](#7-known-issues--workarounds)
8. [Maintenance Procedures](#8-maintenance-procedures)
9. [Rebuild Checklist](#9-rebuild-checklist)

---

## 1. Infrastructure Overview

### Architecture

```
qBittorrent (Seedbox) → Syncthing → /downloads (Caladan) → Sonarr / Radarr / Lidarr → Plex
                                                                                         ↑
                                                         Tdarr (track cleanup) ──────────┘
```

### Key Infrastructure

| Component | Value |
|-----------|-------|
| Caladan IP | 192.168.1.12 |
| Caladan OS | Unraid 7.2.4 |
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
SYNC_RETENTION_DAYS=3
IMPORT_ALERT_THRESHOLD=120
IMPORT_REALERT_SECONDS=3600
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

To update the Discord webhook or API keys, edit only this file — never touch the script.

### 5.2 Script Location & Schedule

- **Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
- **Schedule:** `*/5 * * * *` (every 5 minutes)

### 5.3 Script Design Notes

**External config file** — API keys and Discord webhook stored in `/boot/config/arr-rescans.conf`, separate from the script. Update credentials by editing only the conf file. Never commit the conf file to git.

**send_notification function** — sends to Discord and falls back to Unraid native notification if Discord returns a non-204 response.

**DownloadedEpisodesScan per folder** — core import mechanism. Scans each subfolder individually. Also handles loose .mkv files directly.

**History API detection** — uses Sonarr/Radarr history API (`downloadFolderImported` events, eventType=3) to skip already-imported content before triggering scans. No marker files used.

**jq `--arg` payload builder** — safely handles special characters in folder names including brackets, spaces, and apostrophes common in anime and foreign language releases.

**Suspicious file detection** — alerts Discord and skips import for folders containing .exe, .bat, .com, .scr, .js, or .vbs files.

**Stale Radarr queue entries** — when imports happen via DownloadedMoviesScan rather than through the normal queue flow, Radarr may retain stale "completed" queue entries. Clear manually via Radarr → Activity → Queue or via API:
```bash
curl -s -X DELETE "http://192.168.1.12:7878/api/v3/queue/QUEUE_ID?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $RADARR_KEY"
```

---

## 6. Tdarr — Media Track Cleanup

Tdarr automatically removes non-English and non-Spanish audio and subtitle tracks from media files. It watches both the TV and Films libraries continuously and processes new files as they arrive via Syncthing.

### 6.1 Docker Container

**Image:** `ghcr.io/haveagitgat/tdarr:latest` (install via Unraid Apps)  
**Web UI:** http://192.168.1.12:8265  
**Ports:** 8265 (web UI), 8266 (server), 8267 (node)

**Required extra parameter** (add to container Extra Parameters field):
```
--runtime=nvidia
```

**Environment Variables:**

| Variable | Value |
|----------|-------|
| PUID | 99 |
| PGID | 100 |
| TZ | America/Chicago |
| UMASK_SET | 002 |
| serverIP | 0.0.0.0 |
| serverPort | 8266 |
| webUIPort | 8265 |
| internalNode | **true** (critical — must not be false) |
| inContainer | true |
| NVIDIA_VISIBLE_DEVICES | all |
| NVIDIA_DRIVER_CAPABILITIES | all |

**Volume Mappings:**

| Host Path | Container Path |
|-----------|---------------|
| /mnt/user/appdata/tdarr/server | /app/server |
| /mnt/user/appdata/tdarr/configs | /app/configs |
| /mnt/user/appdata/tdarr/logs | /app/logs |
| /mnt/cache/tdarr_temp | /temp |
| /mnt/user/media/tv | /media/tv |
| /mnt/user/media/films | /media/films |

> **Note:** `/mnt/cache/tdarr_temp` must be configured as a proper cache-only share in Unraid (Shares → tdarr_temp → Primary storage: Cache, Secondary: None, Mover action: Not used) to avoid Fix Common Problems warnings.

### 6.2 GPU Setup

Requires the **Nvidia-Driver** plugin by ich777 (install via Unraid Apps). After install, reboot and verify:

```bash
nvidia-smi                          # on host
docker exec tdarr nvidia-smi       # inside container
```

Both should show the RTX 3060.

### 6.3 Node Configuration

In Tdarr → Nodes → MyInternalNode:

| Setting | Value |
|---------|-------|
| Transcode CPU workers | 2 |
| Transcode GPU workers | 1 |
| Health Check workers | 0 |
| Auto accept successful transcodes | Enabled |

### 6.4 Libraries

Two libraries are configured:

**TV Library:**

| Setting | Value |
|---------|-------|
| Source | /media/tv |
| Transcode Cache | /temp |
| Process Library | On |
| Transcodes | On |
| Health Checks | Off |
| Scan on Start | On |
| Hourly Scan | Off (folder watch handles new files) |
| Folder Watch | On |
| Folder Watch Interval | 60 seconds |

**Films Library:** identical settings with Source `/media/films`.

Both libraries use the **English/Spanish Only - Remux** flow.

### 6.5 Flow: English/Spanish Only - Remux

The flow processes each file through the following logic:

```
Input File
    ↓
Has Non-English Audio (local plugin)
    ├── Output 2: all audio already eng/spa/und → exit as Not Required
    └── Output 1: non-kept audio found ↓
        FFmpeg: Begin Command
            ↓
        Remove Stream By Property (audio, tags.language, not_includes, eng,spa)
            ↓
        Remove Stream By Property (subtitle, tags.language, not_includes, eng,spa)
            ↓
        FFmpeg: Execute
            ↓
        Replace Original File
            ↓
        Notify Sonarr (Output 1+2 → next)
            ↓
        Notify Radarr (Output 1+2 → next)
            ↓
        Discord Notify success (local plugin)
```

The missing-languages safety branch (from Has Non-English Audio Output 2 when no kept tracks found) routes to a separate Discord Notify node with warning severity.

### 6.6 Local Plugins

Two custom local flow plugins are used. Source files are stored in the git repository.

**Has Non-English Audio** (`tdarr-plugin-hasNonEnglishAudio.js`)

Gate plugin that reads `ffProbeData.streams` directly to check audio language tags. Routes to Output 1 if non-kept audio exists AND at least one kept track is present, preventing silent files. Routes to Output 2 (Not Required) if all audio is already clean.

Install path:
```
/mnt/user/appdata/tdarr/server/Tdarr/Plugins/FlowPlugins/LocalFlowPlugins/audio/hasNonEnglishAudio/1.0.0/index.js
```

**Discord Notify** (`tdarr-plugin-discordNotify.js`)

Sends colored Discord embed notifications via webhook using curl. Severity input controls embed sidebar color (success=green, warning=yellow, error=red, info=blue). HTML entities in file paths are decoded automatically. Webhook URL is a plugin input — not hardcoded.

Install path:
```
/mnt/user/appdata/tdarr/server/Tdarr/Plugins/FlowPlugins/LocalFlowPlugins/notification/discordNotify/1.0.0/index.js
```

After copying either plugin, click **Sync node plugins** in Tdarr → Flows.

### 6.7 Key Design Decisions

**No re-encode** — the flow uses FFmpeg stream copy (remux only). Processing is fast (typically 30-120 seconds per file) and lossless — video and audio quality are unchanged.

**Not Required vs Transcode Success** — files that exit the Has Non-English Audio gate via Output 2 are marked "Not Required" by Tdarr. Files that go through the full removal chain are marked "Transcode Success". Only "Transcode Success" files are permanently done; "Not Required" files will be re-evaluated on the next scan trigger. This is by design — Hourly Scan is disabled and Folder Watch only fires on new/changed files, so "Not Required" files are effectively idle.

**Replace Original File bypasses staging** — the Replace Original File plugin writes the processed file directly in-place without going through the Tdarr staging area. Auto accept in staging has no effect on this flow.

**tags.language property path** — the Remove Stream By Property plugin resolves the property as `tags.language` (dot notation into the ffProbeData tags object). The Check Stream Property community plugin does NOT support this dot notation, which is why the custom Has Non-English Audio plugin was written instead.

**`und` (undetermined) language** — included in the keep list by default. Many older or single-language rips have no language tag on their audio track, which ffProbe reports as `und`. Removing `und` from the keep list would strip audio from otherwise clean single-language files.

### 6.8 Tdarr Maintenance

**Updating a local plugin:**
```bash
# Edit the file on Caladan
nano /mnt/user/appdata/tdarr/server/Tdarr/Plugins/FlowPlugins/LocalFlowPlugins/audio/hasNonEnglishAudio/1.0.0/index.js
# Then restart Tdarr to reload
docker restart tdarr
# Then in Tdarr UI: Flows → Sync node plugins
```

**Clearing the error/cancelled queue:**

Go to Status → Transcode: Error/Cancelled → select files → click Skip (~) to add to skiplist.

**Forcing a rescan of a specific library:**

Libraries → [library name] → Options → Scan All (Find new)

**Checking what Tdarr sees for a specific file:**

```bash
docker exec tdarr /app/Tdarr_Node/assets/app/ffmpeg/linux_x64/ffprobe \
  -v quiet -print_format json -show_streams \
  "/media/tv/Show Name/Season 01/episode.mkv" \
  2>/dev/null | jq '.streams[] | select(.codec_type == "audio" or .codec_type == "subtitle") | {codec_type, language: .tags.language}'
```

---

## 7. Known Issues & Workarounds

### 7.1 TorrentLeech Timezone Mismatch

Negative ages (e.g. -284 minutes) on grabbed releases. Cosmetic only.

### 7.2 Anime Series Name Mismatches

Releases use alternate names (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End"). Sonarr handles most via alias matching. The jq payload builder handles bracket characters in SubsPlease folder names. For unresolved mismatches, submit the alias to TVDB and refresh the series after approval.

### 7.3 Syncthing Race Condition

The rescan script retries every 5 minutes until the import is confirmed via history API, so files mid-sync will be caught on subsequent runs.

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

### 7.9 Resetting a Stuck Import

If a file failed to import and needs to be retried:
```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

### 7.10 Tdarr Re-queuing Loop

If "Not Required" files keep re-appearing in the Transcode Queue, check that **Hourly Scan is disabled** on both libraries. Hourly Scan re-evaluates all Not Required files every hour. Folder Watch is sufficient for new file detection and does not cause re-queuing.

### 7.11 Tdarr internalNode=false

If the Tdarr Nodes page shows no nodes, the container was likely deployed with `internalNode=false` (the Apps template default). Fix: Docker → Edit Tdarr container → set `internalNode` environment variable to `true` → Apply.

### 7.12 Tdarr FFmpeg Timestamp Errors

Very old MKV files (pre-2012, XVID codec, mkvmerge < v4) may have unset timestamps that cause FFmpeg stream copy to fail with "Can't write packet with unknown timestamp". These files should be added to the Tdarr skiplist (Status → Error/Cancelled → ~ button).

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

### 8.8 Verifying Tdarr Track Removal

After Tdarr processes a file, verify the result:

```bash
docker exec tdarr /app/Tdarr_Node/assets/app/ffmpeg/linux_x64/ffprobe \
  -v quiet -print_format json -show_streams \
  "/media/tv/Show (Year)/Season 01/episode.mkv" \
  2>/dev/null | jq '.streams[] | select(.codec_type == "audio" or .codec_type == "subtitle") | {codec_type, language: .tags.language}'
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
- [ ] Install Nvidia-Driver plugin (Unraid Apps → ich777)
- [ ] Reboot after Nvidia-Driver install
- [ ] Verify `nvidia-smi` works on host
- [ ] Deploy Tdarr (ghcr.io/haveagitgat/tdarr) per Section 6.1
- [ ] **Add `--runtime=nvidia` to Tdarr Extra Parameters**
- [ ] **Set `internalNode=true` in Tdarr environment variables**
- [ ] Verify `docker exec tdarr nvidia-smi` shows RTX 3060

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

### 9.4 Seedbox

- [ ] Verify qBittorrent save path is `/home18/scytale1953/Media-sync/`
- [ ] Verify qBittorrent seeding limits (20160 min, remove torrent and files)
- [ ] Verify Syncthing cron is present
- [ ] Verify Syncthing connected to Caladan device ID

### 9.5 User Scripts

- [ ] Install User Scripts plugin in Unraid
- [ ] Create `/boot/config/arr-rescans.conf` with API keys and Discord webhook
- [ ] `chmod 600 /boot/config/arr-rescans.conf`
- [ ] Create `arr-rescans` script
- [ ] Set schedule to `*/5 * * * *`
- [ ] Test by running manually
- [ ] Verify Discord alert received

### 9.6 Tdarr

- [ ] Create `tdarr_temp` share (Cache only, no mover)
- [ ] Verify node is active (Nodes page shows MyInternalNode)
- [ ] Set node workers: CPU Transcode=2, GPU Transcode=1, Health Check=0
- [ ] Enable Auto accept successful transcodes
- [ ] Install local plugins from git repo:
  - [ ] Copy `tdarr-plugin-hasNonEnglishAudio.js` → `LocalFlowPlugins/audio/hasNonEnglishAudio/1.0.0/index.js`
  - [ ] Copy `tdarr-plugin-discordNotify.js` → `LocalFlowPlugins/notification/discordNotify/1.0.0/index.js`
- [ ] Click **Sync node plugins** in Flows page
- [ ] Verify both plugins appear under Local tab in flow editor
- [ ] Recreate **English/Spanish Only - Remux** flow per Section 6.5
- [ ] Create TV library (source: /media/tv, cache: /temp)
- [ ] Create Films library (source: /media/films, cache: /temp)
- [ ] Attach flow to both libraries
- [ ] Enable Folder Watch on both libraries, disable Hourly Scan
- [ ] **Scan All (Find new)** on both libraries
- [ ] Verify Discord notification received on first processed file

---

*Caladan Media Automation Guide — store in git repository for rebuild reference*  
*Files never committed to git: arr-rescans.conf (credentials), tdarr flow variables (webhook URL)*
