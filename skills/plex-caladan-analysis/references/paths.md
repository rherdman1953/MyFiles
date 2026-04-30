# Caladan: Full Path Reference

All paths confirmed from live system inspection.

## Plex

Base: `/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/`

### Logs
- `Logs/Plex Media Server.log` — current main log
- `Logs/Plex Media Server.1.log` through `.5.log` — rotated (check all)
- `Logs/Plex Transcoder Statistics.log` — per-session XML transcode reports
  - Contains: `<Session>` blocks with `<TranscodeSession>`, buffering states, bitrates, throttle reasons

### Config
- `Preferences.xml` — key fields:
  - `TranscoderTempDirectory` — where transcode segments go
  - `HardwareDevicePath` — GPU device (e.g. `/dev/dri/renderD128` or `/dev/nvidia0`)
  - `WanUploadSpeedKbps`, `WanPerStreamMaxUploadSpeedKbps` — bandwidth caps
  - `customConnections`, `allowedNetworks`
  - `PlexOnlineToken` — needed for API calls

### Database
- `Plug-in Support/Databases/com.plexapp.plugins.library.db` — main SQLite
  - Tables: `library_sections`, `section_locations`, `media_items`, `media_streams`, `metadata_items`, `activities`
  - Backup created as: `com.plexapp.plugins.library.db.bak-<timestamp>` (same dir)

## Tautulli

Base: `/mnt/user/appdata/tautulli/`

- `logs/tautulli.log` — main log; Plex API connectivity, auth errors, notification failures
- `logs/plex_websocket.log` — real-time event stream from Plex (play/pause/stop/transcode events)
- `logs/tautulli_api.log` — all API calls made to/from Tautulli

## ARR Stack

- `/mnt/user/appdata/sonarr/sonarr.db` — SQLite
- `/mnt/user/appdata/radarr/radarr.db` — SQLite
- `/mnt/user/appdata/radarr-4k/radarr.db` — SQLite
  - Config table: `SELECT Key, Value FROM Config WHERE Key IN ('importmode','copyusinghardlinks','usehardjoinpaths');`
- `/mnt/user/appdata/bazarr/config/config.yaml` — YAML; Plex URL, API key, webhook endpoint

## Library Mount Points (inside Docker containers)

- `/tv` → TV Shows
- `/movies` → Movies  
- `/movies-4k` → Movies (4K)
- `/music/CCM`, `/music/Rock` → Music
- `/concerts` → Concerts

`.plexignore` files exist at `/tv/.plexignore`, `/movies/.plexignore`, `/movies-4k/.plexignore`
