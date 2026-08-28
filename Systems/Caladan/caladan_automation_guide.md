# Caladan Media Automation — Configuration & Rebuild Guide

**Last Updated:** 28 August 2026 (rev 2)
**Server:** Caladan (192.168.1.12) — Unraid 7.2.4
**Hardware:** Supermicro X10SRL-F, Xeon E5-2630 v3, 32 GiB DDR4 ECC, RTX 3060, 68 TB array + 1 TB cache pool

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Seedbox Configuration](#2-seedbox-configuration-seedhosteu)
3. [Syncthing Configuration](#3-syncthing-configuration)
4. [*arr Application Configuration](#4-arr-application-configuration)
5. [Quality Profiles](#5-quality-profiles)
6. [Automation Scripts](#6-automation-scripts)
7. [Manual Import Workflow](#7-manual-import-workflow)
8. [Known Issues & Workarounds](#8-known-issues--workarounds)
9. [Maintenance Procedures](#9-maintenance-procedures)
10. [Rebuild Checklist](#10-rebuild-checklist)
11. [Change Log](#11-change-log)

---

## 1. Infrastructure Overview

### Pipeline

```
Prowlarr (indexer search)
      │
      ▼
qBittorrent (seedbox) ──► Syncthing (Send Only → Receive Only) ──► Caladan sync tree
                                                                          │
                                                        ┌─────────────────┤
                                                        ▼                 ▼
                                                   Unpackerr          arr-rescans
                                                  (RAR extract)      (5-min scans)
                                                        │                 │
                                                        └────────┬────────┘
                                                                 ▼
                                                  Sonarr / Radarr / Lidarr
                                                                 │
                                                                 ▼
                                                        Plex / Jellyfin
                                                                 │
                                                                 ▼
                                                             Tdarr
```

A second, parallel path exists for large releases — see [Section 7, Manual Import Workflow](#7-manual-import-workflow).

### Key Infrastructure

| Component | Value |
|-----------|-------|
| Caladan IP | 192.168.1.12 |
| Caladan OS | Unraid 7.2.4 (kernel 6.12.54) |
| Seedbox Host | ibiza.seedhost.eu |
| Seedbox User | scytale1953 |
| Seedbox Base Path | `/home18/scytale1953/` |
| Media Sync Path (Seedbox) | `~/Media-sync/` |
| Media Sync Path (Caladan) | `/mnt/user/media/download/sync/` |
| Manual Staging Path (Caladan) | `/mnt/user/media/download/manual/` |
| Syncthing Folder ID | `sfqzb-cvm5v` |
| Caladan Syncthing Port | 8384 |
| Seedbox Syncthing GUI Port | 9932 |
| Canonical docs repo | `/MyFiles/Systems/Caladan` |

### appdata Placement

The `appdata` share is configured `shareUseCache="only"` with `shareCachePool="cache"`, so all appdata physically resides on the cache pool and the mover will never relocate it to the array.

**All SQLite-backed containers bind `/config` directly to `/mnt/cache/appdata/<app>`**, not `/mnt/user/appdata/<app>`. Both paths resolve to the same bytes, but binding through `/mnt/user` routes I/O through the shfs FUSE layer, which is a known SQLite corruption vector.

| Container | `/config` host path | Status |
|-----------|--------------------|--------|
| sonarr | `/mnt/cache/appdata/sonarr` | Moved 28 Aug 2026 |
| radarr | `/mnt/cache/appdata/radarr` | Already correct |
| radarr-4k | `/mnt/cache/appdata/radarr-4k` | Already correct |
| lidarr | `/mnt/cache/appdata/lidarr` | Moved 28 Aug 2026 |

> **shfs caveat:** `/mnt/user` fabricates device and inode numbers. Comparing `stat -c '%d:%i'` between a `/mnt/user` path and a `/mnt/cache` path **always** shows a difference, even when the two are the same file. Inode comparison across shfs is meaningless.

To determine whether a second physical copy exists, compare size and mtime and check `/mnt/disk*/` for an array copy:

```bash
ls -la /mnt/disk*/appdata/<app>/ 2>/dev/null || echo "no array copy"
stat -c '%s  %y  %n' /mnt/user/appdata/<app>/<app>.db /mnt/cache/appdata/<app>/<app>.db
```

Identical size and mtime with no array copy means one file seen through two views — do **not** delete the `/mnt/user` path.

---

## 2. Seedbox Configuration (seedhost.eu)

### 2.1 qBittorrent

Active download client. WebUI: `https://ibiza.seedhost.eu/scytale1953/qbittorrent/`

**Tools → Options → Downloads:**
- Default Save Path: `/home18/scytale1953/Media-sync/`
- Pre-allocation: **disabled**
- Append `.!qB` to incomplete files: **enabled**
- Keep unselected files in `.unwanted`: **enabled**

**Tools → Options → BitTorrent (Seeding Limits):**

| Setting | Value | Config key |
|---------|-------|------------|
| When ratio reaches | disabled (0) | — |
| When seeding time reaches | 20160 minutes (14 days) | `Session\GlobalMaxSeedingMinutes=20160` |
| Then | Remove torrent and files | `Session\ShareLimitAction=RemoveWithContent` |

Config file: `~/.config/qBittorrent/qBittorrent.conf`

> **Per-torrent limits override the global.** qBittorrent stores a share limit per torrent at add time. Torrents added before the current global config was written (14 Jul 2026) may carry their own limit or none at all, and the global value will not retroactively apply to them. See [Section 8.10, Orphaned Seedbox Content](#810-orphaned-seedbox-content).

### 2.2 qBittorrent Download Categories

Each category **must have an explicit save path set in the WebUI.** Without one, *arr health checks fail against the bare base path.

| Category | Save Path |
|----------|-----------|
| sonarr | `/home18/scytale1953/Media-sync/sonarr/` |
| radarr | `/home18/scytale1953/Media-sync/radarr/` |
| lidarr | `/home18/scytale1953/Media-sync/lidarr/` |

Category definitions: `~/.config/qBittorrent/categories.json`

### 2.3 qBittorrent WebUI API

Useful for reconciliation from Caladan. Login writes a session cookie:

```bash
QB="https://ibiza.seedhost.eu/scytale1953/qbittorrent"
read -s -p "qb password: " QBPASS; echo

curl -s -c /tmp/qb.cookie -X POST "$QB/api/v2/auth/login" \
  --data-urlencode "username=scytale1953" --data-urlencode "password=$QBPASS" \
  -H "Referer: $QB"
# Prints "Ok." on success, "Fails." on bad credentials

curl -s -b /tmp/qb.cookie "$QB/api/v2/torrents/info" \
  | jq -r '.[] | "\(.name)\t\(.content_path)"'
```

The `Referer` header is required — qBittorrent rejects the login without it.

### 2.4 Seedbox Cron

Only one entry — the Syncthing watchdog:

```cron
MAILTO=""
*/5 * * * * /bin/bash ~/software/cron/syncthing
```

### 2.5 Media-sync Folder Structure

| Directory | Purpose | Synced |
|-----------|---------|--------|
| `sonarr/` | TV downloads | Yes |
| `radarr/` | Movie downloads | Yes |
| `lidarr/` | Music downloads | Yes |
| `radarr-4k/` | 4K movies | No |
| `freeleech/` | Freeleech downloads | No |
| `prowlarr/` | Direct Prowlarr grabs — see [Section 7](#7-manual-import-workflow) | No |
| `foo/` | Miscellaneous | No |

### 2.6 ruTorrent (Legacy — not in use)

Installed but unused. If reverting:
- Ratio plugin `MAX_RATIO` set to 9999 to prevent early removal
- File: `~/www/scytale1953.ibiza.seedhost.eu/scytale1953/rutorrent/plugins/ratio/conf.php`
- Ratio group 1 (ratioDef): Min% 0, Max% 0, UL 0, Time 336h, Action: Remove

---

## 3. Syncthing Configuration

### 3.1 Caladan Container

| Setting | Value |
|---------|-------|
| Container Name | `binhex-syncthing` |
| Image | `binhex/arch-syncthing` |
| Version | 2.1.3 |
| Network Mode | host |
| Web UI Port | 8384 |
| Config Path | `/mnt/cache/appdata/binhex-syncthing/` |
| Sync Mount | `/mnt/user/media/download/sync/` → `/media/sync` |

### 3.2 Folder Configuration

| Setting | Value |
|---------|-------|
| Folder ID | `sfqzb-cvm5v` |
| Folder Name | Media sync |
| Caladan Path | `/mnt/user/media/download/sync/` (host) = `/media/sync` (container) |
| Seedbox Path | `~/Media-sync/` |
| Folder Type (Caladan) | **Receive Only** |
| Folder Type (Seedbox) | Send Only |
| `ignorePerms` | `true` |
| `fsWatcherEnabled` | `true` (delay 10s) |
| `rescanIntervalS` | 0 (watcher-driven) |

### 3.3 Ignore Patterns

**File:** `/mnt/user/media/download/sync/.stignore`

**Ordering is load-bearing.** First match wins, so exclusions must appear *before* the `!` include rules, and the catch-all `*` must be last. An exclusion placed below an include is dead code.

`(?d)` marks a pattern as "ignore, but allow Syncthing to delete it when removing a parent directory." Comments use `//`.

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

> **Recursive form alone is insufficient.** `/sonarr/**/*.jpg` does not match a `.jpg` sitting at the root of `sonarr/`. Both the root-level and recursive variants are required, which is why each image rule appears twice.

This `.stignore` is **verbatim-verified** as of 28 Aug 2026 and safe to restore from directly.

### 3.4 Checking Sync Status via CLI

```bash
STKEY=$(grep -o '<apikey>[^<]*' /mnt/cache/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d'>' -f2)
curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY" | jq
```

Returns `completion`, `globalBytes`, `needBytes`, `needItems`. A completion of 100 with `needItems: 0` means the transfer is finished.

**Alias** — Unraid's root filesystem is RAM-based, so `~/.bashrc` does not survive reboots. Persist by having `/boot/config/go` write the alias into `.bashrc` at each boot:

```bash
cp /boot/config/go /boot/config/backups/go.$(date +%F)

cat >> /boot/config/go <<'EOF'

# syncstatus — Syncthing completion for the Media sync folder
cat >> /root/.bashrc <<'ALIAS'
alias syncstatus='STKEY=$(grep -o "<apikey>[^<]*" /mnt/cache/appdata/binhex-syncthing/syncthing/config/config.xml | cut -d">" -f2) && curl -s "http://localhost:8384/rest/db/completion?folder=sfqzb-cvm5v" -H "X-API-Key: $STKEY" | jq'
ALIAS
EOF

tail -8 /boot/config/go
```

Takes effect on the next reboot; paste the alias directly into the current shell to use it immediately.

Verify whether it is already present:

```bash
grep -n "binhex-syncthing" /boot/config/go 2>/dev/null || echo "syncstatus not yet persisted"
```

### 3.5 Detecting In-Flight Files

Syncthing writes `.syncthing.<name>.tmp` alongside the destination while transferring. A directory can appear complete by file count while two files are still temporaries:

```bash
find /path/to/release -name '.syncthing.*' | wc -l
```

This is the check `arr-rescans` does **not** currently perform — see [Section 8.6](#86-arr-rescans-has-no-syncthing-tmp-guard).

### 3.6 Revert Local Changes — Hazard

The **Revert Local Changes** button resets the local folder to match remote state. On a Receive Only folder with a large divergence this deletes local-only content irreversibly.

As of 28 Aug 2026 the folder reports several hundred Locally Changed Items. Do **not** press this button while any of the following is true:

- A release is staged in the sync tree but not yet imported
- A transfer is in flight
- Seedbox-side content has been deleted but not yet reconciled

**Local deletion from a Receive Only folder is architecturally unsound.** Deleting locally causes Syncthing to re-fetch from remote on the next scan. Deletions must originate on the seedbox and propagate inward — the pinned-delete lifecycle model.

---

## 4. *arr Application Configuration

### 4.1 Docker Path Mappings

| App | Container path | Host path |
|-----|---------------|-----------|
| **Sonarr** (8989) | `/config` | `/mnt/cache/appdata/sonarr` |
| | `/tv` | `/mnt/user/media/tv` |
| | `/downloads` | `/mnt/user/media/download/sync/sonarr` |
| | `/manual` | `/mnt/user/media/download/manual` |
| | `/trash` | `/mnt/user/media/trash/sonarr` |
| **Radarr** (7878) | `/config` | `/mnt/cache/appdata/radarr` |
| | `/movies` | `/mnt/user/media/films` |
| | `/downloads` | `/mnt/user/media/download/sync/radarr` |
| | `/manual` | `/mnt/user/media/download/manual` |
| | `/trash` | `/mnt/user/media/trash/radarr` |
| **Radarr-4K** | `/config` | `/mnt/cache/appdata/radarr-4k` |
| | `/movies` | `/mnt/user/media/films-4k` |
| | `/downloads` | `/mnt/user/media/download/sync/radarr-4k` |
| | `/trash` | `/mnt/user/media/trash/radarr-4k` |
| **Lidarr** (8686) | `/config` | `/mnt/cache/appdata/lidarr` |
| | `/music` | `/mnt/user/media/mp3/Rock` |
| | `/downloads` | `/mnt/user/media/download/sync/lidarr` |
| | `/manual` | `/mnt/user/media/download/manual` |
| | `/trash` | `/mnt/user/media/trash/lidarr` |

**Rules:**
- All *media* mounts use `/mnt/user` paths, never `/mnt/cache/media/...`
- All *appdata* mounts use `/mnt/cache` paths
- Each *arr maps its **app-specific subdirectory** to `/downloads`, consuming the `sonarr/` path segment
- **Unpackerr** mounts the sync **root** (`/mnt/user/media/download/sync` → `/downloads`)
- Lidarr does not include a `/downloads` mapping by default — add it manually

> Because each *arr's `/downloads` is scoped to its own subdirectory, none of them can see `prowlarr/`, `freeleech/`, or any sibling. This is why `/manual` exists.

### 4.2 Download Client Configuration (all *arrs)

| Setting | Value |
|---------|-------|
| Client Type | qBittorrent |
| Name | qBittorrent (seedhost.eu) |
| Host | `ibiza.seedhost.eu` |
| Port | 443 |
| URL Base | `/scytale1953/qbittorrent` |
| SSL | Yes |
| Username | scytale1953 |
| Category | sonarr / radarr / lidarr (per app) |
| Post-Import Category | blank |
| Remove Completed | Unchecked |

> Enable Advanced Settings in the dialog to reveal the URL Base field.

### 4.3 Remote Path Mappings

App-specific, because each app's `/downloads` is already scoped to its subdirectory:

| App | Remote Path (Seedbox) | Local Path (Container) |
|-----|-----------------------|------------------------|
| Sonarr | `/home18/scytale1953/Media-sync/sonarr/` | `/downloads/` |
| Radarr | `/home18/scytale1953/Media-sync/radarr/` | `/downloads/` |
| Lidarr | `/home18/scytale1953/Media-sync/lidarr/` | `/downloads/` |

Host must be `ibiza.seedhost.eu`.

### 4.4 API Keys

Stored in `/boot/config/arr-rescans.conf` — see [Section 6.1](#61-shared-configuration).

API version differs by app: **Sonarr and Radarr use `/api/v3/`, Lidarr uses `/api/v1/`.**

---

## 5. Quality Profiles

### 5.1 Sonarr Profiles (verified live, 28 Aug 2026)

| id | Name | Cutoff | upgradeAllowed | minUpgradeFormatScore |
|----|------|--------|----------------|----------------------|
| 1 | Any | 1 | false | 1 |
| 2 | SD | 1 | false | 1 |
| 3 | HD-720p | 4 | false | 1 |
| 4 | **HD-1080p** | **1002** (WEB 1080p group) | **true** | 1 |
| 5 | Ultra-HD | 16 | false | 1 |
| 6 | **HD - 720p/1080p** | **7** (Bluray-1080p) | **true** | 1 |

**Profile 4 (HD-1080p) allowed qualities, in rank order:**

| id | Quality |
|----|---------|
| 9 | HDTV-1080p |
| 1002 | GROUP: WEB 1080p (WEBRip-1080p, WEBDL-1080p) |
| 7 | Bluray-1080p |

**Profile 6 (HD - 720p/1080p) allowed qualities, in rank order:**

| id | Quality |
|----|---------|
| 4 | HDTV-720p |
| 9 | HDTV-1080p |
| 1001 | GROUP: WEB 720p (WEBRip-720p, WEBDL-720p) |
| 6 | Bluray-720p |
| 1002 | GROUP: WEB 1080p (WEBRip-1080p, WEBDL-1080p) |
| 7 | Bluray-1080p |
| 20 | Bluray-1080p Remux |

> Note the ordering: **Bluray-720p ranks above HDTV-1080p.** Profile 6 is not simply "720p or 1080p, prefer higher" — source quality outranks resolution within it.

### 5.2 Radarr Profiles

| id | Name | Cutoff | upgradeAllowed |
|----|------|--------|----------------|
| 1 | Any | 20 | false |
| 2 | SD | 20 | false |
| 3 | HD-720p | 6 | false |
| 4 | HD-1080p | 1002 | true |
| 5 | Ultra-HD | 31 | false |
| 6 | HD - 720p/1080p | 7 | true |

### 5.3 Profile ID Collision — Sonarr vs Radarr

**Both apps have a profile with id 6 named "HD - 720p/1080p", and they hold different values.** Reading a profile list from one app and acting on the other is a live footgun; it cost two diagnostic round trips on 28 Aug 2026. Always confirm which app a profile dump came from.

### 5.4 How Cutoff-Unmet Actually Works

Three independent gates must all pass for an episode to appear in **Wanted → Cutoff Unmet**:

1. **`upgradeAllowed` must be true.** When false, Sonarr's `UpgradeAllowedSpecification` rejects any release for an episode that already has a file, and nothing is ever marked cutoff-unmet regardless of the cutoff value.
2. **The existing file's quality must be *allowed* in the profile.** A quality not present in the profile is unranked, not "below cutoff" — such files never enter the cutoff-unmet set at all. This is why 76 Bluray-720p TNG episodes were invisible while assigned to profile 4, which allows no 720p tier.
3. **The existing quality must rank below the cutoff.** Setting the cutoff to the profile's *lowest* allowed quality makes the set permanently empty.

The `qualityCutoffNotMet` field on an episode file is the same flag the `wanted/cutoff` endpoint filters on — query it directly when diagnosing:

```bash
source /boot/config/arr-rescans.conf
curl -s "http://192.168.1.12:8989/api/v3/episode?seriesId=<ID>&includeEpisodeFile=true" \
  -H "X-Api-Key: $SONARR_KEY" \
  | jq -r '[.[] | select(.hasFile)] | map({q: .episodeFile.quality.quality.name, unmet: .episodeFile.qualityCutoffNotMet})
           | group_by([.q, .unmet])[] | "\(.[0].q)\tcutoffNotMet=\(.[0].unmet)\t\(length)"'
```

### 5.5 minUpgradeFormatScore Has a Hard Floor of 1

Sonarr's validator refuses any value below 1:

```
'Min Upgrade Format Score' must be greater than or equal to '1'.
```

It is compared against the *difference* in custom format score between candidate and existing file, so it only blocks upgrades where the candidate scores no better. With only negative-scored custom formats defined, a clean Bluray-1080p and a clean Bluray-720p both score 0 — a difference of 0, which is not ≥ 1. This has not been observed blocking a real upgrade, but it is the next suspect if quality-only upgrades stall.

### 5.6 Radarr Custom Format

**"BRRip/WEBRip Re-encode"** — regex `\b(BRRip|BDRip|WEBRip)\b`, scored **-1000** on the HD-1080p profile. Prevents re-encodes from displacing WEB-DL files.

### 5.7 Inspecting a Profile

```bash
source /boot/config/arr-rescans.conf
curl -s "http://192.168.1.12:8989/api/v3/qualityprofile/6" -H "X-Api-Key: $SONARR_KEY" \
  | jq -r '.items[] | select(.allowed) |
      if .quality then "\(.quality.id)\t\(.quality.name)"
      else "\(.id)\tGROUP: \(.name) [\([.items[].quality.name]|join(", "))]" end'
```

Groups carry their own ids (1001, 1002, …) distinct from bare quality ids. Setting `cutoff` to a bare quality id when the profile groups that quality will fail validation.

### 5.8 Editing a Profile Safely

Always back up, patch with `jq`, PUT, and **read the result back** — the PUT echo can mislead, and errors return as a JSON array rather than an HTTP failure:

```bash
source /boot/config/arr-rescans.conf
mkdir -p /boot/config/backups

curl -s "http://192.168.1.12:8989/api/v3/qualityprofile/6" -H "X-Api-Key: $SONARR_KEY" \
  > /boot/config/backups/sonarr-qp6-$(date +%F).json

jq '.upgradeAllowed = true | .cutoff = 7' \
  /boot/config/backups/sonarr-qp6-$(date +%F).json > /tmp/qp6.new.json

curl -s -X PUT "http://192.168.1.12:8989/api/v3/qualityprofile/6" \
  -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d @/tmp/qp6.new.json | jq -r 'if type=="array" then .[].errorMessage else "ok" end'

# Read back — do not trust the echo
curl -s "http://192.168.1.12:8989/api/v3/qualityprofile/6" -H "X-Api-Key: $SONARR_KEY" \
  | jq '{id, name, cutoff, upgradeAllowed}'
```

> Never redirect a PUT to `/dev/null`. A validation error is returned in the response body with a 200-class status; discarding it makes a failed write look like a success.

---

## 6. Automation Scripts

Four scripts, all scheduled through the **Unraid User Scripts plugin** (not root cron — `crontab -l` shows nothing). All live under `/boot/config/plugins/user.scripts/scripts/<name>/script`.

> **The User Scripts plugin cannot pass command-line arguments.** Every script must treat bare invocation as its default/cron mode.

| Script | Version | Schedule | Destructive? |
|--------|---------|----------|--------------|
| `arr-rescans` | 4.6.1 | `*/5 * * * *` | No |
| `arr-import-monitor` | 1.4 | `*/15 * * * *` | Yes — reaper, `REAP_LIVE=1` armed |
| `arr-cleanup` | 2.0 | daily | Yes — `CLEANUP_LIVE=1` armed |
| `arr-import-verify` | 2.2 | 04:30 daily | No — read-only |

### 6.1 Shared Configuration

**File:** `/boot/config/arr-rescans.conf` — `chmod 600`, **never committed to git**.

Sourced by all four scripts. Persists across reboots.

```bash
SONARR_KEY="…"
RADARR_KEY="…"
LIDARR_KEY="…"
DISCORD_WEBHOOK="…"

IMPORT_ALERT_THRESHOLD=120     # 2h — sized for large 4K movie transfers, not the 30m script default
IMPORT_REALERT_SECONDS=28800   # 8h between re-alerts
VIDEO_EXTENSIONS="mkv mp4 avi m4v"
CLEANUP_LIVE=1
VERIFY_SONARR_TOLERANCE=80

# --- pinned defaults (previously implicit) — Aug 2026
RAR_WAIT_ALERT_MINUTES=120   # arr-rescans: alert if a rar set sits unextracted this long
SETTLE_CYCLES=1              # arr-rescans: consecutive stable byte-signature runs before scan
REAP_HOURS=24                # arr-import-monitor: age before a stale importPending is reaped
REAP_LIVE=1                  # arr-import-monitor: stale-queue reaper ARMED
CLEANUP_GRACE_DAYS=2         # arr-cleanup: min residue age before deletion
```

> **Duplicate-block defect (found 28 Aug 2026).** The pinned-defaults block was duplicated at lines 11 and 18. Values were identical so behaviour was unaffected, but the second block silently wins and the redundancy misleads.

Check and remediate — confirm the two blocks are identical *before* cutting either, and adjust the line ranges to what `cat -n` actually shows:

```bash
grep -c "pinned defaults" /boot/config/arr-rescans.conf   # expect 1
cat -n /boot/config/arr-rescans.conf | sed -n '8,30p'

diff <(sed -n '12,17p' /boot/config/arr-rescans.conf | grep -oE '^[A-Z_]+=[^ #]*') \
     <(sed -n '19,24p' /boot/config/arr-rescans.conf | grep -oE '^[A-Z_]+=[^ #]*') \
  && echo "IDENTICAL — safe to drop the second block"

cp /boot/config/arr-rescans.conf /boot/config/backups/arr-rescans.conf.$(date +%F)
sed -i '18,23d' /boot/config/arr-rescans.conf
```

**Always validate after a hand edit.** All four scripts source this file, so a syntax error takes the whole stack down at once. `bash -n` on a pure-assignment file catches unbalanced quotes, the realistic failure mode:

```bash
bash -n /boot/config/arr-rescans.conf && echo "syntax ok"

source /boot/config/arr-rescans.conf
echo "SONARR ${SONARR_KEY:0:4} | REAP_LIVE=$REAP_LIVE | CLEANUP_LIVE=$CLEANUP_LIVE | SETTLE_CYCLES=$SETTLE_CYCLES | TOL=$VERIFY_SONARR_TOLERANCE"
```

Verify the file is sourced before debugging empty API output — an unsourced conf is the usual cause.

### 6.1.1 Environment Override — Defect and Fix

**Sourcing the conf clobbers command-line overrides.** The original ordering in `arr-cleanup` and `arr-import-monitor` was:

```bash
source /boot/config/arr-rescans.conf     # sets CLEANUP_LIVE=1
LIVE="${CLEANUP_LIVE:-0}"                # env value already overwritten
```

So `CLEANUP_LIVE=0 bash …/arr-cleanup/script` ran **LIVE**. The dry-run procedure documented in earlier revisions of this guide did nothing, and the same applied to `REAP_LIVE=0` on `arr-import-monitor`. This was found on 28 Aug 2026 by noticing the banner read `LIVE` on a run invoked with `CLEANUP_LIVE=0`.

**Fix applied to both scripts** — capture before sourcing, restore after:

```bash
_CLEANUP_LIVE_ENV="${CLEANUP_LIVE:-}"
source /boot/config/arr-rescans.conf
[ -n "$_CLEANUP_LIVE_ENV" ] && CLEANUP_LIVE="$_CLEANUP_LIVE_ENV"
LIVE="${CLEANUP_LIVE:-0}"
```

`arr-import-monitor` uses the same shape with `_REAP_LIVE_ENV` / `REAP_LIVE`, inserted around its own `source` line so the later `REAP_LIVE=${REAP_LIVE:-0}` picks up the restored value.

**Both assertions must pass after any change here.** The second matters as much as the first — an over-broad fix would break the scheduled job by leaving it in dry-run permanently:

```bash
CLEANUP_LIVE=0 bash /boot/config/plugins/user.scripts/scripts/arr-cleanup/script 2>&1 | head -1
# → arr-cleanup v2.0 — DRY RUN — grace 2d

bash /boot/config/plugins/user.scripts/scripts/arr-cleanup/script 2>&1 | head -1
# → arr-cleanup v2.0 — LIVE — grace 2d        (bare invocation must stay live)

REAP_LIVE=0 bash /boot/config/plugins/user.scripts/scripts/arr-import-monitor/script 2>&1 | head -1
# → arr-import-monitor v1.4 — reaper: DRY RUN (>= 24h)

bash /boot/config/plugins/user.scripts/scripts/arr-import-monitor/script 2>&1 | head -1
# → arr-import-monitor v1.4 — reaper: LIVE (>= 24h)
```

> **Generalisation.** Any script that sources a config file and then reads a variable with `${VAR:-default}` has this defect. `arr-rescans` and `arr-import-verify` are unaffected — neither has an env-overridable arming switch — but the pattern above is the template if one is ever added.

### 6.2 arr-rescans (v4.6.1)

**Purpose:** trigger `DownloadedEpisodesScan` / `DownloadedMoviesScan` against synced release folders and loose video files.

**Import detection is via the *arr history API**, not marker files. It fetches `eventType=3` (downloadFolderImported) once per app and matches `data.droppedPath` against folder/file names.

> **No `.imported` or `.first_seen` markers are created.** v4.4 removed them. Any such files on disk are pre-v4.4 leftovers and are cleaned by `.stignore` rules. Documentation describing marker-based guards is obsolete.

**Guard chain, in order of evaluation per item:**

1. **Empty directory** — skipped (leftover `_unpackerred` husks)
2. **`*sync-conflict*`** — skipped, folder-shaped and loose-file variants
3. **`*_unpackerred`** — skipped (v4.6.1). Unpackerr staging copies, never valid scan targets; because the suffixed name never appears in import history, they would otherwise be rescanned forever
4. **Import history match** — skipped
5. **Suspicious content** (`.exe .bat .com .scr .js .vbs`) — Discord alert once per folder, deduped in `/tmp/arr-rescans-suspicious.state`, scan genuinely skipped
6. **Settle guard** (v4.6) — deferred while byte signature is changing
7. **RAR guard** — deferred while a `.rar` set is present *and* no settled video file exists

**Settle guard** is **size-based, not mtime-based**, and deliberately so: Syncthing preserves the *source* mtime on delivered files, so a file that landed thirty seconds ago can carry a timestamp hours old. Byte count is the only locally observable signal that a transfer is still moving.

Signature is `"<file count>:<total bytes>"`, recursive for directories. A path must present the same signature for `SETTLE_CYCLES` consecutive runs (default 1 ≈ 5 minutes) before becoming eligible. State in `/tmp/arr-rescans-settle.state`, written wholesale each run so it self-prunes.

**RAR guard** must test whether extraction has *completed*, not merely whether RARs are present — RAR sets persist on disk until seedbox cleanup, so a presence-only check defers forever (the v4.4 defect). "Settled" here means a video file with mtime ≥ 5 minutes old. mtime is correct in *this* context because Unpackerr writes the extracted file locally, making its mtime local truth.

**RAR wait alert:** if a deferred folder's RAR set has sat for `RAR_WAIT_ALERT_MINUTES` (default 120) with no extracted video, a deduped Discord alert fires pointing at Unpackerr. State in `/tmp/arr-rescans-rarwait.state`, pruned when the folder disappears.

**State files:**

| Path | Contents |
|------|----------|
| `/tmp/arr-rescans-settle.state` | `<path>\t<signature>\t<count>` |
| `/tmp/arr-rescans-suspicious.state` | folder names alerted |
| `/tmp/arr-rescans-rarwait.state` | folder names alerted |

All are `/tmp` and therefore reset on reboot. Cost: one extra cycle of latency on the first run after a reboot.

### 6.3 arr-import-monitor (v1.4)

**Purpose:** detect items stuck in import states, alert with per-item deduplication, and reap stale queue entries.

Matches on **`trackedDownloadState`**, not `status`. The `status` field carries download-client state (completed/downloading/…) and never holds import states — matching on it was the v1.1 defect that made the script unable to fire at all.

Watched states: `importPending`, `importBlocked`, `importFailed`.

**Escalating re-alerts:** alert count tracked per item; re-alerts are prefixed `🔁 (alert #N — still stuck)` so a long-stuck item reads differently from a fresh one. Ages ≥ 2h format as `XhYm`.

**Dedup state is stamped only on confirmed Discord delivery (HTTP 204).** A failed delivery retries next run rather than being suppressed for the full re-alert window — which also means the Unraid fallback nags every 15 minutes until the webhook is fixed. That is intentional.

**Stale-queue reaper (v1.4, `REAP_LIVE=1` — ARMED).** An import completed via `DownloadedEpisodesScan` rather than the queue flow leaves its queue entry at `importPending`. The entry survives as long as the torrent seeds, and `RefreshMonitoredDownloads` retries it every 5 minutes against a path `arr-cleanup` has since emptied, producing endless "Import failed, path does not exist" log noise.

Reap conditions — **all** must hold:

- `trackedDownloadState` is exactly `importPending` (`importBlocked` / `importFailed` are actionable and never reaped)
- age ≥ `REAP_HOURS` (default 24)
- `outputPath` present and translatable to a host path
- that host path does **not** exist

Deletion uses `removeFromClient=false&blocklist=false`, so the torrent keeps seeding and the release is not blocklisted. Reaps are announced to Discord without dedup.

`prune_state` is **app-scoped** — the v1.1 version pruned all entries not in the current app's active list, so each app's pass wiped the others' dedup state and caused re-alert spam.

State: `/tmp/arr-import-monitor.state`

### 6.4 arr-cleanup (v2.0)

**Purpose:** remove local-only residue from the Receive Only sync tree. `CLEANUP_LIVE=1` — **armed**.

**The discriminator is Syncthing's global index, not the filesystem.** For each depth-1 entry it queries `/rest/db/file`:

| Response | Verdict | Action |
|----------|---------|--------|
| HTTP 404 | `residue` | global index never knew this object — safe to delete |
| `global.deleted == true` | `residue` | seedbox tracked it once, has since deleted it — safe |
| `global.deleted == false` | `tracked` | seedbox still announces it — **skip** |
| any other status | `tracked` | fail safe — skip |

Deleting *tracked* files would create pinned local deletes; deleting *residue* instead **resolves** pending local changes and drains the receiveOnlyChanged counter.

**Aborts without deleting anything** if the Syncthing API key cannot be read or `/rest/system/ping` fails — an "untracked" verdict is only trustworthy when Syncthing is actually answering.

Age gate: `CLEANUP_GRACE_DAYS` (default 2), computed from the **newest file mtime inside** a directory rather than the directory's own mtime, which is unreliable on Unraid user shares.

> The `STKEY` read was moved from `/mnt/user/appdata/binhex-syncthing/...` to `/mnt/cache/appdata/...` on 28 Aug 2026 (line 45). Both resolve to the same file, but every script now uses the cache path consistently.

**What this script does *not* cover:** content present on the seedbox with no backing torrent. Syncthing's global index legitimately announces such content, so `arr-cleanup` correctly returns `tracked` and skips it. That is a seedbox-side problem — see [Section 8.10](#810-orphaned-seedbox-content).

### 6.5 arr-import-verify (v2.2)

**Purpose:** audit recent imports for truncated or short media. **Read-only** — never deletes, moves, blocklists, or re-triggers.

Two orthogonal detectors:

| Verdict | Meaning |
|---------|---------|
| `TAIL_FAIL` | last N seconds of video will not decode — transit truncation |
| `SHORT_HEADER` | header duration well under *arr expected runtime — defective source |
| `TAIL_WARN` | non-fatal decoder warnings only — *not* a truncation signal |
| `PROBE_FAIL` | ffprobe could not read the file at all |
| `MISSING_ON_DISK` | *arr has a record, file is gone |
| `IGNORED` | matched the acknowledge list |

**Tail checks decode video only** (`-map 0:v:0`). Without this, E-AC3 audio warnings produce false positives.

**ffmpeg is routed through a container** — Caladan has no host ffmpeg. Candidates default to `jellyfin tdarr plex`; in practice `tdarr` is used. The script builds a host→container mount map by longest-prefix match from `docker inspect`, so library paths resolve correctly inside whichever container is selected.

**Tolerances:** Sonarr 80% (`VERIFY_SONARR_TOLERANCE=80`), Radarr 95%. Sonarr was dropped from 90% to eliminate false positives on 22-minute sitcoms, where TVDB slot-length rounding made legitimate files look short. Per-episode TVDB runtime is preferred over series runtime, which is a nominal slot length and produces heavy false positives on variable-length shows.

**Bare invocation = cron mode:** 2-day window (overlapping the daily schedule so nothing slips between runs), Discord on *new* findings only.

```bash
./arr-import-verify                          # cron mode
./arr-import-verify --check-deps             # validate environment and path resolution
./arr-import-verify --days 7                 # manual audit, no Discord
./arr-import-verify --ack '*S04E05*'         # stop alerting on a known-bad file
./arr-import-verify --list-ignored
./arr-import-verify --full                   # decode entire file, not just tail
./arr-import-verify --quick                  # skip tail check
```

**Files** (both on `/boot` so they survive the RAM-based rootfs):

| Path | Purpose |
|------|---------|
| `/boot/config/arr-import-verify.state` | alert-once state, keyed by md5 of path+verdict |
| `/boot/config/arr-import-verify.ignore` | acknowledged files, one glob per line |

CSV output to `/tmp/arr-import-verify-<timestamp>.csv`, pruned after `VERIFY_CSV_KEEP_DAYS` (30).

> **Cosmetic defect:** the summary line prints `SHORT_HEADER: … < ${DURATION_TOLERANCE}%`, the legacy global value, rather than the per-app tolerance actually applied. The check itself uses the correct per-app value.

### 6.6 Script Bodies

Verbatim bodies are **not** inlined here. They are deployed at `/boot/config/plugins/user.scripts/scripts/<name>/script` and committed to `/MyFiles/Systems/Caladan` as individual files.

**Discipline:** never patch or regenerate a script from memory or from this document. Retrieve the deployed body verbatim, apply the diff, verify against live system output, then commit.

---

## 7. Manual Import Workflow

For large releases, FileZilla over FTP is substantially faster than Syncthing. This path predates the automation and remains in active use.

### 7.1 The Path

```
Prowlarr (search + grab, "seedbox" tag)
      │
      ▼
qBittorrent (seedbox) → ~/Media-sync/prowlarr/
      │
      ▼  FileZilla FTP (manual)
      │
/mnt/user/media/download/manual/   ← outside the Syncthing tree
      │
      ▼  Sonarr/Radarr/Lidarr manual import, mode MOVE
      │
   Library
```

`prowlarr/` is excluded by `.stignore`, so nothing on this path is ever tracked by Syncthing.

### 7.2 Why /manual Exists

Each *arr's `/downloads` is scoped to its own subdirectory, so none of them can see `prowlarr/`. Before `/manual`, the workaround was moving content into `sync/<app>/`, which created **untracked local additions in a Receive Only folder** — visible as Locally Changed Items, and destroyable by the Revert button with no remote copy to restore from.

`/mnt/user/media/download/manual` is mounted into Sonarr, Radarr, and Lidarr as `/manual` and sits entirely outside the Syncthing tree.

### 7.3 Import Mode — Move vs Copy

**This is the decision that matters, and it depends on where the files came from.**

| Source | Mode | Reason |
|--------|------|--------|
| `/manual` (FTP) | **Move** | Outside the Syncthing tree. Move consumes the staging copy and leaves the directory clean. |
| `sync/<app>/` (Syncthing) | **Copy** | Receive Only folder. Move creates a local deletion, which Syncthing re-fetches from remote on the next scan. |

After a Move import the staging directory is left as an empty husk — remove it with `rmdir`.

### 7.4 Procedure

```bash
source /boot/config/arr-rescans.conf

# 1. Stage
mv "/mnt/user/media/download/sync/prowlarr/RELEASE" /mnt/user/media/download/manual/

# 2. Verify Sonarr's parse BEFORE importing
curl -s -G "http://192.168.1.12:8989/api/v3/manualimport" -H "X-Api-Key: $SONARR_KEY" \
  --data-urlencode "folder=/manual/RELEASE" \
  --data-urlencode "filterExistingFiles=false" \
  | jq -r '.[] | "\(.episodes[0].episodeNumber // "?")\t\(.quality.quality.name)\t\(.rejections|map(.reason)|join("; "))"' \
  | sort -n
```

Every row should map to a real episode number with an empty rejections column. `?` means the filename did not parse and needs hand-mapping — do that in the UI, which is far easier than constructing the API payload.

3. Import from the UI with mode **Move**, then `rmdir` the empty husk.

---

## 8. Known Issues & Workarounds

### 8.1 Season-Pack Imports Wedge at importPending

A season pack can leave all 26 queue entries at `trackedDownloadState: importPending` with the status message:

```
No files found are eligible for import in /downloads/<release>
```

**This message can be false.** Query `manualimport` for the same folder — if it returns every file mapped to an episode with zero rejections, the queue state is stale, not a real evaluation. `RefreshMonitoredDownloads` does not clear it.

**Workaround — build the ManualImport payload from the same endpoint and POST it:**

```bash
source /boot/config/arr-rescans.conf
FOLDER="/downloads/<release>"

curl -s -G "http://192.168.1.12:8989/api/v3/manualimport" -H "X-Api-Key: $SONARR_KEY" \
  --data-urlencode "folder=$FOLDER" --data-urlencode "filterExistingFiles=false" \
  | jq '[.[] | select(.episodes|length > 0) | {
      path, seriesId: .series.id, episodeIds: [.episodes[].id],
      quality, languages, releaseGroup, indexerFlags: 0
    }]' > /tmp/import.json

jq 'length' /tmp/import.json          # sanity-check the count
jq -r '.[0]' /tmp/import.json         # sanity-check the shape

jq -n --slurpfile f /tmp/import.json \
  '{name: "ManualImport", files: $f[0], importMode: "copy"}' > /tmp/import-cmd.json

curl -s -X POST "http://192.168.1.12:8989/api/v3/command" \
  -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d @/tmp/import-cmd.json | jq '{name, status, id}'
```

`importMode` must be `copy` for anything under the Syncthing tree.

**Monitor progress** — the command processes files serially at roughly a minute per file:

```bash
curl -s "http://192.168.1.12:8989/api/v3/command?pageSize=10" -H "X-Api-Key: $SONARR_KEY" \
  | jq -r '.[] | select(.name=="ManualImport") | {status, message}'
# → "Processing file 15 of 26"
```

Mid-run, the season's file count will briefly show one fewer than expected — the old file is deleted before the new one finishes writing. This is normal.

### 8.2 Clearing Stale Queue Entries

`arr-import-monitor` v1.4 reaps these automatically after 24 hours. To clear immediately:

```bash
source /boot/config/arr-rescans.conf
curl -s "http://192.168.1.12:8989/api/v3/queue?pageSize=100" -H "X-Api-Key: $SONARR_KEY" \
  | jq -r '.records[] | select(.title|test("<pattern>")) | .id' \
  | while read ID; do
      curl -s -X DELETE "http://192.168.1.12:8989/api/v3/queue/$ID?removeFromClient=false&blocklist=false" \
        -H "X-Api-Key: $SONARR_KEY"
    done
```

`removeFromClient=false` keeps the torrent seeding — essential, since the 14-day seedbox removal drives the deletion lifecycle.

Radarr equivalent uses port 7878 and `RADARR_KEY`; Lidarr uses 8686 and `/api/v1/`.

### 8.3 Unpackerr Path Caching

Unpackerr resolves the queue path at queue-tracking time. If Syncthing has not finished delivery at that moment, the cached path is wrong **indefinitely** — no retry corrects it. Fix:

```bash
docker restart unpackerr
```

`UN_START_DELAY=20m` applies after restarts.

**Env var syntax is indexed:** `UN_SONARR_0_PATHS_0=/downloads/sonarr`, not `UN_SONARR_0_PATHS`. The golift/cnfg library silently ignores unindexed list vars. The startup config dump in the container log confirms parsed paths.

Queue-driven mode only processes items with matching queue entries. Folder-watch mode is inotify-based, so pre-existing files may not trigger.

### 8.4 Syncthing Race Condition

`arr-rescans` retries every 5 minutes, so files mid-sync are caught on a later run. The settle guard (v4.6) is the direct defence — see [Section 6.2](#62-arr-rescans-v461).

### 8.5 Truncated / Prematurely Imported Files

Caught by `arr-import-verify` `TAIL_FAIL` at 04:30 daily. If confirmed truncated:

1. Play the tail to verify: `ffmpeg -sseof -60 -i "<file>" -f null -`
2. Delete the file in the *arr, blocklist the release, trigger a fresh search
3. **Check the seedbox copy first** — if it is intact, this was a Syncthing delivery race, not a bad release

### 8.6 arr-rescans Has No .syncthing.*.tmp Guard

**Open defect.** On 28 Aug 2026 a 26-file season pack triggered a scan while two files were still `.syncthing.*.tmp`. The settle guard did not catch it: 24 of 26 files had finished, so the byte signature was stable enough across a cycle to pass.

A direct check would close it:

```bash
find "$item" -name '.syncthing.*' -print -quit | grep -q . && continue
```

Structured like the RAR guard, evaluated before the settle guard. **Not yet implemented.**

### 8.7 Anime & Foreign-Language Title Mismatches

Sonarr stores the TVDB canonical title regardless of the search term used when adding. For a series only available under an alternate title (e.g. "Sousou no Frieren" vs "Frieren: Beyond Journey's End", "La Oficina" vs "The Office (MX)"), submit the alias to TVDB and refresh the series after approval. The `jq --arg` payload builder handles bracket characters in SubsPlease-style folder names.

### 8.8 Fake / Malicious Torrents

`arr-rescans` detects `.exe .bat .com .scr .js .vbs`, alerts Discord once per folder, and genuinely skips the scan. Blocklist the release in Sonarr/Radarr to trigger a search for a valid one.

> v4.3 had this check in a separate loop that only notified; the scan loop below it scanned the folder anyway, making the "Import skipped" message false. Merged into a single pass in v4.4.

### 8.9 TorrentLeech Timezone Mismatch

Negative ages (e.g. −284 minutes) on grabbed releases. Cosmetic.

### 8.10 Orphaned Seedbox Content

**Class of problem:** content in `~/Media-sync/<app>/` whose torrent no longer exists in qBittorrent. The torrent was removed at the seeding limit but the content was not, because the older `ShareLimitAction` did not include content removal.

**Why nothing on Caladan can fix it.** Syncthing's global index legitimately announces the content, so `arr-cleanup` correctly returns `tracked` and skips. Deleting locally would trigger a re-fetch. The deletion must originate on the seedbox.

**Symptoms:** directories in `Media-sync` far older than 14 days; a matching count of Locally Changed Items in Syncthing that never drains.

**Reconciliation:**

```bash
QB="https://ibiza.seedhost.eu/scytale1953/qbittorrent"
read -s -p "qb password: " QBPASS; echo
curl -s -c /tmp/qb.cookie -X POST "$QB/api/v2/auth/login" \
  --data-urlencode "username=scytale1953" --data-urlencode "password=$QBPASS" -H "Referer: $QB"

# Top-level directory name of every live torrent
curl -s -b /tmp/qb.cookie "$QB/api/v2/torrents/info" \
  | jq -r '.[].content_path' \
  | sed 's|^/home18/scytale1953/Media-sync/[^/]*/||' \
  | sed 's|/.*$||' | sort -u > /tmp/qb-tracked.txt

# Everything actually on disk
ssh scytale1953@ibiza.seedhost.eu \
  'for d in sonarr radarr lidarr; do ls -1 ~/Media-sync/$d; done' \
  | sort -u > /tmp/qb-ondisk.txt

wc -l /tmp/qb-tracked.txt /tmp/qb-ondisk.txt
comm -23 /tmp/qb-ondisk.txt /tmp/qb-tracked.txt      # ← orphans
```

**Sanity check the counts.** If `qb-tracked.txt` is implausibly short, the sed is mismatching and nearly everything will falsely appear orphaned. Never delete on an unsanity-checked diff.

**Before deleting, confirm each affected series imported:**

```bash
source /boot/config/arr-rescans.conf
SID=$(curl -s "http://192.168.1.12:8989/api/v3/series" -H "X-Api-Key: $SONARR_KEY" \
  | jq -r --arg t "TITLE" '.[] | select(.title==$t) | .id')
curl -s "http://192.168.1.12:8989/api/v3/episode?seriesId=$SID&includeEpisodeFile=true" \
  -H "X-Api-Key: $SONARR_KEY" \
  | jq -r '[.[] | select(.hasFile)] | group_by(.seasonNumber)[] | "S\(.[0].seasonNumber): \(length)"'
```

Then `rm -rfv` the orphan set on the seedbox. Deletions propagate inward through Syncthing and drain the Locally Changed counter.

> **Future work:** an `arr-orphans` script implementing this reconciliation on a schedule, dry-run by default with `ORPHANS_LIVE=1` to arm, matching the `arr-cleanup` convention.

### 8.11 SSH Consumes stdin in while-read Loops

```bash
# BROKEN — ssh eats the rest of the list, loop runs once
while IFS= read -r n; do ssh host "…$n…"; done < list.txt
```

Use `ssh -n`, redirect from a different fd, or send the whole list to a single remote session.

### 8.12 Prowlarr Indexer Rate Limits

`429 TooManyRequests` with "Indexer is disabled till …" suppresses RSS grabs library-wide for up to 24 hours. Check when grabs stop unexpectedly:

```bash
docker logs sonarr --since 1h 2>&1 | grep -iE "429|API Request Limit|disabled till"
```

### 8.13 SQLite Corruption (SQLite 3.53+)

`WHERE col IS NULL` is constant-folded to false on `NOT NULL` columns, making corrupted NULLs invisible. Unary-`+` (`WHERE +col IS NULL`) no longer defeats this. Working form:

```sql
WHERE typeof(col) = 'null'
```

**Recovery ladder:** `integrity_check` → `logs.db` shortcut → `REINDEX` → `typeof()` delete → `.recover` → scheduled backup restore.

### 8.14 Miscellaneous API Notes

- `/api/v3/parse` never populates `episodeFile`; use `/api/v3/episode?seriesId=N` for hasFile checks
- Empty API output usually means an unsourced conf — check `echo "${SONARR_KEY:0:4}"` first
- Lidarr is `/api/v1/`, not `/api/v3/`
- 7-Zip on Alpine lacks the RAR codec for licensing reasons — "Cannot open file as archive" means missing codec, not corrupt data
- NerdTools is unavailable on Unraid 7; `unrar` is not installed on the host. Manual RAR extraction must route through a container

---

## 9. Maintenance Procedures

### 9.1 Force a Manual Rescan

```bash
bash /boot/config/plugins/user.scripts/scripts/arr-rescans/script &
```

### 9.2 Dry-Run the Destructive Scripts

```bash
CLEANUP_LIVE=0 bash /boot/config/plugins/user.scripts/scripts/arr-cleanup/script 2>&1 | tail -30
REAP_LIVE=0    bash /boot/config/plugins/user.scripts/scripts/arr-import-monitor/script
```

**Always check the banner on the first line of output** — it states the mode the script actually resolved, not the mode you asked for. Before the fix in [Section 6.1.1](#611-environment-override-defect-and-fix), these invocations ran LIVE regardless.

```
arr-cleanup v2.0 — DRY RUN — grace 2d
arr-import-monitor v1.4 — reaper: DRY RUN (>= 24h)
```

`arr-cleanup` closes with a summary: `N residue item(s), N seedbox-tracked skipped, N too-young skipped, N errors`. A healthy system reports **0 residue** — everything present is either seedbox-tracked or inside the grace window. Baseline after the 28 Aug 2026 orphan purge: `0 residue, 47 seedbox-tracked, 8 too-young, 0 errors`.

A non-zero residue count is not automatically a problem — it means Syncthing's global index no longer announces those paths, which is exactly what the script is designed to clean. Read the per-item lines before arming.

### 9.3 Check Import Logs

```bash
docker logs sonarr --since 1h 2>&1 | grep -E "Imported|Import failed|Scan" | tail -30
docker logs sonarr --since 1h 2>&1 | grep -i error | tail -20
```

### 9.4 Check Sync Folder Contents

```bash
ls /mnt/user/media/download/sync/{sonarr,radarr,lidarr}/
ls /mnt/user/media/download/manual/
```

### 9.5 Check Sync Status

See [Section 3.4](#34-checking-sync-status-via-cli).

### 9.6 Update Credentials

```bash
nano /boot/config/arr-rescans.conf
```

All four scripts source this file — one edit covers everything. Never commit it.

### 9.7 Library Quality Survey

```bash
source /boot/config/arr-rescans.conf
SID=<seriesId>
curl -s "http://192.168.1.12:8989/api/v3/episode?seriesId=$SID&includeEpisodeFile=true" \
  -H "X-Api-Key: $SONARR_KEY" \
  | jq -r '[.[] | select(.hasFile)] | group_by(.seasonNumber)[]
           | "S\(.[0].seasonNumber)\t" + ([.[] | .episodeFile.quality.quality.name] | group_by(.) | map("\(.[0]):\(length)") | join(" "))'
```

Add `mediaInfo.resolution` to the projection to detect files labelled 1080p that are not:

```bash
  | jq -r '.[] | "\(.quality.quality.name)\t\(.mediaInfo.resolution // "n/a")"' | sort | uniq -c
```

> Anamorphic 4:3 content legitimately reports non-16:9 dimensions. The TNG Blu-ray remaster is 1440x1080 (some encodes 1456x1072) and is correctly labelled Bluray-1080p.

### 9.8 Backlog Triage

```bash
curl -s "http://192.168.1.12:8989/api/v3/wanted/cutoff?pageSize=2000&includeSeries=true" \
  -H "X-Api-Key: $SONARR_KEY" | jq -r '.records[].series.title' | sort | uniq -c | sort -rn
```

Not every entry is attainable. Before chasing a large backlog, consider whether an HD source exists at all:

| Show | Situation |
|------|-----------|
| Star Trek: TNG | Film-scanned Blu-ray remaster exists — fully attainable |
| Star Trek: Voyager | Video-finished, no HD remaster — 1080p releases are upscales |
| Star Trek: DS9 | Same as Voyager |
| Angel | HD remaster exists but drew reframing/colour complaints |
| The Drew Carey Show | SD-sourced |

Unmonitoring an unattainable series removes it from the backlog and stops pointless searching — see [Section 9.9](#99-unmonitoring-a-series).

### 9.9 Unmonitoring a Series

Series-level `monitored: false` stops all searching. Episode-level flags are what `wanted/cutoff` filters on, so both are needed to clear the backlog count.

```bash
source /boot/config/arr-rescans.conf
mkdir -p /boot/config/backups

for TITLE in "Star Trek: Voyager" "Angel"; do
  SID=$(curl -s "http://192.168.1.12:8989/api/v3/series" -H "X-Api-Key: $SONARR_KEY" \
    | jq -r --arg t "$TITLE" '.[] | select(.title==$t) | .id')
  echo "$TITLE -> id $SID"
  curl -s "http://192.168.1.12:8989/api/v3/series/$SID" -H "X-Api-Key: $SONARR_KEY" \
    > "/boot/config/backups/sonarr-series-$SID-$(date +%F).json"
done

# Substitute the real ids — placeholders in a for-loop are a shell syntax error
for SID in <id1> <id2>; do
  jq '.monitored = false' "/boot/config/backups/sonarr-series-$SID-$(date +%F).json" > /tmp/s$SID.json
  curl -s -X PUT "http://192.168.1.12:8989/api/v3/series/$SID" \
    -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
    -d @/tmp/s$SID.json | jq '{id, title, monitored}'

  IDS=$(curl -s "http://192.168.1.12:8989/api/v3/episode?seriesId=$SID" -H "X-Api-Key: $SONARR_KEY" \
    | jq -c '[.[].id]')
  curl -s -X PUT "http://192.168.1.12:8989/api/v3/episode/monitor" \
    -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
    -d "{\"episodeIds\": $IDS, \"monitored\": false}" | jq 'length'
done
```

Rollback is a straight PUT of the untouched backup.

> Series-level unmonitoring also stops new-episode RSS grabs. Safe for ended shows; do not use this pattern on anything still airing.

### 9.10 Grabbing a Specific Release

Sonarr picks the highest-ranked *allowed* release, which for a profile allowing Remux means a 186 GB season pack. To take a specific release instead, list candidates and POST the guid:

```bash
source /boot/config/arr-rescans.conf
SID=<seriesId>

curl -s "http://192.168.1.12:8989/api/v3/release?seriesId=$SID&seasonNumber=3" \
  -H "X-Api-Key: $SONARR_KEY" \
  | jq -r '.[] | select(.rejected==false)
           | "\(.quality.quality.name)\t\((.size/1073741824)|floor)GB\tseeders=\(.seeders)\t\(.title[0:55])"' \
  | sort -k2 -n

curl -s "http://192.168.1.12:8989/api/v3/release?seriesId=$SID&seasonNumber=3" \
  -H "X-Api-Key: $SONARR_KEY" \
  | jq -r '.[] | select(.rejected==false) | "\(.guid)\t\(.indexerId)\t\(.title[0:60])"'

curl -s -X POST "http://192.168.1.12:8989/api/v3/release" \
  -H "X-Api-Key: $SONARR_KEY" -H "Content-Type: application/json" \
  -d '{"guid":"<guid>","indexerId":<id>}' \
  | jq -r 'if type=="array" then .[].errorMessage else "pushed" end'
```

> A `/api/v3/release` **GET only lists**. Grabbing requires the POST.

**Prefer season searches for season-packed shows.** An episode-level search on a show distributed as season packs typically returns nothing usable. Rejections reading `Existing file meets cutoff` on a well-seeded release are correct behaviour, not a fault — that episode is already at target quality.

**Magnet-link results from public trackers** (indexer 9) do not count toward seedbox ratio and depend on DHT, which some seedbox configurations block. Prefer private-tracker `.torrent` URLs.

### 9.11 Rebuilding an Empty Staging Husk

```bash
rmdir /mnt/user/media/download/manual/<release>/
```

---

## 10. Rebuild Checklist

### 10.1 Unraid Containers

- [ ] Deploy `binhex-syncthing`, host networking, port 8384, config at `/mnt/cache/appdata/binhex-syncthing`
- [ ] Deploy Sonarr (8989), Radarr (7878), Radarr-4K, Lidarr (8686)
- [ ] **All `/config` mounts point at `/mnt/cache/appdata/<app>`**, never `/mnt/user/appdata`
- [ ] All media mounts use `/mnt/user` paths
- [ ] Add `/manual` → `/mnt/user/media/download/manual` to Sonarr, Radarr, Lidarr
- [ ] Manually add `/downloads` mapping to Lidarr (not present by default)
- [ ] Deploy Unpackerr mounted at the sync **root**, with indexed env vars (`UN_SONARR_0_PATHS_0`)
- [ ] Confirm `appdata` share is `shareUseCache="only"`

### 10.2 Syncthing

- [ ] Add Media sync folder, ID `sfqzb-cvm5v`, path `/media/sync` (container)
- [ ] Folder type **Receive Only**
- [ ] `ignorePerms=true`, `fsWatcherEnabled=true`
- [ ] Add seedbox as remote device
- [ ] Restore `.stignore` verbatim from [Section 3.3](#33-ignore-patterns)
- [ ] **Verify ordering: exclusions FIRST, includes next, `*` LAST**

### 10.3 *arr Apps

- [ ] Add qBittorrent download client per [Section 4.2](#42-download-client-configuration-all-arrs)
- [ ] Add app-specific remote path mappings per [Section 4.3](#43-remote-path-mappings)
- [ ] Configure quality profiles per [Section 5](#5-quality-profiles) — **verify `upgradeAllowed` and `cutoff` explicitly; stock defaults have upgrades disabled**
- [ ] Recreate the Radarr "BRRip/WEBRip Re-encode" custom format at −1000
- [ ] Connect Discord notifications in Sonarr/Radarr

### 10.4 Seedbox

- [ ] qBittorrent save path `/home18/scytale1953/Media-sync/`
- [ ] `GlobalMaxSeedingMinutes=20160`, `ShareLimitAction=RemoveWithContent`
- [ ] Pre-allocation off, `.!qB` suffix on, keep-unselected on
- [ ] Explicit save path per category
- [ ] Syncthing cron present
- [ ] Syncthing connected to Caladan device ID

### 10.5 User Scripts

- [ ] Install User Scripts plugin
- [ ] Create `/boot/config/arr-rescans.conf`; `chmod 600`
- [ ] Deploy all four scripts from the git repo (never retype)
- [ ] Schedules: `arr-rescans` `*/5`, `arr-import-monitor` `*/15`, `arr-cleanup` daily, `arr-import-verify` 04:30 daily
- [ ] Run each manually once and confirm output
- [ ] Verify Discord delivery
- [ ] Add `syncstatus` alias to `/boot/config/go`

### 10.6 Post-Rebuild Verification

- [ ] `arr-cleanup` dry run reports 0 residue
- [ ] `arr-import-verify --check-deps` resolves both library roots inside the ffmpeg container
- [ ] Sonarr and Radarr profile dumps match [Section 5](#5-quality-profiles)
- [ ] Sync a small release end to end and confirm automatic import

---

## 11. Change Log

### 28 August 2026

**Quality profiles — corrected**

- Sonarr profile 4 (HD-1080p) was `cutoff: 9` / `upgradeAllowed: false`; now `cutoff: 1002` / `true`
- Sonarr profile 6 (HD - 720p/1080p) was `cutoff: 4` / `upgradeAllowed: false`; now `cutoff: 7` / `true`
- Both were Sonarr stock defaults and had never been changed. The previous revision of this guide claimed settings that were not live.
- Radarr profiles were already correct — only Sonarr was affected
- Cutoff-unmet backlog moved from 290 → 831 → 1258 as each gate was cleared
- Documented that `minUpgradeFormatScore` has a hard validation floor of 1

**Containers**

- Sonarr and Lidarr `/config` moved from `/mnt/user/appdata` to `/mnt/cache/appdata`; all four *arrs now consistent
- `/trash` verified on `/mnt/user` for all four (previously an unconfirmed inference)
- `/manual` mount added to Sonarr, Radarr, Lidarr

**New content**

- Section 7, Manual Import Workflow — the FileZilla/FTP path, previously undocumented
- Section 8.1, season-pack import wedge and the ManualImport API payload workaround
- Section 8.10, orphaned seedbox content as a distinct problem class
- Section 5.4, the three independent gates governing cutoff-unmet
- shfs inode-comparison caveat

**Corrections to prior documentation**

- `arr-import-monitor` is **v1.4**, not v1.3 — gained a stale-queue reaper, `REAP_LIVE=1` armed
- `arr-rescans` creates **no marker files**; the prior guide's description of `.imported` / `.first_seen` as the sole re-scan guard has been obsolete since v4.4
- Syncthing config path is `/mnt/cache/appdata/binhex-syncthing`, not `/mnt/user/appdata`
- The `ignorePerms=false` note was wrong — the live value is `true`, so permission drift is not the source of Locally Changed Items; orphaned seedbox content is
- All four scripts are scheduled via the User Scripts plugin, not root cron

**Housekeeping**

- Removed `arr-rescan.sh` and `rescan.sh` from Sonarr appdata — both dead, both containing all three API keys in plaintext
- Cleared 16 orphaned release directories (~11 GB) from the seedbox
- Star Trek: TNG upgraded from mixed 720p/1080p to Bluray-1080p across seasons 1–3 and 5–7
- Voyager and Angel unmonitored as unattainable

**Script fixes (later the same day)**

- **Environment-override defect fixed** in `arr-cleanup` and `arr-import-monitor`. Sourcing the conf clobbered command-line arming switches, so `CLEANUP_LIVE=0` and `REAP_LIVE=0` ran LIVE. The dry-run procedure documented in every prior revision of this guide did nothing. See [Section 6.1.1](#611-environment-override-defect-and-fix). Both scripts verified against dry-run and bare-invocation assertions.
- `arr-cleanup` `STKEY` path moved to `/mnt/cache/appdata/binhex-syncthing` (line 45); all scripts now consistent
- Section 9.2 rewritten — the banner on the first line of output is the authoritative statement of resolved mode

**Open items**

- **API key rotation** — keys were exposed in the two removed scripts
- **`.syncthing.*.tmp` guard** for `arr-rescans` ([Section 8.6](#86-arr-rescans-has-no-syncthingtmp-guard))
- **`arr-orphans`** reconciliation script ([Section 8.10](#810-orphaned-seedbox-content))
- **TNG S04** — staged in `/manual`, parses clean at 26/26, awaiting import
- Verify the pinned-defaults block in `arr-rescans.conf` is deduplicated (`grep -c "pinned defaults"` should return 1)
- Persist the `syncstatus` alias in `/boot/config/go` ([Section 3.4](#34-checking-sync-status-via-cli))
- Tdarr music library ffmpeg health-check coverage (TV/Movies/Movies 4K covered; music gap)
- Update the `plex-caladan-analysis` skill's appdata paths from `/mnt/user` to `/mnt/cache`

---

*Caladan Media Automation Guide — canonical copy in `/MyFiles/Systems/Caladan`*
*Never commit `arr-rescans.conf` — it contains credentials*
