# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** August 2026
**Server:** Caladan (192.168.1.12) — Unraid 7.2.4
**Hardware:** Supermicro X10SRL-F · Xeon E5-2630 v3 · 32 GiB DDR4 ECC · RTX 3060 · 68 TB array (2× parity)

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Unpackerr](#5-unpackerr)
6. [Automation Scripts](#6-automation-scripts)
7. [Known Issues & Workarounds](#7-known-issues--workarounds)
8. [Diagnostic Playbooks](#8-diagnostic-playbooks)
9. [Maintenance Procedures](#9-maintenance-procedures)
10. [Rebuild Checklist](#10-rebuild-checklist)

---

## 1. Infrastructure Overview

### Pipeline

```
qBittorrent (seedbox)
  └─> Syncthing Send Only (~/Media-sync/)
       └─> Syncthing Receive Only (/mnt/user/media/download/sync/)
            ├─> Unpackerr (RAR extraction, queue-driven)
            └─> arr-rescans -> Sonarr / Radarr / Lidarr
                 └─> /mnt/user/media/{tv,films,mp3}
                      └─> Tdarr -> Plex / Jellyfin
```

Both Syncthing sides carry an `.stignore`. The seedbox side limits what is *indexed and announced*; the Caladan side limits what is *accepted*. Both are required — see §3.3.

### Key Infrastructure

| Component | Value |
|-----------|-------|
| Caladan IP | 192.168.1.12 |
| Caladan OS | Unraid 7.2.4 (kernel 6.12.54) |
| Seedbox host | ibiza.seedhost.eu |
| Seedbox user | scytale1953 |
| Seedbox base path | /home18/scytale1953/ |
| Media sync path (seedbox) | ~/Media-sync/ |
| Media sync path (Caladan) | /mnt/user/media/download/sync/ |
| Syncthing folder ID | sfqzb-cvm5v |
| Caladan Syncthing GUI | 8384 |
| Seedbox Syncthing GUI | 9932 (127.0.0.1 only) |
| Caladan device ID | CZAA5AM-KOENLJM-VFCRXBQ-N7KCDVJ-BCHSQAU-KR646KG-5D7R4OM-3M6BTAP |
| Git repo | /MyFiles/Systems/Caladan |

### Application Ports

| App | Port | API version |
|-----|------|-------------|
| Sonarr | 8989 | v3 |
| Radarr | 7878 | v3 |
| Radarr-4K | — | v3 |
| Lidarr | 8686 | **v1** |
| Prowlarr | — | v1 |
| Plex | 32400 | — |
| Jellyfin | 8096 | — |
| Syncthing | 8384 | REST |

> **Lidarr uses `/api/v1/`, not `/api/v3/`.** Every script that touches Lidarr must use v1 or the call silently returns nothing.

### Storage Layout

SQLite-backed container appdata lives on `/mnt/cache/appdata/` (direct cache path), **not** `/mnt/user/appdata/`. Writing SQLite through Unraid's shfs FUSE layer is a known corruption vector and caused a prior incident.

| Class | Path | Containers |
|-------|------|-----------|
| SQLite-backed | /mnt/cache/appdata/ | sonarr, radarr, radarr-4k, lidarr, prowlarr, bazarr, tautulli, plex, requestrr, tdarr, open-webui |
| Stateless | /mnt/user/appdata/ | binhex-syncthing, unpackerr, others |
| Media | /mnt/user/media/ | all — **always `/mnt/user/`, never `/mnt/cache/`** |
| Tdarr temp | /mnt/cache/tdarr_temp/ | tdarr (`/media_temp`) |

> Media mounts must use `/mnt/user/` paths. A `/mnt/cache/` media mount triggers FCP cache warnings and silently misdirects import lanes.

---

## 2. Seedbox Configuration

### 2.1 qBittorrent

Web UI: `https://ibiza.seedhost.eu/scytale1953/qbittorrent/`

**Tools → Options → Downloads:**
- Default save path: `/home18/scytale1953/Media-sync/`

**Tools → Options → BitTorrent (seeding limits):**
- When ratio reaches: disabled (0)
- When seeding time reaches: 20160 minutes (14 days)
- Then: Remove torrent and files

qBittorrent's own retention drives cleanup. When it removes files at 14 days, Syncthing propagates the deletion to Caladan naturally. There is no sync-cleanup cron — that approach was retired.

> **qBittorrent pre-allocation** creates full-size zero-filled files that pass every size check. This is a real source of false "complete" signals; it is why arr-rescans uses a multi-cycle byte-signature settle guard rather than a single size test.

### 2.2 Download Categories

| Category | Save path |
|----------|-----------|
| sonarr | /home18/scytale1953/Media-sync/sonarr/ |
| radarr | /home18/scytale1953/Media-sync/radarr/ |
| lidarr | /home18/scytale1953/Media-sync/lidarr/ |

A torrent that lands outside these three subfolders will never sync — the seedbox `.stignore` excludes everything else. **First check when a completed download does not appear on Caladan: confirm the category applied.**

### 2.3 Media-sync Folder Structure

| Directory | Synced | Purpose |
|-----------|--------|---------|
| sonarr/ | **yes** | TV downloads |
| radarr/ | **yes** | Movie downloads |
| lidarr/ | **yes** | Music downloads |
| seeding/ | no | Long-term seeding store |
| freeleech/ | no | Freeleech grabs |
| prowlarr/ | no | Prowlarr test downloads |
| radarr-4k/ | no | 4K movies |
| foo/ | no | Miscellaneous |

### 2.4 Seedbox Syncthing

| Setting | Value |
|---------|-------|
| Binary | ~/bin/syncthing |
| Launch | `screen -dm -S syncthing ~/bin/syncthing` |
| Config | ~/.config/syncthing/config.xml |
| GUI address | 127.0.0.1:9932 |
| Folder type | sendonly |
| rescanIntervalS | 3600 |
| fsWatcherEnabled | true (delay 10s) |
| listenAddress | default |

Watchdog cron (`~/software/cron/syncthing`), every 5 minutes:

```bash
#!/bin/bash
if ! pgrep -u $(whoami) syncthing; then
echo "started $(date)" >> ~/.config/syncthing/syncthing_cron.log
screen -dm -S syncthing ~/bin/syncthing
sleep 5
/usr/sbin/apache2ctl -k graceful &>/dev/null
fi
```

```cron
MAILTO=""
*/5 * * * * /bin/bash ~/software/cron/syncthing
```

A healthy instance shows **three** PIDs: the `SCREEN` wrapper, the Syncthing monitor, and the main process forked a few seconds later. Three PIDs is normal, not a duplicate instance.

Getting the API key and port:

```bash
SBKEY=$(grep -o '<apikey>[^<]*' ~/.config/syncthing/config.xml | cut -d'>' -f2)
SBPORT=9932
echo "${SBKEY:0:4}"     # non-empty = key loaded
```

> Do **not** read the port from `<listenAddress>` — that is the sync protocol port (22000). The REST API answers only on the `<gui><address>` port. Empty curl output usually means an unset `$SBKEY`, not an empty result.

### 2.5 Port 22000 Bind Failures (benign)

The seedbox log contains a continuous stream of:

```
Failed to listen (TCP) (error="listen tcp 0.0.0.0:22000: bind: address already in use")
Failed to listen (QUIC) (error="listen udp 0.0.0.0:22000: bind: address already in use")
```

**This is expected and requires no action.** ibiza is a shared host and another tenant holds port 22000. Caladan's connection is verified `tcp-client` in both directions — the seedbox dials *out* and never needs to accept inbound, so the failed listener costs nothing.

Confirm with:

```bash
curl -s -H "X-API-Key: $SBKEY" "http://localhost:9932/rest/system/connections" | grep -E '"type"|"address"'
```

`"type": "tcp-client"` means direct TCP. A `relay-client` type would indicate relaying and would be worth fixing; `tcp-client` is not.

The only real cost is log noise: these messages fill the 1000-line REST log buffer and push out genuine errors. Keep that in mind when reading `/rest/system/log`.

---

## 3. Syncthing Configuration

### 3.1 Caladan Container

| Setting | Value |
|---------|-------|
| Container | binhex-syncthing |
| Image | binhex/arch-syncthing |
| Network | host |
| Web UI | 8384 |
| Config | /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml |
| Sync mount | /mnt/user/media/download/sync/ -> /media/sync |

### 3.2 Folder Configuration

| Setting | Caladan | Seedbox |
|---------|---------|---------|
| Folder ID | sfqzb-cvm5v | sfqzb-cvm5v |
| Type | Receive Only | Send Only |
| Path | /mnt/user/media/download/sync/ | ~/Media-sync |
| Rescan interval | 1 hour | 1 hour |
| fsWatcher | enabled | enabled (10s) |

### 3.3 Ignore Patterns — BOTH SIDES REQUIRED

**First match wins.** Exceptions must appear before the wildcard, and the trailing `*` must be present. A rule placed below an include directive is dead code. A missing trailing `*` silently allows unintended directories to sync.

**Caladan:** `/mnt/user/media/download/sync/.stignore`

```
!/sonarr
!/sonarr/**
!/radarr
!/radarr/**
!/lidarr
!/lidarr/**
*
```

**Seedbox:** `~/Media-sync/.stignore` — identical content.

```
!/sonarr
!/sonarr/**
!/radarr
!/radarr/**
!/lidarr
!/lidarr/**
*
```

> **The seedbox side is not optional.** Without it the Send Only side indexes the entire `Media-sync/` tree — `seeding/`, `freeleech/`, `radarr-4k/`, `prowlarr/`, `foo/` — and announces all of it. Caladan discards it on receive, so nothing corrupts, but the index bloats and full scans become slow enough to swallow filesystem-watcher events. See §7.1.

Measured impact of adding the seedbox `.stignore` (Aug 2026):

| Metric | Before | After |
|--------|--------|-------|
| Full scan duration | > 60 min | 1 min 54 s |
| globalFiles | 926 | 578 |
| globalDeleted | 43,866 | 24,230 |
| globalBytes | 464.7 GB | 242.5 GB |

Verify the patterns loaded and that only the three app folders survive:

```bash
curl -s -H "X-API-Key: $SBKEY" "http://localhost:9932/rest/db/status?folder=sfqzb-cvm5v" | grep ignorePatterns
curl -s -H "X-API-Key: $SBKEY" "http://localhost:9932/rest/db/browse?folder=sfqzb-cvm5v&levels=0" | grep '"name"'
```

Expect `"ignorePatterns": true` and exactly `sonarr`, `radarr`, `lidarr`. `ignorePatterns` is a **read-only status field** — it flips to true on its own once an `.stignore` exists; there is nothing to set directly.

### 3.4 syncstatus Helper (Caladan)

Unraid rebuilds `/root` on every boot, so a `.bashrc` alias does not survive. The helper lives on the flash drive and is copied into place by the go file.

`/boot/config/syncstatus.sh`:

```bash
#!/bin/bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY" | jq
```

Appended to `/boot/config/go`:

```bash
# Syncthing status helper
cp /boot/config/syncstatus.sh /usr/local/bin/syncstatus
chmod +x /usr/local/bin/syncstatus
```

> Avoid nested-escape `echo "alias ..." >> /root/.bashrc` constructions in the go file — the quoting is fragile and fails silently. A script file on flash plus a copy is robust.

### 3.5 Revert Local Changes — EMERGENCY ONLY

The **Revert Local Changes** button was previously routine. It is now emergency-only. Normal operation relies on natural deletion propagation from the seedbox; reverting discards local state and can force large re-transfers. Use only when Syncthing is genuinely wedged with local additions that cannot be resolved otherwise.

---

## 4. *arr Application Configuration

### 4.1 Container Mounts (verified via `docker inspect`, Aug 2026)

| App | Host path | Container path |
|-----|-----------|----------------|
| Sonarr | /mnt/user/media/download/sync/sonarr | /downloads |
| | /mnt/user/media/trash/sonarr | /trash |
| | /mnt/user/appdata/sonarr | /config |
| | /mnt/user/media/tv | /tv |
| Radarr | /mnt/user/media/download/sync/radarr | /downloads |
| | /mnt/user/media/trash/radarr | /trash |
| | /mnt/cache/appdata/radarr | /config |
| | /mnt/user/media/films | /movies |
| Lidarr | /mnt/user/media/download/sync/lidarr | /downloads |
| | /mnt/user/media/trash/lidarr | /trash |
| | /mnt/user/appdata/lidarr | /config |
| | /mnt/user/media/mp3/Rock | /music |
| Unpackerr | /mnt/user/media/download/sync | /downloads |
| | /mnt/user/media/films | /movies |

**The mount shape is app-specific and deliberate.** Each *arr sees only its own subfolder at `/downloads`. Unpackerr is the exception: it mounts the sync **root** at `/downloads`, so it addresses `/downloads/sonarr/...` and `/downloads/radarr/...`.

> Radarr's `/trash` mount was previously unverified and inferred from convention. It is now **confirmed present** in `docker inspect` output. That open item is closed.

### 4.2 Remote Path Mappings (app-specific)

| App | Remote path | Local path |
|-----|-------------|------------|
| Sonarr | /home18/scytale1953/Media-sync/sonarr/ | /downloads/ |
| Radarr | /home18/scytale1953/Media-sync/radarr/ | /downloads/ |
| Lidarr | /home18/scytale1953/Media-sync/lidarr/ | /downloads/ |

Host for all three: `ibiza.seedhost.eu`.

These mappings are **app-specific, not base-path**. The `sonarr`/`radarr`/`lidarr` segment is consumed by the mapping, so a queue item's `outputPath` reads `/downloads/<Release.Name>` with no app segment. This is correct and consistent with §4.1. The earlier base-path convention was replaced deliberately.

`arr-import-monitor`'s `host_path()` function encodes exactly this assumption and is correct as written:

```
/downloads/X  (Sonarr container)  ->  /mnt/user/media/download/sync/sonarr/X  (host)
```

### 4.3 Download Client (all *arrs)

| Setting | Value |
|---------|-------|
| Type | qBittorrent |
| Name | seedhost.eu |
| Host | ibiza.seedhost.eu |
| Port | 443 |
| URL base | /scytale1953/qbittorrent |
| SSL | yes |
| Username | scytale1953 |
| Category | sonarr / radarr / lidarr |
| Post-import category | blank |
| Remove completed | unchecked |

> Enable Advanced Settings in the dialog to reveal the URL Base field.

### 4.4 Quality Profile (HD-1080p)

- Upgrades allowed: yes
- Upgrade until: Bluray-1080p
- Order: Remux-1080p, Bluray-1080p, WEB 1080p, HDTV-1080p

> **BRRip/WEBRip watch item.** Re-encodes (observed from group Carmoz) can quietly displace native WEB-DL files when the profile maps BRRip to Bluray-1080p. Monitor quality-source parsing in Radarr.

---

## 5. Unpackerr

Handles RAR extraction in queue-driven mode. Environment (verified Aug 2026):

```
UN_SONARR_0_URL=http://192.168.1.12:8989
UN_SONARR_0_API_KEY=<key>
UN_SONARR_0_PATHS_0=/downloads/sonarr
UN_RADARR_0_URL=http://192.168.1.12:7878
UN_RADARR_0_API_KEY=<key>
UN_RADARR_0_PATHS_0=/downloads/radarr
UN_LIDARR_0_URL=
UN_LIDARR_0_API_KEY=
UN_INTERVAL=2m
UN_TIMEOUT=15s
UN_START_DELAY=20m
UN_RETRY_DELAY=5m
UN_DELETE_DELAY=5m
UN_PARALLEL=1
UN_DEBUG=false
UN_LOG_FILE=/mnt/user/appdata/unpackerr/unpackerr.log
```

**Indexed env var format is mandatory.** `golift/cnfg` silently ignores unindexed list variables — `UN_SONARR_0_PATHS` without the trailing `_0` produces no error and no paths. Confirm loading via the startup banner:

```bash
docker logs unpackerr 2>&1 | head -20
```

The banner prints `paths:["/downloads/sonarr"]`. If it shows an empty list, the env format is wrong.

### 5.1 Path Resolution Race

Unpackerr caches the resolved path when it **first tracks a queue item**, which can precede Syncthing finishing delivery. When that happens it stats a stale path forever:

```
[Sonarr] Completed item still waiting: <Release>, no extractable files found at:
/downloads/<Release> (stat err: ... no such file or directory)
```

Fix:

```bash
docker restart unpackerr
```

The restart clears the cache and re-resolves from the current queue state.

### 5.2 UN_START_DELAY Masks the Result

`UN_START_DELAY=20m` means Unpackerr waits 20 minutes after an item appears complete before attempting extraction. **After a restart, the elapsed counter resets**, so a log line reading `Waiting, pre-Queue, elapsed: 4m0s` proves nothing about whether resolution succeeded.

Wait out the full delay before concluding the restart failed. Checking too early and escalating to a mount/mapping redesign is a documented false path (Aug 2026).

### 5.3 No unrar Binary

Unpackerr uses a Go-native RAR library, not a bundled `unrar`. `docker exec unpackerr unrar` fails with "executable file not found" — this is expected and not a fault.

Neither `unrar`, `7z`, nor `cksfv` is installed on the Unraid host. **ffmpeg/ffprobe are reachable** via `docker exec` into jellyfin, tdarr, or plex — `arr-import-verify` relies on this. Install `unrar` via NerdTools if manual archive testing is needed.

---

## 6. Automation Scripts

### 6.1 Shared Config

`/boot/config/arr-rescans.conf` — sourced by all four scripts. Never committed to git.

```bash
SONARR_KEY="..."
RADARR_KEY="..."
LIDARR_KEY="..."
DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
IMPORT_ALERT_THRESHOLD=120     # 2h — sized for large 4K transfers, not the 30m script default
IMPORT_REALERT_SECONDS=28800   # 8h between re-alerts on the same stuck item
VIDEO_EXTENSIONS="mkv mp4 avi m4v"
CLEANUP_LIVE=1
VERIFY_SONARR_TOLERANCE=80     # below the 90 default — variable-length episodes cause false positives

# --- pinned defaults (previously implicit) — Aug 2026
RAR_WAIT_ALERT_MINUTES=120
SETTLE_CYCLES=1
REAP_HOURS=24
REAP_LIVE=1
CLEANUP_GRACE_DAYS=2
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

> **Empty output from an *arr API call almost always means an unsourced conf file**, not a genuinely empty result. Check `echo "${SONARR_KEY:0:4}"` before investigating anything else.

`SYNC_RETENTION_DAYS` was dead code from the retired sync-cleanup era and has been removed.

### 6.2 Schedules (verified from `schedule.json`)

Schedules live in `/boot/config/plugins/user.scripts/schedule.json`, **not** in per-script files.

| Script | Cron | Purpose |
|--------|------|---------|
| arr-rescans | `*/5 * * * *` | Trigger *arr import scans |
| arr-import-monitor | `*/15 * * * *` | Alert on stuck imports; reap stale queue entries |
| arr-cleanup | `0 4 * * *` | Remove local sync residue |
| arr-import-verify | `30 4 * * *` | Audit imports for truncation |
| Daily system summary | `0 7 * * *` | — |
| Daily arr Media Stack Review | `15 7 * * *` | Ollama log review |
| Script log summary | `30 7 * * *` | — |
| DownloadCleanupMoviesRadarr | `*/10 * * * *` | — |
| DownloadCleanupMusic-Lidarr | daily | — |

Ordering matters: `arr-cleanup` at 04:00 removes residue, then `arr-import-verify` at 04:30 audits what remains.

> `arr-import-verify`'s description string says "Daily 04:00" but the actual schedule is 04:30. Cosmetic only.

### 6.3 arr-rescans v4.6.1

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
**Schedule:** `*/5 * * * *`

Triggers `DownloadedEpisodesScan` / `DownloadedMoviesScan` per folder and per loose video file. Import detection is via the **history API** (`eventType=3`, `downloadFolderImported`) — marker files were retired.

Guard order per candidate, first match wins:

1. Empty directory → skip
2. `*sync-conflict*` → skip
3. `*_unpackerred` → skip (Unpackerr staging copy, never a valid target)
4. Already in import history → skip
5. Suspicious executables → alert once, skip
6. **Settle guard** — byte signature unchanged for `SETTLE_CYCLES` runs, else defer
7. **RAR guard** — rar set present and no settled video, else defer (alert past `RAR_WAIT_ALERT_MINUTES`)
8. Queue the scan

**Settle guard is size-based, not mtime-based, and deliberately so.** Syncthing preserves the *source* mtime on delivered files, so a file that landed thirty seconds ago can carry a timestamp hours old. Byte count is the only locally-observable signal that a transfer is still moving.

**The RAR guard's mtime check is correct in its own context** — Unpackerr writes the extracted file locally, so that mtime is local truth.

State files (all in `/tmp`, self-pruning):

| File | Purpose |
|------|---------|
| /tmp/arr-rescans-settle.state | Byte signatures, tab-delimited |
| /tmp/arr-rescans-suspicious.state | Suspicious-folder alert dedup |
| /tmp/arr-rescans-rarwait.state | RAR-wait alert dedup |

```bash
#!/bin/bash
# arr-rescans v4.6.1
# Core function: trigger *arr scans on synced download folders.
# Import detection via Sonarr/Radarr history API — no marker files required.
# Alerting on stuck imports is handled separately by arr-import-monitor.
#
# Schedule: */5 * * * *
#
# Changes from v4.6:
#   - NEW: skip *_unpackerred directories. These are Unpackerr's transient
#     extraction staging copies, not releases. The *arrs import from the
#     ORIGINAL release folder, so an _unpackerred folder is never a valid scan
#     target — and because its name never appears in import history under that
#     suffix, in_history() can never match it, so it was rescanned every cycle
#     forever (the Aug 2026 House.of.the.Dragon.S03E03 case: imported in July,
#     still generating "Folder/File specified for import scan ... doesn't
#     exist" warnings in the Sonarr log a month later).
#     Empty husks were already skipped by the v4.4 empty-dir check; this covers
#     the ones that still hold an extracted file.
#     NOTE: if these accumulate, check Unpackerr's UN_DELETE_DELAY — it is
#     supposed to remove its own extraction folder after the *arr confirms
#     the import.
#
# Changes from v4.5.2:
#   - NEW: settle guard. Refuses to scan a folder or loose file whose byte
#     signature changed since the previous run, so the *arrs are never handed
#     a release that Syncthing is still delivering (the Aug 2026 partial-import
#     pattern — a truncated .mkv imported as if whole).
#     Size-based, NOT mtime-based, and deliberately so: Syncthing preserves the
#     SOURCE mtime on delivered files, so a file that landed thirty seconds ago
#     can carry a timestamp hours old. Byte count is the only locally-observable
#     signal that the transfer is still moving.
#     Signature = "<file count>:<total bytes>" (recursive for folders). A path
#     must present the same signature for SETTLE_CYCLES consecutive runs
#     (default 1, i.e. ~5 minutes of quiet) before it is eligible to scan.
#     State lives in /tmp and self-prunes: paths not seen in a run are dropped.
#     Cost: one extra cycle of latency on a newly-seen release, including
#     releases that finished syncing long ago but have no state entry yet
#     (e.g. first run after a reboot). Bounded and self-correcting.
#   - Override SETTLE_CYCLES in arr-rescans.conf if desired. 0 disables the
#     guard without editing the script.
#
# Changes from v4.5.1:
#   - NEW: RAR-guard age alert. The guard's defer path was silent-forever:
#     a rar'd release Unpackerr never touches deferred every 5 minutes with
#     no alert (the Aug 2026 CAKES incident — Unpackerr cached a bad path
#     resolution during the seedbox/Syncthing landing race and never
#     extracted). Now, if a deferred folder's rar set has been settled for
#     RAR_WAIT_ALERT_MINUTES (default 120) with still no extracted video,
#     a deduped Discord alert fires: "awaiting unpack — check Unpackerr."
#     One alert per folder, pruned when the folder disappears.
#   - Override RAR_WAIT_ALERT_MINUTES in arr-rescans.conf if desired.
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

# v4.5.2: rar-wait alert state + threshold (override in arr-rescans.conf)
RARWAIT_STATE="/tmp/arr-rescans-rarwait.state"
touch "$RARWAIT_STATE"
RAR_WAIT_ALERT_MINUTES=${RAR_WAIT_ALERT_MINUTES:-120}

# --- SETTLE GUARD (v4.6) -----------------------------------------------------
# Consecutive runs a path must present an unchanged byte signature before it is
# eligible to scan. 1 = ~5 minutes of quiet on the */5 schedule. 0 disables.
SETTLE_CYCLES=${SETTLE_CYCLES:-1}
SETTLE_STATE="/tmp/arr-rescans-settle.state"
touch "$SETTLE_STATE"

declare -A SETTLE_PREV
declare -A SETTLE_NEW

# Load previous run's signatures. Tab-delimited: <path>\t<signature>\t<count>
while IFS=$'\t' read -r _p _sig _n; do
  [ -n "$_p" ] || continue
  SETTLE_PREV["$_p"]="${_sig}|${_n}"
done < "$SETTLE_STATE"

# "<file count>:<total bytes>", recursive for directories.
path_signature() {
  local target="$1"
  if [ -d "$target" ]; then
    find "$target" -type f -printf '%s\n' 2>/dev/null \
      | awk '{c++; b+=$1} END {printf "%d:%d", c+0, b+0}'
  else
    printf "1:%d" "$(stat -c %s "$target" 2>/dev/null || echo 0)"
  fi
}

# True when the path's signature has been stable for SETTLE_CYCLES runs.
# Always records the current signature, so the state file self-prunes: a path
# that disappears is simply never written again.
settled() {
  local target="$1" sig prev prev_sig prev_n n
  sig=$(path_signature "$target")
  prev="${SETTLE_PREV[$target]}"
  if [ -n "$prev" ]; then
    prev_sig="${prev%|*}"
    prev_n="${prev#*|}"
  else
    prev_sig=""
    prev_n=-1
  fi
  if [ -n "$prev" ] && [ "$sig" = "$prev_sig" ]; then
    n=$(( prev_n + 1 ))
  else
    n=0
  fi
  SETTLE_NEW["$target"]="${sig}|${n}"
  [ "$n" -ge "$SETTLE_CYCLES" ]
}
# --- END SETTLE GUARD --------------------------------------------------------

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
# NOTE: mtime is the right signal HERE (unlike the v4.6 settle guard) because
# Unpackarr writes the extracted file locally, so its mtime is local truth.
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

# v4.5.2: alert (once per folder, deduped) when a deferred folder's rar set has
# sat for RAR_WAIT_ALERT_MINUTES with no extracted video. A silent defer is fine
# for the normal Unpackerr window; past the threshold it means Unpackerr is
# wedged (bad cached path, dead container) and someone should look.
check_rar_wait_alert() {
  local label="$1" dir="$2" folder="$3"
  local now rar m newest=0
  now=$(date +%s)
  for rar in "${dir}"*.rar; do
    [ -f "$rar" ] || continue
    m=$(stat -c %Y "$rar")
    [ "$m" -gt "$newest" ] && newest=$m
  done
  [ "$newest" -eq 0 ] && return
  local age_min=$(( (now - newest) / 60 ))
  [ "$age_min" -lt "$RAR_WAIT_ALERT_MINUTES" ] && return
  if ! grep -qFx "$folder" "$RARWAIT_STATE"; then
    send_notification "⏳ **$label**: \`$folder\` awaiting unpack for ${age_min} minutes — rar set present, no extracted video. Check Unpackerr (docker logs unpackerr / docker restart unpackerr)."
    echo "$folder" >> "$RARWAIT_STATE"
    echo "$label RAR-WAIT alert: $folder (${age_min}m)"
  fi
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
      # v4.6.1: Unpackerr staging copy, not a release. Never a scan target.
      *_unpackerred)
        echo "$label skip (unpackerr artifact): $folder"
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

    # --- SETTLE GUARD caller (v4.6 — delete these 4 lines to disable)
    # Bytes still arriving from Syncthing: defer rather than hand the *arr a
    # partial release. Runs before the RAR guard so a still-landing rar set
    # cannot trip the rar-wait alert.
    if ! settled "$item"; then
      echo "$label defer (still settling): $folder"
      continue
    fi
    # --- END SETTLE GUARD caller

    # --- RAR GUARD caller (delete these 5 lines to disable)
    if awaiting_unpack "$item"; then
      check_rar_wait_alert "$label" "$item" "$folder"
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

      # --- SETTLE GUARD caller (v4.6 — delete these 4 lines to disable)
      # The direct fix for the Aug 2026 truncated-.mkv imports: a file still
      # growing under Syncthing changes size between runs and is deferred.
      if ! settled "$vid"; then
        echo "$label defer (still settling): $filename"
        continue
      fi
      # --- END SETTLE GUARD caller

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

# v4.6: persist this run's settle signatures. Written wholesale rather than
# appended, so paths not examined this run (imported, cleaned, or now ignored)
# drop out automatically — no separate prune step needed.
: > "${SETTLE_STATE}.tmp"
for _k in "${!SETTLE_NEW[@]}"; do
  printf '%s\t%s\t%s\n' "$_k" "${SETTLE_NEW[$_k]%|*}" "${SETTLE_NEW[$_k]#*|}" >> "${SETTLE_STATE}.tmp"
done
mv "${SETTLE_STATE}.tmp" "$SETTLE_STATE"

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

# v4.5.2: same prune for rar-wait alert state — folder gone (imported or
# cleaned) means a future re-download can alert again.
if [ -s "$RARWAIT_STATE" ]; then
  while read -r name; do
    [ -n "$name" ] || continue
    if [ -d "$SYNC_ROOT/sonarr/$name" ] || [ -d "$SYNC_ROOT/radarr/$name" ]; then
      echo "$name"
    fi
  done < "$RARWAIT_STATE" > "${RARWAIT_STATE}.tmp"
  mv "${RARWAIT_STATE}.tmp" "$RARWAIT_STATE"
fi

echo "arr-rescans v4.6.1 complete."
```

### 6.4 arr-import-monitor v1.4

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-import-monitor/script`
**Schedule:** `*/15 * * * *`

Queries all three *arr queues for items in `importPending`, `importBlocked`, or `importFailed`.

> **Import states live in `trackedDownloadState`, not `status`.** The `status` field carries download-client state (completed/downloading/queued) and never holds import states. Matching on `status` cannot fire on any stuck import — this was the v1.1 defect.

Features:
- Dedup state stamped **only on confirmed Discord delivery (HTTP 204)** — a failed send retries next run rather than being suppressed silently
- Escalating re-alerts prefixed `🔁 (alert #N — still stuck)`
- Ages ≥ 2h format as `XhYm`
- App-scoped state pruning (v1.1 wiped other apps' state)
- **Stale-queue reaper** — see below

**Stale-queue reaper.** An import completing via `DownloadedEpisodesScan` rather than the queue flow leaves its entry at `importPending`. `RefreshMonitoredDownloads` retries it every 5 minutes against a path arr-cleanup has emptied, producing endless "Import failed, path does not exist" log noise.

Reap conditions — all must hold:
- `trackedDownloadState` is exactly `importPending` (blocked/failed are actionable, never reaped)
- age ≥ `REAP_HOURS` (24)
- `outputPath` present and translatable to a host path
- that host path does **not** exist

Deletion uses `removeFromClient=false&blocklist=false` — the torrent keeps seeding and the release is not blocklisted. Anything unverifiable falls through to the alert path; never reaped on a guess.

**Status: ARMED** (`REAP_LIVE=1`, set Aug 2026). It ran dry-run from deployment until then.

```bash
#!/bin/bash

# arr-import-monitor v1.4
# Queries *arr queue APIs for items stuck in import states and sends
# Discord alerts with per-item deduplication.
# Schedule: */15 * * * *
#
# v1.4 changes:
#   - NEW: stale-queue reaper. An import that completes via
#     DownloadedEpisodesScan/DownloadedMoviesScan rather than the queue flow
#     leaves its queue entry behind at importPending. The entry survives for
#     as long as the torrent seeds, and RefreshMonitoredDownloads (fired by
#     arr-rescans every 5 min) retries it every cycle against a path
#     arr-cleanup has since emptied — producing an endless stream of
#     "Import failed, path does not exist or is not accessible" in the *arr
#     log. Two such entries were cleared by hand on 21 Aug 2026
#     (Librarians S02E02 PROPER, SNW S04E02); this automates that.
#
#     Reap conditions — ALL must hold:
#       * trackedDownloadState is exactly importPending
#         (importBlocked/importFailed are actionable and never reaped)
#       * age >= REAP_HOURS (default 24)
#       * outputPath is present and translates to a host path
#       * that host path does NOT exist
#     Deletion uses removeFromClient=false&blocklist=false, so the torrent
#     keeps seeding and the release is not blocklisted.
#
#   - DRY RUN BY DEFAULT. Set REAP_LIVE=1 in arr-rescans.conf to arm it,
#     matching the arr-cleanup v2.0 convention.
#   - Reaps are announced to Discord (not deduped — a reap happens once).
#
# v1.3 changes:
#   - FIX: record_alert now only runs on successful Discord delivery (204).
#     v1.2 stamped the dedup state regardless of outcome, so a failed
#     delivery was suppressed for the full re-alert window with nothing in
#     Discord. Failed deliveries now retry on every run (which also means
#     the Unraid fallback nags every 15 minutes until the webhook is fixed —
#     that is the point).
#   - NEW: escalating re-alerts. Alert count tracked per item; re-alerts are
#     prefixed 🔁 with the alert number, so a long-stuck item reads
#     differently from a fresh one (the Aug 2026 CAKES incident: one 4 AM
#     alert followed by 24h of suppression looked identical to silence).
#   - Ages ≥ 2h now format as XhYm instead of a raw minute count.
#   - send_notification curl gains --max-time 30 (parity with arr-rescans).
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
# REAP_HOURS=24                  # age before a stale importPending is reaped (default 24)
# REAP_LIVE=1                    # arm reaping; absent or 0 = dry run (default 0)
THRESHOLD=${IMPORT_ALERT_THRESHOLD:-30}
REALERT=${IMPORT_REALERT_SECONDS:-3600}
REAP_HOURS=${REAP_HOURS:-24}
REAP_LIVE=${REAP_LIVE:-0}
REAP_MINUTES=$(( REAP_HOURS * 60 ))

# v1.4: host-side root of the sync tree, for translating *arr container paths
SYNC_BASE="/mnt/user/media/download/sync"

STATE_FILE="/tmp/arr-import-monitor.state"
touch "$STATE_FILE"

REAPED=0
REAP_ERRORS=0

# Send Discord notification with Unraid fallback.
# v1.3: returns 0 on successful Discord delivery, 1 otherwise, so callers can
# decide whether to stamp dedup state.
send_notification() {
  local message="$1"
  local MSG=$(jq -n --arg msg "$message" '{content: $msg}')
  local HTTP_CODE=$(curl -s --max-time 30 -o /tmp/discord_response.json -w "%{http_code}" \
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
    return 1
  fi
  return 0
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

# v1.3: record how many alerts have fired for this item (escalation counter)
record_count() {
  local key="$1"
  local n="$2"
  local tmp=$(mktemp)
  grep -v "^${key}_count=" "$STATE_FILE" > "$tmp" 2>/dev/null
  echo "${key}_count=${n}" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# v1.4: drop every state entry for one item (used after a successful reap, so a
# future queue id reusing the number starts clean)
forget_state() {
  local key="$1"
  local tmp=$(mktemp)
  grep -v -e "^${key}=" -e "^${key}_first=" -e "^${key}_count=" "$STATE_FILE" > "$tmp" 2>/dev/null
  mv "$tmp" "$STATE_FILE"
}

# v1.4: translate an *arr container path to its host path.
# Every *arr maps <SYNC_BASE>/<subdir>/ to /downloads, so /downloads/X on the
# Sonarr container is <SYNC_BASE>/sonarr/X on the host.
# Echoes an empty string for anything unrecognised — callers MUST treat that as
# "cannot verify" and skip, never as "does not exist".
host_path() {
  local out="$1" subdir="$2"
  case "$out" in
    /downloads/*) echo "${SYNC_BASE}/${subdir}/${out#/downloads/}" ;;
    /downloads)   echo "${SYNC_BASE}/${subdir}" ;;
    *)            echo "" ;;
  esac
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
# Args: $1=app_name $2=base_url $3=api_key $4=api_version (default v3) $5=sync subdir
check_queue() {
  local api_ver="${4:-v3}"
  local app="$1"
  local url="$2"
  local key="$3"
  local subdir="$5"
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
    local id title status tracked_state tracked_status error_msg status_msg output_path

    id=$(echo "$record"             | jq -r '.id')
    title=$(echo "$record"          | jq -r '.title // "Unknown"')
    status=$(echo "$record"         | jq -r '.status // ""')
    tracked_state=$(echo "$record"  | jq -r '.trackedDownloadState // ""')
    tracked_status=$(echo "$record" | jq -r '.trackedDownloadStatus // ""')
    error_msg=$(echo "$record"      | jq -r '.errorMessage // ""')
    status_msg=$(echo "$record"     | jq -r '[.statusMessages[]?.messages[]?] | first // ""')
    output_path=$(echo "$record"    | jq -r '.outputPath // ""')

    # Import states live in trackedDownloadState, NOT status.
    # status holds download-client state (completed/downloading/queued/...)
    case "$tracked_state" in
      importPending|importBlocked|importFailed) ;;
      *) continue ;;
    esac

    local state_key="${app}:${id}"

    # Get first-seen time for age calculation
    local first_seen
    first_seen=$(grep "^${state_key}_first=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    if [ -z "$first_seen" ]; then
      echo "${state_key}_first=${now}" >> "$STATE_FILE"
      first_seen=$now
    fi

    local age_minutes=$(( (now - first_seen) / 60 ))

    # v1.3: readable age for long-stuck items
    local age_fmt="${age_minutes}m"
    if [ "$age_minutes" -ge 120 ]; then
      age_fmt="$(( age_minutes / 60 ))h$(( age_minutes % 60 ))m"
    fi

    # ---------------------------------------------------------------- v1.4
    # Stale-queue reaper. Only importPending, only past REAP_HOURS, only when
    # the output path is verifiable AND absent. Anything unverifiable falls
    # through to the normal alert path — never reaped on a guess.
    if [ "$tracked_state" = "importPending" ] && [ "$age_minutes" -ge "$REAP_MINUTES" ]; then
      local hp=""
      [ -n "$output_path" ] && [ "$output_path" != "null" ] && hp=$(host_path "$output_path" "$subdir")

      if [ -z "$hp" ]; then
        echo "${app}: '${title}' ${age_fmt} — outputPath unverifiable ('${output_path}'), not reaping"
      elif [ -e "$hp" ]; then
        echo "${app}: '${title}' ${age_fmt} — outputPath still on disk, not reaping"
      else
        if [ "$REAP_LIVE" -eq 1 ]; then
          local del_code
          del_code=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" -X DELETE \
            -H "X-Api-Key: $key" \
            "${url}/api/${api_ver}/queue/${id}?removeFromClient=false&blocklist=false")
          case "$del_code" in
            200|202|204)
              echo "${app}: REAPED queue id ${id} '${title}' (${age_fmt}, path gone: ${hp})"
              forget_state "$state_key"
              REAPED=$(( REAPED + 1 ))
              send_notification "🧹 **${app}**: cleared stale queue entry \`${title}\` — import completed out-of-band ${age_fmt} ago and the source path is gone. Torrent left seeding, release not blocklisted."
              continue
              ;;
            *)
              echo "${app}: REAP FAILED for id ${id} '${title}' (HTTP ${del_code}) — falling through to alert"
              REAP_ERRORS=$(( REAP_ERRORS + 1 ))
              ;;
          esac
        else
          echo "${app}: WOULD REAP queue id ${id} '${title}' (${age_fmt}, path gone: ${hp})"
          REAPED=$(( REAPED + 1 ))
          continue
        fi
      fi
    fi
    # ------------------------------------------------------------ end v1.4

    active_keys+=("$state_key")
    active_keys+=("${state_key}_first")
    active_keys+=("${state_key}_count")

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

      # v1.3: escalation — how many alerts have already fired for this item
      local alert_count
      alert_count=$(grep "^${state_key}_count=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
      alert_count=${alert_count:-0}

      local msg="${icon} **${app}**: \`${title}\` import ${label} for ${age_fmt}"
      if [ "$alert_count" -ge 1 ]; then
        msg="🔁 ${msg} (alert #$(( alert_count + 1 )) — still stuck)"
      fi
      if [ -n "$status_msg" ] && [ "$status_msg" != "null" ]; then
        msg="${msg} — ${status_msg}"
      elif [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
        msg="${msg} — ${error_msg}"
      fi

      # v1.3: only stamp dedup state on confirmed Discord delivery; a failed
      # delivery retries next run instead of being silently suppressed.
      if send_notification "$msg"; then
        record_alert "$state_key"
        record_count "$state_key" $(( alert_count + 1 ))
        echo "${app}: alerted for '${title}' (${tracked_state}, ${age_fmt}, alert #$(( alert_count + 1 )))"
      else
        echo "${app}: delivery FAILED for '${title}' — dedup not stamped, will retry next run"
      fi
    else
      echo "${app}: '${title}' (${tracked_state}, ${age_minutes}m) — suppressed, recently alerted"
    fi

  done < <(echo "$queue" | jq -c '.records[]')

  # Prune stale entries for THIS app only
  prune_state "$app" "${active_keys[@]}"
}

REAP_MODE="DRY RUN"
[ "$REAP_LIVE" -eq 1 ] && REAP_MODE="LIVE"
echo "arr-import-monitor v1.4 — reaper: $REAP_MODE (>= ${REAP_HOURS}h)"

check_queue "Sonarr" "$SONARR" "$SONARR_KEY" "v3" "sonarr"
check_queue "Radarr" "$RADARR" "$RADARR_KEY" "v3" "radarr"
check_queue "Lidarr" "$LIDARR" "$LIDARR_KEY" "v1" "lidarr"

if [ "$REAPED" -gt 0 ] || [ "$REAP_ERRORS" -gt 0 ]; then
  echo "Reaper ($REAP_MODE): $REAPED stale entr(ies), $REAP_ERRORS error(s)"
fi

echo "arr-import-monitor v1.4 complete"
```

### 6.5 arr-cleanup v2.0

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-cleanup/script`
**Schedule:** `0 4 * * *`

Removes local-only residue from the Receive Only tree: `_unpackerred` folders, extracted mkvs, stale markers, empty husks.

**The discriminator is Syncthing's global index, not marker files.** For each depth-1 entry it queries `/rest/db/file`:

| Result | Meaning | Action |
|--------|---------|--------|
| HTTP 404 | Global index never knew this object | residue — delete |
| `global.deleted == true` | Seedbox tracked it, has since deleted it | residue — delete |
| `global.deleted` false/absent | Seedbox still announces it | tracked — **skip** |
| Any other HTTP code | Ambiguous | **fail safe: treat as tracked** |

Deleting tracked files would create pinned local deletes. Deleting residue instead *resolves* pending local changes and drains the `receiveOnlyChanged` counters.

Aborts before any deletion if the Syncthing API key cannot be read or `/rest/system/ping` fails.

**Status: LIVE** (`CLEANUP_LIVE=1`), grace period 2 days.

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

### 6.6 arr-import-verify v2.2

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-import-verify/script`
**Schedule:** `30 4 * * *`

Read-only audit of recent imports for truncated or short files. Never deletes, moves, blocklists, or re-triggers — remediation is manual.

Two orthogonal detectors:

| Verdict | Meaning |
|---------|---------|
| TAIL_FAIL | Last N seconds will not decode — strong transit-truncation signal |
| SHORT_HEADER | Header duration below tolerance % of *arr expected runtime — defective source |
| TAIL_WARN | Non-fatal decoder warnings only — not a truncation signal |
| PROBE_FAIL | ffprobe could not read the file at all |
| MISSING_ON_DISK | *arr believes a file exists that does not |
| IGNORED | Matched an acknowledged pattern |

Tolerances are per-app: Sonarr 80% (lowered from the 90 default — variable-length episodes cause false positives), Radarr 95%.

Sonarr runtime resolution prefers the **per-episode** TVDB runtime over the series runtime, since series runtime is a nominal slot length.

ffmpeg is located automatically: host binary if present, otherwise `docker exec` into the first running container from `jellyfin tdarr plex`, with a longest-prefix host→container mount map built from `docker inspect`.

Useful invocations:

```bash
./script --check-deps                      # validate environment and path resolution
./script --days 7                          # manual 7-day audit, no Discord
./script --ack '*Strange New Worlds*S04E05*'   # acknowledge a known-bad file
./script --list-ignored
```

Bare invocation equals `--cron`: 2-day window, Discord on new findings only. The User Scripts plugin cannot pass arguments, so no-args must do the scheduled thing.

State and ignore lists live on `/boot` so they survive the RAM-based rootfs:

| File | Purpose |
|------|---------|
| /boot/config/arr-import-verify.ignore | Acknowledged files, one glob per line |
| /boot/config/arr-import-verify.state | Alert-once state (md5 of path+verdict) |

> Known cosmetic defect: the summary line prints `${DURATION_TOLERANCE}%` (the legacy global, 90) rather than the per-app tolerance actually applied. Detection uses the correct per-app value.

```bash
#!/bin/bash
# arr-import-verify v2.2
# Audit of Sonarr/Radarr imports for truncated or short media files.
#
# READ-ONLY. Never deletes, moves, blocklists, or re-triggers anything.
# Reports only — remediation is manual in the *arr UIs.
#
# Two detectors, deliberately orthogonal:
#   TAIL_FAIL     — last N seconds of video will not decode (transit truncation)
#   SHORT_HEADER  — duration well under *arr expected runtime (defective source)
#
# Usage:
#   ./arr-import-verify                           # BARE = cron mode: 2-day window,
#                                                 # Discord on new findings only
#   ./arr-import-verify --check-deps              # validate environment, exit
#   ./arr-import-verify --days 7                  # manual audit, no Discord
#   ./arr-import-verify --cron                    # same as bare, explicit
#   ./arr-import-verify --ack '*Strange New Worlds*S04E05*'   # stop alerting on a known-bad file
#   ./arr-import-verify --list-ignored
#
# Files:
#   /boot/config/arr-rescans.conf            API keys, Discord webhook, overrides
#   /boot/config/arr-import-verify.ignore    acknowledged files (glob per line)
#   /boot/config/arr-import-verify.state     alert-once state
#
# Path: /boot/config/plugins/user.scripts/scripts/arr-import-verify/script

set -uo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

CONF="/boot/config/arr-rescans.conf"
if [ ! -f "$CONF" ]; then
  echo "FATAL: $CONF not found. Cannot load API keys." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONF"

SONARR_URL="${SONARR_URL:-http://192.168.1.12:8989}"
RADARR_URL="${RADARR_URL:-http://192.168.1.12:7878}"

# Container-path -> host-path translation for *arr library roots.
# Overridable in arr-rescans.conf if these ever drift.
SONARR_CONTAINER_ROOT="${SONARR_CONTAINER_ROOT:-/tv}"
SONARR_HOST_ROOT="${SONARR_HOST_ROOT:-/mnt/user/media/tv}"
RADARR_CONTAINER_ROOT="${RADARR_CONTAINER_ROOT:-/movies}"
RADARR_HOST_ROOT="${RADARR_HOST_ROOT:-/mnt/user/media/films}"

TAIL_SECONDS="${VERIFY_TAIL_SECONDS:-30}"
DURATION_TOLERANCE="${VERIFY_DURATION_TOLERANCE:-90}"   # % of expected runtime (legacy/global)
SONARR_TOLERANCE="${VERIFY_SONARR_TOLERANCE:-90}"
RADARR_TOLERANCE="${VERIFY_RADARR_TOLERANCE:-95}"
TOLERANCE_OVERRIDE=""
FF_CONTAINER_CANDIDATES="${VERIFY_FF_CONTAINERS:-jellyfin tdarr plex}"

# Acknowledged / known-bad files that should never re-alert.
# One glob pattern per line; '#' comments and blank lines ignored.
IGNORE_FILE="${VERIFY_IGNORE_FILE:-/boot/config/arr-import-verify.ignore}"
# Alert-once state. Lives on /boot so it survives reboots (RAM-based rootfs).
STATE_FILE="${VERIFY_STATE_FILE:-/boot/config/arr-import-verify.state}"
# 0 = alert once per file, ever. >0 = re-alert after N days if still flagged.
REALERT_DAYS="${VERIFY_REALERT_DAYS:-0}"
CSV_KEEP_DAYS="${VERIFY_CSV_KEEP_DAYS:-30}"

CRON_MODE=0
ALWAYS_NOTIFY=0
DAYS_SET=0
ACK_PATTERN=""
LIST_IGNORED=0

DAYS=7
SINCE=""
APP="both"
LIMIT=0
DO_DISCORD=0
CHECK_DEPS_ONLY=0
FULL_DECODE=0
QUICK=0
VERBOSE=0
CSV_OUT="/tmp/arr-import-verify-$(date +%Y%m%d-%H%M%S).csv"

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

# Bare invocation (no args) == --cron. The Unraid User Scripts plugin cannot
# pass arguments, so running with no args must do the scheduled-job thing.
ORIG_ARGC=$#

while [ $# -gt 0 ]; do
  case "$1" in
    --days)       DAYS="$2"; DAYS_SET=1; shift 2 ;;
    --since)      SINCE="$2"; shift 2 ;;
    --app)        APP="$2"; shift 2 ;;
    --limit)      LIMIT="$2"; shift 2 ;;
    --tail)       TAIL_SECONDS="$2"; shift 2 ;;
    --tolerance)  TOLERANCE_OVERRIDE="$2"; shift 2 ;;
    --csv)        CSV_OUT="$2"; shift 2 ;;
    --discord)    DO_DISCORD=1; shift ;;
    --check-deps) CHECK_DEPS_ONLY=1; shift ;;
    --cron)       CRON_MODE=1; DO_DISCORD=1; shift ;;
    --always-notify) ALWAYS_NOTIFY=1; shift ;;
    --ack)        ACK_PATTERN="$2"; shift 2 ;;
    --list-ignored) LIST_IGNORED=1; shift ;;
    --full)       FULL_DECODE=1; shift ;;
    --quick)      QUICK=1; shift ;;
    --verbose|-v) VERBOSE=1; shift ;;
    --help|-h)
      sed -n '2,20p' "$0"; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$APP" in sonarr|radarr|both) ;; *) echo "--app must be sonarr, radarr, or both" >&2; exit 1 ;; esac

# --ack / --list-ignored are management shortcuts; handle and exit.
if [ -n "$ACK_PATTERN" ]; then
  touch "$IGNORE_FILE"
  if grep -Fxq "$ACK_PATTERN" "$IGNORE_FILE" 2>/dev/null; then
    echo "Already acknowledged: $ACK_PATTERN"
  else
    echo "$ACK_PATTERN" >> "$IGNORE_FILE"
    echo "Acknowledged (will no longer alert): $ACK_PATTERN"
  fi
  exit 0
fi

if [ "$LIST_IGNORED" -eq 1 ]; then
  echo "Ignore list: $IGNORE_FILE"
  if [ -f "$IGNORE_FILE" ]; then
    grep -vE '^\s*(#|$)' "$IGNORE_FILE" | nl -ba
  else
    echo "  (none)"
  fi
  exit 0
fi

# Cron runs daily; a 2-day window gives overlap so nothing slips between runs.
if [ "$ORIG_ARGC" -eq 0 ]; then
  CRON_MODE=1
  DO_DISCORD=1
fi
if [ "$CRON_MODE" -eq 1 ] && [ "$DAYS_SET" -eq 0 ]; then
  DAYS=2
fi

if [ -n "$TOLERANCE_OVERRIDE" ]; then
  SONARR_TOLERANCE="$TOLERANCE_OVERRIDE"
  RADARR_TOLERANCE="$TOLERANCE_OVERRIDE"
fi

if [ -z "$SINCE" ]; then
  SINCE=$(date -u -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)
elif [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  SINCE="${SINCE}T00:00:00Z"
fi

vlog() { [ "$VERBOSE" -eq 1 ] && echo "  . $*"; return 0; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

MISSING_BIN=0
for b in curl jq stat awk; do
  command -v "$b" >/dev/null 2>&1 || { echo "MISSING host binary: $b"; MISSING_BIN=1; }
done

check_key() {
  local name="$1" val="$2"
  if [ -z "$val" ]; then
    echo "MISSING key in $CONF: $name"
    return 1
  fi
  echo "  $name = ${val:0:4}…  (len ${#val})"
  return 0
}

FF_MODE=""
FF_CONTAINER=""
FF_FFMPEG=""
FF_FFPROBE=""

detect_ffmpeg() {
  if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
    FF_MODE="host"; FF_FFMPEG="ffmpeg"; FF_FFPROBE="ffprobe"
    return 0
  fi

  local c p_mpeg p_probe
  for c in $FF_CONTAINER_CANDIDATES; do
    docker inspect "$c" >/dev/null 2>&1 || continue
    [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ] || continue

    p_mpeg=""; p_probe=""
    for cand in ffmpeg /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/local/bin/ffmpeg /usr/bin/ffmpeg; do
      if docker exec "$c" sh -c "command -v '$cand' >/dev/null 2>&1 || [ -x '$cand' ]" 2>/dev/null; then
        p_mpeg="$cand"; break
      fi
    done
    for cand in ffprobe /usr/lib/jellyfin-ffmpeg/ffprobe /usr/local/bin/ffprobe /usr/bin/ffprobe; do
      if docker exec "$c" sh -c "command -v '$cand' >/dev/null 2>&1 || [ -x '$cand' ]" 2>/dev/null; then
        p_probe="$cand"; break
      fi
    done

    if [ -n "$p_mpeg" ] && [ -n "$p_probe" ]; then
      FF_MODE="docker"; FF_CONTAINER="$c"; FF_FFMPEG="$p_mpeg"; FF_FFPROBE="$p_probe"
      return 0
    fi
  done
  return 1
}

# Build host->container mount map for the chosen ffmpeg container.
declare -a MOUNT_SRC=() MOUNT_DST=()
load_mounts() {
  [ "$FF_MODE" = "docker" ] || return 0
  local line src dst
  while IFS=$'\t' read -r src dst; do
    [ -n "$src" ] || continue
    MOUNT_SRC+=("${src%/}")
    MOUNT_DST+=("${dst%/}")
  done < <(docker inspect -f '{{range .Mounts}}{{.Source}}{{"\t"}}{{.Destination}}{{"\n"}}{{end}}' "$FF_CONTAINER" 2>/dev/null)
}

# Longest-prefix match host path -> container path
to_ff_path() {
  local hp="$1"
  if [ "$FF_MODE" = "host" ]; then echo "$hp"; return 0; fi
  local i best=-1 bestlen=-1
  for i in "${!MOUNT_SRC[@]}"; do
    local s="${MOUNT_SRC[$i]}"
    if [ "$hp" = "$s" ] || [[ "$hp" == "$s"/* ]]; then
      if [ "${#s}" -gt "$bestlen" ]; then bestlen="${#s}"; best="$i"; fi
    fi
  done
  [ "$best" -ge 0 ] || return 1
  echo "${MOUNT_DST[$best]}${hp:${#MOUNT_SRC[$best]}}"
}

echo "=== arr-import-verify v2.2 ==="
echo "Config:   $CONF"
[ "$APP" = "radarr" ] || check_key SONARR_KEY "${SONARR_KEY:-}" || MISSING_BIN=1
[ "$APP" = "sonarr" ] || check_key RADARR_KEY "${RADARR_KEY:-}" || MISSING_BIN=1

if detect_ffmpeg; then
  if [ "$FF_MODE" = "host" ]; then
    echo "  ffmpeg:  host ($(ffmpeg -version 2>/dev/null | head -1 | cut -c1-40))"
  else
    echo "  ffmpeg:  container '$FF_CONTAINER' -> $FF_FFMPEG / $FF_FFPROBE"
    load_mounts
    echo "  mounts:  ${#MOUNT_SRC[@]} bind mounts loaded from $FF_CONTAINER"
  fi
else
  echo "  ffmpeg:  NOT FOUND (no host binary, no usable container)"
  echo "           Set VERIFY_FF_CONTAINERS in $CONF to a container that has ffmpeg+ffprobe,"
  echo "           or install ffmpeg via NerdTools."
  MISSING_BIN=1
fi

echo "  window:  since $SINCE   (apps: $APP)"
echo "  checks:  tail=${TAIL_SECONDS}s  tol(sonarr)=${SONARR_TOLERANCE}% tol(radarr)=${RADARR_TOLERANCE}%  full=${FULL_DECODE}  quick=${QUICK}"
echo

if [ "$CHECK_DEPS_ONLY" -eq 1 ]; then
  # Verify the library roots resolve inside the ffmpeg container too
  for pair in "$SONARR_HOST_ROOT" "$RADARR_HOST_ROOT"; do
    if cp=$(to_ff_path "$pair"); then
      echo "  path check: $pair -> $cp"
    else
      echo "  path check: $pair -> UNRESOLVABLE inside $FF_CONTAINER"
    fi
  done
  exit $MISSING_BIN
fi

[ "$MISSING_BIN" -eq 0 ] || { echo "Preflight failed. Run --check-deps for detail." >&2; exit 1; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

api() { # api <url> <key>
  curl -sf --max-time 30 -H "X-Api-Key: $2" "$1" 2>/dev/null
}

send_discord() {
  [ "$DO_DISCORD" -eq 1 ] || return 0
  [ -n "${DISCORD_WEBHOOK:-}" ] || return 0
  local msg="$1"
  local payload code
  payload=$(jq -n --arg msg "$msg" '{content: $msg}')
  code=$(curl -s -o /tmp/aiv_discord.json -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK")
  if [ "$code" != "204" ]; then
    /usr/local/emhttp/webGui/scripts/notify \
      -e "arr-import-verify" -s "Discord webhook error" \
      -d "HTTP $code" -i "warning" 2>/dev/null
  fi
}

# --- Ignore list -----------------------------------------------------------
# Returns 0 if the path matches an acknowledged pattern.
is_ignored() {
  local hp="$1" pat
  [ -f "$IGNORE_FILE" ] || return 1
  while IFS= read -r pat; do
    case "$pat" in ''|\#*) continue ;; esac
    pat="${pat%"${pat##*[![:space:]]}"}"   # rstrip
    [ -n "$pat" ] || continue
    # Exact match, or glob match (patterns may contain * and ?)
    if [ "$hp" = "$pat" ]; then return 0; fi
    # shellcheck disable=SC2254
    case "$hp" in $pat) return 0 ;; esac
  done < "$IGNORE_FILE"
  return 1
}

# --- Alert-once state ------------------------------------------------------
state_key() { printf '%s|%s' "$1" "$2" | md5sum | cut -d' ' -f1; }

should_alert() { # <path> <verdict> -> 0 if this should produce a Discord alert
  local key now last
  key=$(state_key "$1" "$2")
  now=$(date +%s)
  [ -f "$STATE_FILE" ] || return 0
  last=$(grep "^${key} " "$STATE_FILE" 2>/dev/null | tail -1 | awk '{print $2}')
  [ -n "$last" ] || return 0
  if [ "$REALERT_DAYS" -gt 0 ]; then
    local age=$(( (now - last) / 86400 ))
    [ "$age" -ge "$REALERT_DAYS" ] && return 0
  fi
  return 1
}

record_alert() {
  local key; key=$(state_key "$1" "$2")
  touch "$STATE_FILE"
  grep -v "^${key} " "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null
  echo "${key} $(date +%s) $2" >> "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

container_to_host() { # <app> <container path>
  local app="$1" p="$2"
  case "$app" in
    sonarr) echo "${p/#$SONARR_CONTAINER_ROOT/$SONARR_HOST_ROOT}" ;;
    radarr) echo "${p/#$RADARR_CONTAINER_ROOT/$RADARR_HOST_ROOT}" ;;
  esac
}

probe_duration() { # <host path> -> seconds (float) or empty
  local hp="$1" cp
  cp=$(to_ff_path "$hp") || return 1
  if [ "$FF_MODE" = "host" ]; then
    ffprobe -v error -show_entries format=duration -of csv=p=0 "$cp" 2>/dev/null
  else
    docker exec "$FF_CONTAINER" "$FF_FFPROBE" -v error \
      -show_entries format=duration -of csv=p=0 "$cp" 2>/dev/null
  fi
}

# Stderr patterns that indicate genuine structural damage / truncation,
# as opposed to benign codec-level grumbling (e.g. E-AC3 exponent warnings).
FATAL_RE='Invalid data found|moov atom not found|Truncat|Invalid NAL|error reading header|Failed to read|End of file|Cannot determine format|corrupt|Invalid frame size|could not find corresponding|Error opening input|No such file or directory|Error splitting the input|Invalid argument'

tail_check() { # <host path> -> prints result; returns 0=ok 1=fatal 2=warnings-only
  local hp="$1" cp out rc
  cp=$(to_ff_path "$hp") || { echo "path-unresolvable"; return 1; }

  local -a args
  if [ "$FULL_DECODE" -eq 1 ]; then
    args=(-v error -i "$cp" -map 0:v:0 -f null -)
  else
    args=(-v error -sseof "-${TAIL_SECONDS}" -i "$cp" -map 0:v:0 -f null -)
  fi

  if [ "$FF_MODE" = "host" ]; then
    out=$(ffmpeg "${args[@]}" 2>&1); rc=$?
  else
    out=$(docker exec "$FF_CONTAINER" "$FF_FFMPEG" "${args[@]}" 2>&1); rc=$?
  fi

  local flat
  flat=$(echo "$out" | tr '\n' ' ' | cut -c1-200)

  if [ $rc -ne 0 ]; then
    echo "${flat:-exit $rc}"; return 1
  fi
  if [ -n "$out" ]; then
    if echo "$out" | grep -Eqi "$FATAL_RE"; then
      echo "$flat"; return 1
    fi
    echo "warn: $flat"; return 2
  fi
  echo "OK"
  return 0
}

# ---------------------------------------------------------------------------
# Collect candidate files
# ---------------------------------------------------------------------------

declare -A SEEN
declare -a ROWS=()

TOTAL_HISTORY=0

collect_radarr() {
  local hist ids
  hist=$(api "${RADARR_URL}/api/v3/history/since?date=${SINCE}" "$RADARR_KEY")
  if [ -z "$hist" ]; then
    echo "WARN: Radarr history returned empty — check RADARR_KEY and reachability." >&2
    return
  fi
  ids=$(echo "$hist" | jq -r '
    (if type=="array" then . else .records end)[]
    | select((.eventType|tostring) == "downloadFolderImported" or (.eventType|tostring) == "3")
    | .movieId' 2>/dev/null | sort -un)

  local n; n=$(echo "$ids" | grep -c . || true)
  TOTAL_HISTORY=$((TOTAL_HISTORY + n))
  vlog "Radarr: $n distinct movies imported since $SINCE"

  local mid mf path runtime title
  for mid in $ids; do
    [ -n "$mid" ] || continue
    mf=$(api "${RADARR_URL}/api/v3/moviefile?movieId=${mid}" "$RADARR_KEY")
    path=$(echo "$mf" | jq -r '.[0].path // empty' 2>/dev/null)
    [ -n "$path" ] || { vlog "Radarr movieId $mid: no current file (deleted/upgraded away)"; continue; }
    local info; info=$(api "${RADARR_URL}/api/v3/movie/${mid}" "$RADARR_KEY")
    runtime=$(echo "$info" | jq -r '.runtime // 0' 2>/dev/null)
    title=$(echo "$info" | jq -r '.title // "unknown"' 2>/dev/null)
    ROWS+=("radarr|${title}|${path}|${runtime}|movie")
  done
}

collect_sonarr() {
  local hist ids
  hist=$(api "${SONARR_URL}/api/v3/history/since?date=${SINCE}" "$SONARR_KEY")
  if [ -z "$hist" ]; then
    echo "WARN: Sonarr history returned empty — check SONARR_KEY and reachability." >&2
    return
  fi
  ids=$(echo "$hist" | jq -r '
    (if type=="array" then . else .records end)[]
    | select((.eventType|tostring) == "downloadFolderImported" or (.eventType|tostring) == "3")
    | .episodeId' 2>/dev/null | sort -un)

  local n; n=$(echo "$ids" | grep -c . || true)
  TOTAL_HISTORY=$((TOTAL_HISTORY + n))
  vlog "Sonarr: $n distinct episodes imported since $SINCE"

  declare -A SERIES_RUNTIME
  local eid ep fid sid path runtime title
  for eid in $ids; do
    [ -n "$eid" ] || continue
    ep=$(api "${SONARR_URL}/api/v3/episode/${eid}" "$SONARR_KEY")
    fid=$(echo "$ep" | jq -r '.episodeFileId // 0' 2>/dev/null)
    [ "$fid" != "0" ] && [ -n "$fid" ] || { vlog "Sonarr episodeId $eid: no file (hasFile=false)"; continue; }
    path=$(echo "$ep" | jq -r '.episodeFile.path // empty' 2>/dev/null)
    if [ -z "$path" ]; then
      path=$(api "${SONARR_URL}/api/v3/episodefile/${fid}" "$SONARR_KEY" | jq -r '.path // empty' 2>/dev/null)
    fi
    [ -n "$path" ] || continue
    sid=$(echo "$ep" | jq -r '.seriesId // 0' 2>/dev/null)
    if [ -z "${SERIES_RUNTIME[$sid]:-}" ]; then
      local sinfo; sinfo=$(api "${SONARR_URL}/api/v3/series/${sid}" "$SONARR_KEY")
      SERIES_RUNTIME[$sid]="$(echo "$sinfo" | jq -r '.runtime // 0')|$(echo "$sinfo" | jq -r '.title // "unknown"')"
    fi
    runtime="${SERIES_RUNTIME[$sid]%%|*}"
    title="${SERIES_RUNTIME[$sid]#*|}"
    # Prefer per-episode runtime (TVDB) — series runtime is a nominal slot length
    # and produces heavy false positives on shows with variable episode lengths.
    local ep_runtime rt_src
    ep_runtime=$(echo "$ep" | jq -r '.runtime // 0' 2>/dev/null)
    if [ -n "$ep_runtime" ] && [ "$ep_runtime" != "0" ] && [ "$ep_runtime" != "null" ]; then
      runtime="$ep_runtime"; rt_src="ep"
    else
      rt_src="series"
      vlog "episodeId $eid: no per-episode runtime, falling back to series (${runtime}m)"
    fi
    local sn en
    sn=$(echo "$ep" | jq -r '.seasonNumber // 0'); en=$(echo "$ep" | jq -r '.episodeNumber // 0')
    ROWS+=("sonarr|${title} S$(printf '%02d' "$sn")E$(printf '%02d' "$en")|${path}|${runtime}|${rt_src}")
  done
}

echo "Querying history…"
[ "$APP" = "radarr" ] || collect_sonarr
[ "$APP" = "sonarr" ] || collect_radarr

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

echo "app,title,file,size_bytes,header_duration_s,expected_s,pct_of_expected,tail_result,verdict,runtime_source" > "$CSV_OUT"

n_ok=0; n_short=0; n_tail=0; n_missing=0; n_probe=0; n_checked=0; n_warn=0; n_ignored=0
declare -a FAILURES=()
declare -a ALERTS=()

printf "\n%-7s %-46s %8s %7s  %s\n" "APP" "TITLE" "HDR(s)" "PCT" "VERDICT"
printf '%.0s-' {1..100}; echo

for row in "${ROWS[@]}"; do
  IFS='|' read -r app title cpath runtime rt_src <<< "$row"
  hpath=$(container_to_host "$app" "$cpath")

  case "$app" in
    sonarr) TOL="$SONARR_TOLERANCE" ;;
    radarr) TOL="$RADARR_TOLERANCE" ;;
    *)      TOL="$DURATION_TOLERANCE" ;;
  esac

  # dedupe (multi-episode files, re-imports)
  [ -n "${SEEN[$hpath]:-}" ] && continue
  SEEN[$hpath]=1

  if [ "$LIMIT" -gt 0 ] && [ "$n_checked" -ge "$LIMIT" ]; then break; fi
  n_checked=$((n_checked + 1))

  short_title=$(echo "$title" | cut -c1-46)

  if [ ! -f "$hpath" ]; then
    verdict="MISSING_ON_DISK"; n_missing=$((n_missing + 1))
    printf "%-7s %-46s %8s %7s  %s\n" "$app" "$short_title" "-" "-" "$verdict"
    echo "$app,\"$title\",\"$hpath\",0,,,,,$verdict" >> "$CSV_OUT"
    FAILURES+=("$verdict | $app | $title")
    continue
  fi

  size=$(stat -c %s "$hpath" 2>/dev/null || echo 0)
  dur=$(probe_duration "$hpath")

  if [ -z "$dur" ] || [ "$dur" = "N/A" ]; then
    verdict="PROBE_FAIL"; n_probe=$((n_probe + 1))
    printf "%-7s %-46s %8s %7s  %s\n" "$app" "$short_title" "-" "-" "$verdict"
    echo "$app,\"$title\",\"$hpath\",$size,,,,,$verdict" >> "$CSV_OUT"
    FAILURES+=("$verdict | $app | $title | $hpath")
    continue
  fi

  dur_i=${dur%.*}
  expected=$(( ${runtime:-0} * 60 ))
  pct=""
  if [ "$expected" -gt 0 ]; then
    pct=$(awk -v d="$dur_i" -v e="$expected" 'BEGIN{printf "%.1f", d*100/e}')
  fi

  hdr_short=0
  if [ -n "$pct" ] && [ "$(awk -v p="$pct" -v t="$TOL" 'BEGIN{print (p<t)?1:0}')" = "1" ]; then
    hdr_short=1
  fi

  if [ "$QUICK" -eq 1 ]; then
    tail_res="skipped"; tail_ok=0
  else
    tail_res=$(tail_check "$hpath"); tail_ok=$?
  fi

  if [ "$QUICK" -eq 0 ] && [ "$tail_ok" -eq 1 ]; then
    verdict="TAIL_FAIL"; detail="$hpath"
  elif [ "$hdr_short" -eq 1 ]; then
    verdict="SHORT_HEADER"; detail="${pct}% of expected (${runtime}m, src=${rt_src})"
  elif [ "$QUICK" -eq 0 ] && [ "$tail_ok" -eq 2 ]; then
    verdict="TAIL_WARN"; detail=""
  else
    verdict="OK"; detail=""
  fi

  case "$verdict" in
    TAIL_FAIL|SHORT_HEADER)
      if is_ignored "$hpath"; then
        verdict="IGNORED"; n_ignored=$((n_ignored + 1))
      else
        [ "$verdict" = "TAIL_FAIL" ] && n_tail=$((n_tail + 1)) || n_short=$((n_short + 1))
        FAILURES+=("$verdict | $app | $title | $detail")
        if should_alert "$hpath" "$verdict"; then
          ALERTS+=("$verdict | $app | $title | $detail")
          record_alert "$hpath" "$verdict"
        fi
      fi
      ;;
    TAIL_WARN) n_warn=$((n_warn + 1)) ;;
    OK)        n_ok=$((n_ok + 1)) ;;
  esac

  printf "%-7s %-46s %8s %6s%%  %s\n" "$app" "$short_title" "$dur_i" "${pct:-n/a}" "$verdict"
  echo "$app,\"$title\",\"$hpath\",$size,$dur_i,$expected,${pct:-},\"$tail_res\",$verdict,$rt_src" >> "$CSV_OUT"
done

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

echo
echo "=== Summary ==="
echo "  Files checked:   $n_checked"
echo "  OK:              $n_ok"
echo "  TAIL_FAIL:       $n_tail   (tail of file will not decode — strong truncation signal)"
echo "  SHORT_HEADER:    $n_short  (header duration < ${DURATION_TOLERANCE}% of *arr expected runtime)"
echo "  TAIL_WARN:       $n_warn   (non-fatal decoder warnings only — not a truncation signal)"
echo "  IGNORED:         $n_ignored  (matched $IGNORE_FILE)"
echo "  PROBE_FAIL:      $n_probe  (ffprobe could not read the file at all)"
echo "  MISSING_ON_DISK: $n_missing"
echo "  CSV:             $CSV_OUT"

if [ ${#FAILURES[@]} -gt 0 ]; then
  echo
  echo "=== Suspect files ==="
  printf '%s\n' "${FAILURES[@]}"
  echo
  echo "Suggested next steps (NOT executed):"
  echo "  1. Play the tail directly to confirm:"
  echo "       ffmpeg -sseof -60 -i \"<file>\" -f null -"
  echo "  2. If confirmed truncated, in Sonarr/Radarr: delete the file, blocklist the release,"
  echo "     and trigger a fresh search so a different release is grabbed."
  echo "  3. Check whether the seedbox copy is intact before re-downloading — if the seedbox file"
  echo "     is complete, this was a Syncthing-delivery race, not a bad release."
fi

# ---------------------------------------------------------------------------
# Notify — only when there is something NEW to say (unless --always-notify)
# ---------------------------------------------------------------------------

if [ ${#ALERTS[@]} -gt 0 ]; then
  msg="⚠️ **arr-import-verify** — suspect imports since \`${SINCE}\`"$'\n'
  msg+="Checked ${n_checked} · TailFail ${n_tail} · ShortHeader ${n_short} · Ignored ${n_ignored}"$'\n'
  msg+="\`\`\`"$'\n'"$(printf '%s\n' "${ALERTS[@]}" | head -15)"$'\n'"\`\`\`"$'\n'
  msg+="Remediate in Sonarr/Radarr, then acknowledge with:"$'\n'
  msg+="\`--ack '<path or glob>'\`"
  send_discord "$msg"
  echo
  echo "Discord: alerted on ${#ALERTS[@]} new finding(s)."
elif [ "$ALWAYS_NOTIFY" -eq 1 ]; then
  send_discord "✅ **arr-import-verify** — ${n_checked} files checked since \`${SINCE}\`, no new issues."
  echo
  echo "Discord: all-clear sent."
else
  echo
  if [ ${#FAILURES[@]} -gt 0 ]; then
    echo "Discord: suppressed — ${#FAILURES[@]} finding(s), all previously alerted."
  else
    echo "Discord: nothing to report."
  fi
fi

# Prune old CSVs
find /tmp -maxdepth 1 -name 'arr-import-verify-*.csv' -mtime "+${CSV_KEEP_DAYS}" -delete 2>/dev/null

exit 0
```

---

## 7. Known Issues & Workarounds

### 7.1 Sending-Side Scan Contention — the Aug 2026 Ted Lasso incident

**Symptom:** A torrent completes on the seedbox, sits in the correct `sonarr/` folder, and Syncthing never picks it up. Caladan shows nothing pending.

**Root cause:** With no `.stignore` on the Send Only side, the seedbox indexed the entire `Media-sync/` tree — 43,866 tracked deletes across 926 files. Full scans took over an hour. `fsWatcherEnabled` was `true`, but **watcher-triggered scans queue behind a running full scan**, so a release completing mid-scan was never announced.

Diagnostic sequence (in order — the earlier steps are cheap):

```bash
# 1. Is the file where it should be?
find ~/Media-sync -maxdepth 2 -iname "*<release>*"

# 2. Is the SENDING side scanning or idle?
curl -s -H "X-API-Key: $SBKEY" \
  "http://localhost:9932/rest/db/status?folder=sfqzb-cvm5v" | grep -E '"state"|stateChanged'

# 3. Has it been indexed?
curl -s -H "X-API-Key: $SBKEY" \
  "http://localhost:9932/rest/db/browse?folder=sfqzb-cvm5v&prefix=sonarr&levels=0" | grep -i "<release>"

# 4. Only then look at Caladan
syncstatus
```

If `state` is `scanning` and `stateChanged` is more than a few minutes old, the scan is the blocker. **Check the sending side before Syncthing delivery, Unpackerr, or the *arr queues** — the failure was three layers upstream of where the investigation started.

Prevented by the seedbox `.stignore` (§3.3), which cut scans to under two minutes.

### 7.2 `/rest/db/scan` Blocks

`POST /rest/db/scan` does not return until the scan finishes. A hung-looking terminal is normal for a large subtree. Ctrl+C aborts the HTTP request only — **the scan continues server-side.**

### 7.3 Unpackerr Cached Path

See §5.1 and §5.2. Restart clears it; wait out `UN_START_DELAY` before judging the result.

### 7.4 Ghost Queue Entries

Recurring pattern: `importPending` items where the file has already been imported by another lane. Diagnose with a `hasFile` check:

```bash
curl -s "http://192.168.1.12:8989/api/v3/episode?seriesId=N" -H "X-Api-Key: $SONARR_KEY" | jq '.[] | {id, hasFile}'
```

> Do **not** use `/api/v3/parse` — it never populates `episodeFile`.

Now handled automatically by the arr-import-monitor reaper (§6.4).

### 7.5 Syncthing Conflict Files

`.stignore` carries a `(?d)*.sync-conflict-*` rule to prevent new conflicts. Both `scan_subfolders` and `scan_loose_files` additionally refuse conflict-named paths — belt and braces, after the Apr–Jul 2026 false-import pattern where a conflict copy was fed to the *arrs as a real release.

### 7.6 Season Pack Imports

Require Interactive Import in Sonarr: Wanted → Manual Import → folder → Interactive Import.

### 7.7 Anime & Foreign-Language Title Mismatches

Sonarr stores the TVDB canonical title regardless of the search term used when adding. For a series only available under a foreign or alternate title, submit the alias to TVDB, then refresh the series once approved. The jq `--arg` payload builder handles brackets, spaces, and apostrophes in SubsPlease-style folder names.

### 7.8 TorrentLeech Timezone Mismatch

Negative ages on grabbed releases (e.g. −284 minutes). Cosmetic only.

### 7.9 Fake / Malicious Torrents

arr-rescans detects `.exe`, `.bat`, `.com`, `.scr`, `.js`, `.vbs`, alerts once per folder, and genuinely skips the scan. Blocklist the release in Sonarr/Radarr to trigger a fresh search.

### 7.10 SQLite on shfs FUSE

All database-backed containers must use `/mnt/cache/appdata/` direct paths. To find corrupted NULLs in SQLite 3.5x:

```sql
SELECT * FROM table WHERE typeof(col)='null';
```

Standard `IS NULL` and unary-`+` workarounds are optimized away by the query planner.

---

## 8. Diagnostic Playbooks

### 8.1 "A completed download never appeared"

Work outward from the source. Each step is cheaper than the next.

| # | Check | Command | Verdict |
|---|-------|---------|---------|
| 1 | Correct folder? | `find ~/Media-sync -maxdepth 2 -iname "*<rel>*"` | Outside sonarr/radarr/lidarr → category wrong |
| 2 | Sending side idle? | `/rest/db/status` → `state`, `stateChanged` | Long-running scan → §7.1 |
| 3 | Indexed? | `/rest/db/browse?prefix=sonarr&levels=0` | Absent → scan hasn't reached it |
| 4 | Devices connected? | `/rest/system/connections` | `tcp-client` = healthy |
| 5 | Caladan pulling? | `syncstatus` | `needBytes` counting down = working |
| 6 | Files landed? | `ls -1 <folder> \| wc -l` | Compare against seedbox, minus ignored |
| 7 | Extraction? | `docker logs unpackerr --since 30m \| grep -i "<rel>"` | Stale path → §5.1 |
| 8 | Import? | `docker logs sonarr --since 1h 2>&1 \| grep -E "Imported\|Import failed"` | — |

> **Expected file-count delta.** The seedbox folder will show more entries than Caladan: `Sample/`, `*.nfo`, and similar are excluded by `.stignore`. A 17-part RAR set plus `.rar` and `.sfv` is 19 files on Caladan versus 22 on the seedbox. That gap is correct, not a partial transfer.

### 8.2 Verifying a Suspect Import by Hand

```bash
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -v error -sseof -60 \
  -i "/media/tv/<Series>/<file>.mkv" -f null -
```

Silence means the tail decodes. Errors matching the `FATAL_RE` set in arr-import-verify indicate genuine truncation. If confirmed: delete the file in Sonarr/Radarr, blocklist the release, trigger a fresh search — **and check whether the seedbox copy is intact first.** An intact seedbox copy means a delivery race, not a bad release.

### 8.3 API Returns Nothing

1. `echo "${SONARR_KEY:0:4}"` — empty means the conf was not sourced
2. Lidarr uses `/api/v1/`
3. On the seedbox, `$SBKEY` does not persist across shells or restarts — re-derive it

---

## 9. Maintenance Procedures

### 9.1 Force a Rescan

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script
```

### 9.2 Check Sync Status

```bash
syncstatus
curl -s "http://localhost:8384/rest/db/status?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY" \
  | jq '{state, needFiles, needBytes, pullErrors, errors}'
```

### 9.3 Dry-Run Cleanup

```bash
CLEANUP_LIVE=0 bash /boot/config/plugins/user.scripts/scripts/arr-cleanup/script
```

### 9.4 Manual Import Audit

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-import-verify/script --days 7
```

### 9.5 Container Mount Audit

Run after **any** mount mapping edit — a path typo fails silently.

```bash
for c in sonarr radarr radarr-4k lidarr unpackerr binhex-syncthing plex jellyfin tdarr bazarr; do
  echo "=== $c ==="
  docker inspect "$c" --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null
done
```

### 9.6 Update Credentials

```bash
nano /boot/config/arr-rescans.conf
```

Never touch the scripts for credential changes.

### 9.7 Check Import Logs

```bash
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30
docker logs radarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30
```

---

## 10. Rebuild Checklist

### 10.1 Storage

- [ ] SQLite-backed appdata on `/mnt/cache/appdata/` — sonarr, radarr, radarr-4k, lidarr, prowlarr, bazarr, tautulli, plex, requestrr, tdarr, open-webui
- [ ] Media mounts on `/mnt/user/` paths only
- [ ] Tdarr temp at `/mnt/cache/tdarr_temp/`

### 10.2 Containers

- [ ] binhex-syncthing, host networking, port 8384
- [ ] Sonarr 8989, Radarr 7878, Lidarr 8686, Prowlarr
- [ ] Unpackerr with sync **root** at `/downloads`
- [ ] Mounts per §4.1 — app-specific for the *arrs, root for Unpackerr
- [ ] Run the §9.5 audit sweep before proceeding

### 10.3 Syncthing

- [ ] Folder `sfqzb-cvm5v`, Receive Only on Caladan, Send Only on seedbox
- [ ] `.stignore` on **both** sides per §3.3
- [ ] Verify exceptions first, wildcard last, trailing `*` present
- [ ] Confirm `ignorePatterns: true` on both sides
- [ ] Confirm `/rest/db/browse&levels=0` returns exactly sonarr, radarr, lidarr
- [ ] `fsWatcherEnabled` true on the sending side
- [ ] Copy `syncstatus.sh` to flash and add the go-file lines (§3.4)

### 10.4 *arr Apps

- [ ] qBittorrent download client per §4.3
- [ ] App-specific remote path mappings per §4.2
- [ ] Quality profiles per §4.4
- [ ] Verify `/downloads` mount present in all three
- [ ] Discord notifications connected

### 10.5 Seedbox

- [ ] qBittorrent save path `/home18/scytale1953/Media-sync/`
- [ ] Seeding limit 20160 min, remove torrent and files
- [ ] Categories map to the three synced subfolders
- [ ] Syncthing watchdog cron present
- [ ] `~/Media-sync/.stignore` created

### 10.6 Scripts

- [ ] User Scripts plugin installed
- [ ] `/boot/config/arr-rescans.conf` created, `chmod 600`
- [ ] All four scripts deployed per §6
- [ ] Schedules set per §6.2
- [ ] Run each manually and confirm Discord delivery
- [ ] Confirm `arr-import-monitor` reports `reaper: LIVE`
- [ ] Confirm `arr-cleanup` reports `LIVE`
- [ ] Run `arr-import-verify --check-deps` and confirm ffmpeg resolution

---

## 11. Open Items

| Item | Status |
|------|--------|
| Lidarr scan lane in arr-rescans | **Open** — no lane exists; orphaned Lidarr folders need manual `DownloadedAlbumsScan`. Music health checking in Tdarr also outstanding. |
| Radarr `/trash` mount | **Closed** — confirmed in `docker inspect`, Aug 2026 |
| `SYNC_RETENTION_DAYS` dead code | **Closed** — removed |
| Reaper armed | **Closed** — `REAP_LIVE=1`, Aug 2026 |
| Seedbox `.stignore` | **Closed** — created Aug 2026 |
| `syncstatus` persistence | **Closed** — flash script + go file |
| Seedbox port 22000 bind noise | **Won't fix** — benign, shared-host contention (§2.5) |
| `arr-import-verify` description string | Cosmetic — says 04:00, runs 04:30 |
| `arr-import-verify` summary tolerance | Cosmetic — prints global 90, applies per-app 80/95 |

---

*Caladan Media Automation Guide — store in git at /MyFiles/Systems/Caladan*
*Never commit arr-rescans.conf — it contains live credentials*
