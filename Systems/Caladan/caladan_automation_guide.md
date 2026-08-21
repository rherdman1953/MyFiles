# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** 21 August 2026
**Server:** Caladan (192.168.1.12) — Unraid 7.2.4
**Hardware:** Supermicro X10SRL-F · Xeon E5-2630 v3 · 32 GiB DDR4 ECC · GeForce RTX 3060
**Array:** 46.6 TB used of 68 TB · Cache: 102 GB of 1 TB

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Unpackerr](#5-unpackerr)
6. [Automation Scripts](#6-automation-scripts)
7. [Known Issues & Workarounds](#7-known-issues--workarounds)
8. [Triage Procedures](#8-triage-procedures)
9. [Maintenance Procedures](#9-maintenance-procedures)
10. [Rebuild Checklist](#10-rebuild-checklist)
11. [Open Items](#11-open-items)

---

## 1. Infrastructure Overview

### 1.1 Pipeline

```
qBittorrent (seedbox)
      ↓  torrent completes, files land in ~/Media-sync/<category>/
Syncthing (Send Only → Receive Only)
      ↓  delivers to /mnt/user/media/download/sync/<category>/
Unpackerr  ────────────► extracts RAR sets (queue-driven, via *arr queue state)
      ↓
arr-rescans (*/5 min)   ─► guard chain → DownloadedEpisodesScan / DownloadedMoviesScan
      ↓
Sonarr / Radarr / Lidarr  ─► import to /mnt/user/media/{tv,films,mp3}
      ↓
Tdarr (transcode) → Plex / Jellyfin
      ↓
arr-cleanup (daily) ─► removes imported files from sync folders
```

Deletion propagates **from the seedbox side** at the 14-day seeding expiry. Caladan
never originates a delete inside the Syncthing folder (see §3.5).

### 1.2 Key Infrastructure

| Component | Value |
|-----------|-------|
| Caladan IP | 192.168.1.12 |
| Caladan OS | Unraid 7.2.4 (kernel 6.12.54) |
| Seedbox Host | ibiza.seedhost.eu |
| Seedbox User | scytale1953 |
| Seedbox Base Path | /home18/scytale1953/ |
| Media Sync Path (seedbox) | ~/Media-sync/ |
| Media Sync Path (Caladan) | /mnt/user/media/download/sync/ |
| Syncthing Folder ID | sfqzb-cvm5v |
| Syncthing Version | v2.1.3 |
| Caladan Syncthing Port | 8384 |

### 1.3 Appdata Placement

SQLite-backed containers live on `/mnt/cache/appdata/` to keep shfs FUSE out of the
write path — this was the fix for the August 2026 Radarr SQLite corruption incident.

| On `/mnt/cache/appdata/` | On `/mnt/user/appdata/` |
|--------------------------|--------------------------|
| sonarr, radarr, radarr-4k, lidarr, prowlarr, bazarr, tautulli, plex, requestrr, tdarr, open-webui | unpackerr, apprise, dozzle, glances, Krusader, FileZilla, posterr, Pulsarr, CloudBerryBackup, big-blob mounts |

---

## 2. Seedbox Configuration (seedhost.eu)

### 2.1 qBittorrent

Available at `https://ibiza.seedhost.eu/scytale1953/qbittorrent/`

**Tools → Options → Downloads:**

| Setting | Value | Rationale |
|---------|-------|-----------|
| Default Save Path | `/home18/scytale1953/Media-sync/` | |
| Torrent content layout | Original | |
| **Pre-allocate disk space for all files** | **OFF** | **Critical.** See below. |
| **Append `.!qB` extension to incomplete files** | **ON** | **Critical.** See below. |
| Keep unselected files in `.unwanted` folder | ON | excluded in `.stignore` |
| Keep incomplete torrents in | *not available on this host* | see note |
| Delete .torrent files afterwards | ON | |

> **Pre-allocation must stay OFF.** With it enabled, qBittorrent creates each file at
> its full final size before any content arrives. Syncthing then replicates a
> full-size file whose unwritten regions are zeros — a file that passes every
> size check in the pipeline and plays until it hits the hole. This was the root
> cause of the August 2026 truncated-import incidents. With pre-allocation off,
> a partially-delivered file is visibly short and gets rejected.

> **`.!qB` suffix is the incomplete-file gate.** Since this host does not expose a
> separate incomplete-downloads directory, the suffix is what keeps in-flight files
> out of the synced namespace: an incomplete file carries `.!qB`, which `.stignore`
> excludes, and the real filename only appears once the file is whole. Applies to
> newly-added torrents only, not ones already seeding.

**Tools → Options → BitTorrent (Seeding Limits):**

- When ratio reaches: disabled (0)
- When seeding time reaches: 20160 minutes (14 days)
- Then: **Remove torrent and files**

This 14-day expiry is the upstream trigger for the whole cleanup lifecycle.

### 2.2 Download Categories

Save paths must be **explicitly saved** in the WebUI — merely displaying them leaves
the API reporting empty paths.

| Category | Save Path |
|----------|-----------|
| sonarr | /home18/scytale1953/Media-sync/sonarr/ |
| radarr | /home18/scytale1953/Media-sync/radarr/ |
| lidarr | /home18/scytale1953/Media-sync/lidarr/ |

### 2.3 Seedbox Cron

```cron
MAILTO=""
*/5 * * * * /bin/bash ~/software/cron/syncthing
```

### 2.4 Media-sync Folder Structure

| Directory | Synced? |
|-----------|---------|
| sonarr/ | yes |
| radarr/ | yes |
| lidarr/ | yes |
| freeleech/ | no — ignored |
| prowlarr/ | no — ignored |
| radarr-4k/ | no — ignored |
| foo/ | no — ignored |

Ignored directories still exist on both sides and are used for manual downloads.
Once ignored, Syncthing stops tracking them: local copies persist, and seedbox-side
deletions no longer propagate. They are managed by hand from that point on.

### 2.5 ruTorrent (legacy — not in use)

Still installed; qBittorrent handles all *arr downloads. If reverting: ratio plugin
`MAX_RATIO` is 9999 at
`~/www/scytale1953.ibiza.seedhost.eu/scytale1953/rutorrent/plugins/ratio/conf.php`.

---

## 3. Syncthing Configuration

### 3.1 Container

| Setting | Value |
|---------|-------|
| Container Name | binhex-syncthing |
| Image | binhex/arch-syncthing |
| Network Mode | host |
| Web UI Port | 8384 |
| Sync Mount | /mnt/user/media/download/sync/ → /media/sync |

### 3.2 Folder Configuration

| Setting | Value |
|---------|-------|
| Folder ID | sfqzb-cvm5v |
| Folder Name | Media sync |
| Caladan Path | /media/sync (container) |
| Seedbox Path | ~/Media-sync/ |
| Folder Type (Caladan) | **Receive Only** |
| Folder Type (seedbox) | Send Only |
| Rescan Interval | **0 (disabled)** — watcher-driven only |
| File Pull Order | Random |

Because periodic rescan is disabled, `.stignore` changes do **not** apply on a timer.
Force a rescan after editing (§9.5).

### 3.3 Ignore Patterns

File: `/mnt/user/media/download/sync/.stignore`

**Ordering is load-bearing: first match wins, so every exclusion must precede the
`!` includes, and the file must end with `*`.** Without the trailing `*`, unmatched
paths default to *not ignored*, which silently makes all the `!` include lines
no-ops and syncs every sibling directory.

```
// Exclusions MUST precede the ! includes — first match wins
// (?d) = ignore, but allow Syncthing to delete when removing a parent dir
(?d)(?i)*sample*
(?d)(?i)screens
(?d)*.nfo
(?d)*.srr
(?d)*.sync-conflict-*
// qBittorrent in-flight files. With "Append .!qB" enabled, an incomplete file
// carries the suffix until the last byte lands, so the real name only appears
// once the file is whole. Unscoped = matches at any depth, covering both loose
// single-file torrents and files inside release folders.
(?d)*.!qB
// qBittorrent parks unselected files here ("Keep unselected files" is enabled)
(?d).unwanted
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

**Pattern rules learned the hard way:**

- Comments use `//`.
- Recursive patterns (`/sonarr/**/*.jpg`) do **not** match files at the tree root.
  Both root-level (`/sonarr/*.jpg`) and recursive forms are required.
- `(?d)` permits Syncthing to delete an ignored file when removing its parent
  directory — without it, ignored files block parent deletion.
- `(?i)` is case-insensitive.
- **Do not add a `.syncthing.*.tmp` pattern.** Syncthing handles its own temp files
  internally and never indexes them, so the pattern is redundant here. It would also
  have no effect on the consumers that do see those files: arr-cleanup globs the
  filesystem directly and never reads `.stignore`, and arr-rescans cannot match them
  because its loose-file glob is `*.<video ext>` and a temp file ends in `.tmp`.
  arr-cleanup's existing behaviour is already correct — an active temp file sits
  inside the grace window, and an orphaned one older than `CLEANUP_GRACE_DAYS`
  resolves to `residue` and is removed.

**Verification after deploying (August 2026 baseline):**

```
Global State: 1,027 files / ~488 GiB
Local State:    425 files / ~162 GiB   "Reduced by ignore patterns"
```

The gap is the ignored directories. `ignorePatterns: true` and `errors: 0` in
`rest/db/status` confirm the file parsed.

### 3.4 API Access

The Syncthing API key is read from `config.xml`:

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/user/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
echo "len=${#STKEY} first4=${STKEY:0:4}"
```

This is the path arr-cleanup v2.0 depends on (§6.3). **Confirm it resolves** — a
`len=0` result means arr-cleanup aborts at its FATAL check every run.

> **A doubled `config/config/` in the path is a common typo** and produces a silent
> 403 whose HTML body then breaks every downstream `jq` with
> `parse error: Invalid numeric literal at line 2, column 0`. If the grep returns
> empty for any reason, take the key from the UI instead: Actions → Settings →
> General → API Key.

```bash
STKEY='<key>'
# Always verify before use — a 403 returns HTML and breaks every downstream jq:
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:8384/rest/system/ping" -H "X-API-Key: $STKEY"
curl -s "http://localhost:8384/rest/db/status?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY" \
  | jq '{localFiles, localBytes, globalFiles, globalBytes, receiveOnlyChangedFiles, ignorePatterns, state, errors}'
```

### 3.5 Receive Only Semantics — Critical

**Never delete files locally from a Receive Only folder.** Syncthing re-downloads
them and creates `sync-conflict-*` copies, which the *arrs then import as if they
were fresh releases. Thirteen such false imports occurred between May and August
2026 before the v4.5 guard was added.

- Deletion must propagate **from the seedbox side**.
- `receiveOnlyChangedFiles` / `receiveOnlyChangedBytes` are **flow metrics, not
  stock**. A large count is normal — it reflects arr-cleanup's pinned-delete
  lifecycle, not a fault.
- **Revert Local Changes is emergency-only.** With ~424 of 425 files flagged as
  locally-changed (the normal steady state), pressing it would delete the entire
  local tree.

Files created *locally* by containers — e.g. Unpackerr's `*_unpackerred` staging
folders — are **not tracked** by Syncthing and can be removed directly. Confirm
first:

```bash
curl -s "http://localhost:8384/rest/db/file?folder=sfqzb-cvm5v&file=sonarr/<name>" \
  -H "X-API-Key: $STKEY" | jq -r '.global.deleted? // "not tracked"'
```

---

## 4. *arr Application Configuration

### 4.1 Docker Path Mappings

| App | Host Path | Container Path | Port |
|-----|-----------|---------------|------|
| Sonarr | /mnt/user/media/download/sync/sonarr/ | /downloads | 8989 |
| Radarr | /mnt/user/media/download/sync/radarr/ | /downloads | 7878 |
| Lidarr | /mnt/user/media/download/sync/lidarr/ | /downloads | 8686 |

Media library mounts:

- Sonarr: `/mnt/user/media/tv/` → `/tv`
- Radarr: `/mnt/user/media/films/` → `/movies`
- Lidarr: `/mnt/user/media/mp3/Rock/` → `/music`

> Lidarr does not include a `/downloads` mapping by default — add it manually.

### 4.2 Download Client (all *arrs)

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

> Enable Advanced Settings to see the URL Base field.

### 4.3 Remote Path Mappings

| App | Remote Path (seedbox) | Local Path (container) |
|-----|-----------------------|------------------------|
| Sonarr | /home18/scytale1953/Media-sync/sonarr/ | /downloads/ |
| Radarr | /home18/scytale1953/Media-sync/radarr/ | /downloads/ |
| Lidarr | /home18/scytale1953/Media-sync/lidarr/ | /downloads/ |

> Mappings are app-specific — each app's category subfolder maps to its own
> `/downloads`. Host must be `ibiza.seedhost.eu`.

### 4.4 API Versions

Sonarr and Radarr use `/api/v3/`. **Lidarr uses `/api/v1/`** — a v3 call against
Lidarr fails silently.

### 4.5 Quality Profile — HD-1080p (Radarr)

Ranked low → high; **cutoff = Bluray-1080p (id 7)**; upgrades allowed.

| Rank | Quality |
|------|---------|
| 4 (highest) | Remux-1080p (id 30) |
| 3 | Bluray-1080p (id 7) ← cutoff |
| 2 | **WEB 1080p** — *group* containing WEBRip-1080p + WEBDL-1080p |
| 1 (lowest) | HDTV-1080p (id 9) |

**Custom Format: `BRRip/WEBRip Re-encode` — score `-1000`**

Release Title regex: `\b(BRRip|BDRip|WEBRip)\b`

> **Why this exists.** Radarr parses **BRRip** as Bluray-1080p, which outranks WEBDL,
> so BRRip HEVC re-encodes were "legitimately" replacing native AMZN WEB-DL files
> across the library (Backrooms, Mandalorian, Disclosure Day, Project Hail Mary,
> Michael, The Bride, Super Mario Galaxy, Avatar, Toy Story 5). Separately, because
> **WEB 1080p is a group**, WEBRip and WEBDL are treated as equal quality, so a
> WEBRip could displace a WEBDL on a coin-flip. The −1000 score blocks both classes
> while leaving genuine Bluray/Remux releases untouched.

Verify the format actually fires:

```bash
curl -s -H "X-Api-Key: $RADARR_KEY" \
  "http://192.168.1.12:7878/api/v3/parse?title=<url-encoded-release-title>" \
  | jq '{quality: .parsedMovieInfo.quality.quality.name, customFormats: [.customFormats[]?.name], score: .customFormatScore}'
```

**Optional hardening:** setting the cutoff to `WEB 1080p` stops Radarr searching for
upgrades once a WEB-DL lands — currently ~300 legacy files sit below cutoff and are
re-searched every RSS cycle.

---

## 5. Unpackerr

Handles RAR extraction. Queue-driven: it acts on *arr queue state, not on filesystem
events, for its primary mode.

### 5.1 Environment

| Variable | Value | Notes |
|----------|-------|-------|
| `UN_SONARR_0_PATHS_0` | /downloads/sonarr | **`_0` index suffix required** |
| `UN_RADARR_0_PATHS_0` | /downloads/radarr | **`_0` index suffix required** |
| `UN_INTERVAL` | 2m | |
| `UN_START_DELAY` | 20m | raised from 5m, Aug 2026 |
| `UN_RETRY_DELAY` | 5m | |
| `UN_LOG_FILE` | /mnt/user/appdata/unpackerr/unpackerr.log | moved out of the sync tree |

> **The `_0` suffix on `PATHS` is mandatory.** Omitting it causes a silent fallback
> to `/downloads` and extraction never fires.

> **`UN_LOG_FILE` must not point inside the sync tree.** Rotated logs previously
> accumulated at the sync root.

### 5.2 Extraction Lifecycle

1. *arr queue item reaches completed → Unpackerr waits `UN_START_DELAY`.
2. Extracts the RAR set into `<release>_unpackerred/`.
3. The *arr imports from that folder.
4. Unpackerr deletes its staging folder after import (`UN_DELETE_DELAY`).
5. The original RAR set remains until arr-cleanup / seedbox expiry.

**Steps 4 is unreliable in practice** — 16 orphaned `*_unpackerred` folders
accumulated between July and August 2026. arr-rescans v4.6.1 skips them (§6.1); see
§11 for the outstanding `UN_DELETE_DELAY` investigation.

### 5.3 Queue-driven vs. folder-watch

Manually dropped archives have no queue entry and will not trigger the primary mode.
Folder-watch (`PATHS_0`) is inotify-driven and may miss pre-existing files or
same-filesystem moves. Workaround: drop outside the watched folder first, then move
in.

---

## 6. Automation Scripts

All at `/boot/config/plugins/user.scripts/scripts/`.

### 6.0 Shared Config

`/boot/config/arr-rescans.conf` — sourced by every script before any API call.
Persists across reboots. **Never committed to git.**

```bash
SONARR_KEY="..."
RADARR_KEY="..."
LIDARR_KEY="..."
DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
VIDEO_EXTENSIONS="mkv mp4 avi m4v"
# optional overrides:
# RAR_WAIT_ALERT_MINUTES=120
# SETTLE_CYCLES=1
```

```bash
chmod 600 /boot/config/arr-rescans.conf
```

> Empty API output from an *arr almost always means an unsourced conf file.
> Check `echo "${SONARR_KEY:0:4}"` first.

### 6.1 arr-rescans v4.6.1 — every 5 minutes

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-rescans/script`
**Schedule:** `*/5 * * * *`

Triggers *arr scan commands against synced download folders. Import detection is via
the Sonarr/Radarr history API (`eventType=3`, `pageSize=1000`, fetched once per run)
— no marker files.

**Guard chain, in order:**

| # | Guard | Behaviour |
|---|-------|-----------|
| 1 | Empty directory | skip (leftover husks) |
| 2 | `*sync-conflict*` | skip — never feed conflict copies to the *arrs |
| 3 | `*_unpackerred` | skip — Unpackerr staging, not a release *(v4.6.1)* |
| 4 | `in_history` | skip — already imported |
| 5 | Suspicious files | Discord alert (deduped), skip |
| 6 | **Settle guard** | defer while byte signature is changing *(v4.6)* |
| 7 | RAR guard | defer while rar set present and no settled video |
| 7a | RAR-wait alert | Discord alert after `RAR_WAIT_ALERT_MINUTES` *(v4.5.2)* |

**Settle guard (v4.6)** — signature is `<file count>:<total bytes>`, recursive for
folders, compared across consecutive runs. A path must be unchanged for
`SETTLE_CYCLES` runs (default 1 ≈ 5 minutes) before it is eligible to scan.

> **Size-based, deliberately not mtime-based.** Syncthing preserves the *source*
> mtime on delivered files, so a file that landed thirty seconds ago can carry a
> timestamp hours old. Byte count is the only locally-observable signal that a
> transfer is still moving. (The RAR guard's separate 300-second video-settle check
> *is* mtime-based, correctly — Unpackerr writes that file locally.)

State: `/tmp/arr-rescans-settle.state`, self-pruning. Only paths that survive the
`in_history` check get entries, so a small state file is normal.

> **Full script body:** see `arr-rescans-v4.6.1` alongside this guide in the repo.

### 6.2 arr-import-monitor v1.4 — every 15 minutes

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-import-monitor/script`
**Schedule:** `*/15 * * * *`

Detects items stuck in an import state and alerts to Discord with per-item
deduplication and escalation.

**Optional conf overrides:**

```bash
IMPORT_ALERT_THRESHOLD=30    # minutes before first alert (default 30)
IMPORT_REALERT_SECONDS=3600  # seconds before re-alerting the same item (default 3600)
REAP_HOURS=24                # age before a stale importPending is reaped (default 24)
REAP_LIVE=1                  # arm the reaper; absent or 0 = DRY RUN (default)
```

**Design notes:**

| Aspect | Detail |
|--------|--------|
| Match field | **`trackedDownloadState`**, not `status`. `status` carries download-client state (completed/downloading/…) and never holds import states — v1.1 could not fire at all. |
| States matched | `importPending`, `importBlocked`, `importFailed` |
| Lidarr | requires `/api/v1/` — passed as the 4th arg to `check_queue` |
| Dedup stamping | **v1.3:** `record_alert` runs only on HTTP 204. A failed delivery retries next run rather than being silently suppressed for the full window. |
| Escalation | **v1.3:** re-alerts prefixed 🔁 with the alert number, so a long-stuck item reads differently from a fresh one. |
| Age format | ≥ 2 h renders as `XhYm` |
| Prune scope | **app-scoped.** v1.1 pruned all entries not in the current app's active list, so each app's pass wiped the others' dedup state. |
| Stale-queue reaper | **v1.4.** Deletes `importPending` entries whose source path is gone — see below. |

State: `/tmp/arr-import-monitor.state`, keys `<App>:<id>`, `<App>:<id>_first`,
`<App>:<id>_count`. A successful reap forgets all three.

**Stale-queue reaper (v1.4)** — automates the manual cleanup of §7.3. All four
conditions must hold before an entry is deleted:

1. `trackedDownloadState` is exactly `importPending`. `importBlocked` and
   `importFailed` are actionable states and are never reaped.
2. Age ≥ `REAP_HOURS` (default 24), measured from the monitor's own `_first`
   timestamp — a conservative under-estimate, since `/tmp` clears on reboot.
3. `outputPath` is present and translates to a host path. `/downloads/X` on any
   *arr container is `<SYNC_BASE>/<subdir>/X` on the host. Anything unrecognised
   yields an empty string and is treated as **cannot verify**, never as
   "does not exist".
4. That host path does **not** exist on disk.

Deletion uses `removeFromClient=false&blocklist=false`, so the torrent keeps
seeding and the release is not blocklisted. Each reap posts to Discord.

> **Dry run by default.** Set `REAP_LIVE=1` in the conf to arm it, matching the
> arr-cleanup v2.0 convention. Verify a full cycle of `WOULD REAP` output first.

A failed DELETE (non-2xx) falls through to the normal alert path rather than being
silently dropped.

> **Full script body:** `scripts/arr-import-monitor-v1.4` in the repo.

### 6.3 arr-cleanup v2.0 — daily

**Path:** `/boot/config/plugins/user.scripts/scripts/arr-cleanup/script`
**Schedule:** daily

Removes **local-only residue** from the Receive Only sync tree — `_unpackerred`
folders, extracted files, stale markers, empty husks. It never touches
seedbox-tracked content; that lifecycle belongs to the 14-day expiry and deletion
propagation.

**The discriminator is Syncthing's global index, not import history.**

```
/rest/db/file?folder=sfqzb-cvm5v&file=<rel>
  404                     → residue  (global index never knew it)
  200 + global.deleted    → residue  (seedbox tracked it, has since deleted it)
  200 + not deleted       → tracked  (SKIP — propagation owns it)
  anything else           → tracked  (fail safe)
```

Deleting residue **resolves** pending local changes and drains the
`receiveOnlyChanged` counters. Deleting tracked files would instead create pinned
local deletes — the failure mode described in §3.5.

**Optional conf overrides:**

```bash
CLEANUP_LIVE=1         # arm deletions; absent or 0 = DRY RUN (default)
CLEANUP_GRACE_DAYS=2   # minimum age before residue is eligible (default 2)
```

**Current state:** `CLEANUP_LIVE=1` is set — deletions are armed.

> **Dry-run by default.** The User Scripts plugin cannot pass command-line
> arguments, so live mode is armed from the conf file. Verify dry-run output before
> setting `CLEANUP_LIVE=1`.

**Two hard aborts before any deletion is attempted:**

1. Syncthing API key unreadable → `FATAL`, exit 1
2. `rest/system/ping` not answering → `FATAL`, exit 1

> **Verified executing LIVE, 21 Aug 2026.** `CLEANUP_LIVE=1` is set in the conf and
> the API key reads correctly. Baseline run:
> `0 residue item(s), 60 seedbox-tracked skipped, 9 too-young skipped, 0 errors`.
>
> **A zero-residue result is the healthy state**, not a fault. Everything in the tree
> is either still announced by the seedbox (propagation owns its lifecycle) or inside
> the 2-day grace window. Residue only appears when a locally-created artifact —
> typically an orphaned `_unpackerred` folder — survives past the grace gate.
>
> If residue *is* accumulating and the summary still reads 0, check the two FATAL
> aborts above before anything else: an unreadable key or a non-responding Syncthing
> exits the script before a single path is evaluated, while seedbox-propagated
> deletions keep working and mask the problem.

**v2.0 changes vs v1.x:** v1.x gated every deletion on `.imported` marker files,
which arr-rescans v4.4 stopped creating — the script had become a permanent no-op.

> **Full script body:** `scripts/arr-cleanup-v2.0` in the repo.

---

## 7. Known Issues & Workarounds

### 7.1 Partial imports from in-flight files *(Aug 2026)*

**Symptom:** a truncated `.mkv` imports as if whole and plays until it hits the gap.

**Cause:** qBittorrent pre-allocation created full-size files with zero-filled holes;
Syncthing replicated them faithfully; every size check in the pipeline passed.

**Fix:** pre-allocation OFF, `.!qB` suffix ON (§2.1), plus the arr-rescans settle
guard (§6.1) as a defence that does not depend on seedbox config.

### 7.2 Unpackerr landing race *(Aug 2026 — CAKES incident)*

**Symptom:** Unpackerr logs a frozen `(Extracted, Awaiting Import, elapsed: …) @
286.1MB/1.4GB (20%)` line every 2 minutes indefinitely; no extracted file appears.

**Cause:** extraction began before Syncthing finished delivering the volume set,
stopped when it ran out of parts, cleaned up its partial output, and cached the
result as `Extracted`. The cached state persists until the *arr queue entry clears.

**Diagnosis** — verify the archive before suspecting corruption:

```bash
cd "<release folder>"
cat *.sfv                      # release group's own CRC32 manifest
docker run --rm -v "$PWD":/data:ro alpine sh -c "apk add --no-cache cksfv; cd /data && cksfv -f *.sfv"
od -An -N16 -c *.rar           # Rar ! 032 007 \0 = valid RAR4 header
```

> **7-Zip is not a valid RAR test here.** Distro 7-Zip builds frequently ship without
> the RAR decoder for licensing reasons; `Cannot open the file as archive` means a
> missing codec, not bad data. `od` on the header and `cksfv` against the `.sfv`
> are the reliable checks. Also note `apk add pkg >/dev/null 2>&1 && cmd` will
> silently swallow a failed install and skip the command — drop the `&&`.

**Fix:** `docker restart unpackerr` clears the cached state; extraction re-runs
against the now-complete set. `UN_START_DELAY` raised to 20m as partial mitigation.

### 7.3 Stale `importPending` queue entries

**Symptom:** repeating `Import failed, path does not exist or is not accessible`
in the *arr log, every 5 minutes, for a release that already imported.

**Cause:** when an import happens via `DownloadedEpisodesScan` rather than the queue
flow, the *arr never ties completion back to the queue item. The entry survives while
the torrent seeds, and `RefreshMonitoredDownloads` retries it every cycle against a
path whose contents arr-cleanup has since removed.

**Resolution:** automated since arr-import-monitor v1.4 (§6.2) — entries older than
24 h whose source path is gone are deleted with the torrent left seeding. For manual
clearing, or while the reaper is still in dry-run, see §8.3. Entries also self-clear
at the 14-day seedbox expiry.

### 7.4 Orphaned `*_unpackerred` folders

**Symptom:** `Folder/File specified for import scan [...] doesn't exist` warnings for
a release imported weeks earlier.

**Cause:** the folder name never appears in import history under the `_unpackerred`
suffix, so `in_history` cannot match, so it was rescanned forever.

**Fix:** v4.6.1 skips them by name. They are locally-created and untracked by
Syncthing, so they can be deleted directly:

```bash
rm -rf /mnt/user/media/download/sync/sonarr/*_unpackerred/
```

### 7.5 Sync-conflict false imports *(Apr–Jul 2026)*

`sync-conflict-*` copies were fed to the *arrs as real releases. Guarded in both the
loose-file and subfolder scanners since v4.5, and excluded in `.stignore`. Root cause
was local deletion inside a Receive Only folder (§3.5). Last occurrence: 5 Aug 2026.

### 7.6 BRRip/WEBRip re-encodes displacing WEB-DL

See §4.5. Resolved via custom format scored −1000.

### 7.7 Anime / foreign-language title mismatches

Sonarr stores the TVDB canonical title regardless of the search term used. For
unresolved mismatches, submit the alias to TVDB and refresh the series once approved.
The `jq --arg` payload builder handles brackets, spaces and apostrophes in release
names (SubsPlease, ENOW/SUNSTONE).

### 7.8 Season pack imports

Require Interactive Import: Wanted → Manual Import → folder → Interactive Import.

### 7.9 TorrentLeech timezone mismatch

Negative ages on grabbed releases. Cosmetic.

### 7.10 SQLite gotchas *(Unraid 7.2.4 / SQLite 3.5x)*

- `WHERE col IS NULL` on a NOT NULL-declared column is constant-folded to false.
  Use `WHERE typeof(col)='null'` to find corrupted NULLs. The `unary-+` workaround
  no longer works in 3.5x.
- Recovery ladder: `PRAGMA integrity_check` → logs.db shortcut → `REINDEX` →
  `typeof()` delete → `.recover` → scheduled backup restore → API close-out.

---

## 8. Triage Procedures

### 8.1 A release has not imported — decision order

```
Is the file present on Caladan?
├─ No  → check Syncthing: rest/db/status, rest/db/need
│         is the torrent complete on the seedbox?
└─ Yes → Is it a RAR set?
    ├─ Yes → cksfv against .sfv + od header check   (§7.2)
    │        archive good?  → docker restart unpackerr
    │        archive bad?   → blocklist + re-search
    └─ No  → Does the *arr already have the file?
        ├─ Yes → stale queue entry                  (§7.3 / §8.3)
        └─ No  → check arr-rescans output           (§8.2)
```

### 8.2 What is arr-rescans doing?

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script 2>&1 | tail -30
cat /tmp/arr-rescans-settle.state
```

Every item prints its decision: `skip (imported)`, `skip (sync-conflict)`,
`skip (unpackerr artifact)`, `defer (still settling)`, `defer (awaiting unpack)`,
or `scan queued`.

### 8.3 Clear a stale queue entry

Verify the file exists first — never delete an entry for something that genuinely
failed to import.

```bash
source /boot/config/arr-rescans.conf

# 1. List pending entries with IDs
curl -s -H "X-Api-Key: $SONARR_KEY" "http://192.168.1.12:8989/api/v3/queue?pageSize=100&includeSeries=true" \
  | jq -r '.records[] | select(.trackedDownloadState=="importPending") | "\(.id)\t\(.series.title)\t\(.title)"'

# 2. Confirm the episode has a file (use episode?seriesId=N — /parse never populates episodeFile)
SID=<seriesId>
curl -s -H "X-Api-Key: $SONARR_KEY" "http://192.168.1.12:8989/api/v3/episode?seriesId=$SID" \
  | jq -r '.[] | select(.seasonNumber==N and .episodeNumber==M) | {hasFile, episodeFileId}'

# 3. Delete — keeps the torrent seeding, no blocklist
curl -s -X DELETE "http://192.168.1.12:8989/api/v3/queue/<ID>?removeFromClient=false&blocklist=false" \
  -H "X-Api-Key: $SONARR_KEY"
```

> If the release title contains `PROPER` and the file is already present, the entry
> is a failed PROPER upgrade. Blocklist instead of a plain delete if the PROPER is
> wanted.

### 8.4 Quoting and query pitfalls

- A `jq` regex that matches two series (`test("Librarians")`) puts two IDs in the
  shell variable and mangles the URL. `echo "$SID"` before using it.
- Radarr's `/api/v3/history` **ignores** `movieId`; use `/api/v3/history/movie?movieId=N`.
- `movieFile` embedded in `/api/v3/movie` has **no** `customFormatScore`;
  `/api/v3/moviefile?movieId=N` does.
- `jq` precedence: `(.x // 0) < 0`, not `.x // 0 < 0`.

---

## 9. Maintenance Procedures

### 9.1 Check import logs

```bash
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed" | tail -30
docker logs radarr --since 1h 2>&1 | grep -E "Imported|Import failed" | tail -30
```

### 9.2 Force a manual rescan

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

### 9.3 Check sync folder contents

```bash
ls /mnt/user/media/download/sync/{sonarr,radarr,lidarr}/
```

### 9.4 Check Syncthing status

See §3.4 — always `ping` first to confirm the key.

### 9.5 Apply an .stignore change

Rescan is disabled, so the change is not picked up on a timer:

```bash
curl -s -X POST "http://localhost:8384/rest/db/scan?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY"
curl -s "http://localhost:8384/rest/db/status?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY" \
  | jq '{localFiles, globalFiles, ignorePatterns, errors}'
```

A container restart also applies it.

### 9.6 Update credentials

```bash
nano /boot/config/arr-rescans.conf
```

Never edit keys into the scripts.

---

## 10. Rebuild Checklist

### 10.1 Containers

- [ ] binhex-syncthing, host networking, port 8384
- [ ] Sonarr 8989 / Radarr 7878 / Lidarr 8686 — appdata on **`/mnt/cache/appdata/`**
- [ ] Unpackerr — appdata on `/mnt/user/appdata/`
- [ ] Volume mounts per §4.1
- [ ] **Manually add /downloads mapping to Lidarr**

### 10.2 Syncthing

- [ ] Folder ID `sfqzb-cvm5v`, path `/media/sync`
- [ ] Type **Receive Only**; rescan interval **0**
- [ ] Add seedbox as remote device
- [ ] Create `.stignore` per §3.3
- [ ] **Verify exclusions FIRST, includes after, trailing `*` present**
- [ ] Confirm `ignorePatterns: true` and the Global/Local file-count gap

### 10.3 qBittorrent (seedbox)

- [ ] Save path `/home18/scytale1953/Media-sync/`
- [ ] **Pre-allocate disk space: OFF**
- [ ] **Append `.!qB` extension: ON**
- [ ] Seeding limits: 20160 min, remove torrent and files
- [ ] Category save paths explicitly saved in the WebUI
- [ ] Syncthing cron present

### 10.4 *arr Apps

- [ ] qBittorrent download client per §4.2
- [ ] Remote path mappings per §4.3
- [ ] Quality profile + **BRRip/WEBRip Re-encode custom format at −1000** (§4.5)
- [ ] Discord notifications

### 10.5 Unpackerr

- [ ] `UN_SONARR_0_PATHS_0` / `UN_RADARR_0_PATHS_0` — **verify the `_0` suffix**
- [ ] `UN_START_DELAY=20m`
- [ ] `UN_LOG_FILE` outside the sync tree

### 10.6 User Scripts

- [ ] Create `/boot/config/arr-rescans.conf`, `chmod 600`
- [ ] Deploy arr-rescans v4.6.1, schedule `*/5 * * * *`
- [ ] Deploy arr-import-monitor v1.4, schedule `*/15 * * * *`
- [ ] Deploy arr-cleanup v2.0, daily
- [ ] Run each manually and verify Discord delivery

---

## 11. Open Items

| Priority | Item | Notes |
|----------|------|-------|
| Medium | `UN_DELETE_DELAY` | Unpackerr should remove its own `_unpackerred` folder after import; 16 leftovers Jul–Aug 2026 say it is not firing. Check the value; unset or negative disables removal. arr-cleanup would reap them on its next pass regardless |
| Medium | Radarr re-encode backlog | ~9 films still hold Carmoz HEVC. The −1000 score appears to be driving upgrades already — BluRay x265 releases (GeneMige, SM737) were landing within hours of the change. Verify after one full RSS cycle before forcing manual searches |
| Low | Music library Tdarr coverage | Only TV / Movies / Movies 4K covered |
| Low | `zipPluginsFolder` performance | Monitor after plugin SHA `7bb0b1a7` |

**Verified closed on 21 Aug 2026:** Stuart S01E05 imported (`episodeFileId` 109246);
Sonarr queue clear except one genuinely-stalled download; `.stignore` deployed and
confirmed reducing the local index; arr-rescans v4.6.1 deployed; BRRip/WEBRip custom
format confirmed firing at −1000; **arr-cleanup v2.0 confirmed executing LIVE with
0 errors** (§6.3).

---

*Store in git at `/MyFiles/Systems/Caladan`.*
*Never commit `arr-rescans.conf` — it contains live credentials.*
