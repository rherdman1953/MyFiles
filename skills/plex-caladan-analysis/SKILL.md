---
name: plex-caladan-analysis
description: >
  Use this skill whenever the user asks to analyze Plex or Tautulli data on their Unraid server
  (Caladan). Triggers include: analyzing logs for performance issues, transcoding failures,
  buffering, bandwidth problems, HW/SW transcode fallback, codec analysis, client compatibility
  checks, Tdarr retranscode planning, library codec surveys, remote streaming issues, or any
  query referencing Plex, Tautulli, Sonarr, Radarr, Bazarr, or the media stack on Caladan.
  Always use this skill when the user wants to investigate or optimize their media server setup —
  even if they don't say "Caladan" explicitly.
---

# Plex / Caladan Analysis Skill

This skill provides all environment context for analyzing Rich's Plex media stack on Caladan
(Unraid server, RTX 3060 12GB VRAM, Docker-based). Always produce output as a **structured
breakdown** with clearly labeled sections.

---

## System Context

- **Server**: Caladan — Unraid, Docker stack
- **GPU**: RTX 3060, 12GB VRAM (NVENC/NVDEC hardware transcoding)
- **Plex container**: `plex` (binhex or official)
- **Network**: LAN at 192.168.1.x, gateway 192.168.1.1, pfSense router at 192.168.1.12

---

## Data Sources

See `references/paths.md` for full annotated path list. Summary below.

### Plex Logs
| File | Purpose |
|------|---------|
| `.../Logs/Plex Media Server.log` | Main log — errors, transcode decisions, NVENC events |
| `.../Logs/Plex Media Server.{1-5}.log` | Rotated logs (check all for history) |
| `.../Logs/Plex Transcoder Statistics.log` | Per-session XML: buffering states, bitrates, transcode decisions |

Base path: `/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/`

### Plex Config & DB
| File | Purpose |
|------|---------|
| `Preferences.xml` | HW device path, WAN rates, port mapping mode, token |
| `Plug-in Support/Databases/com.plexapp.plugins.library.db` | SQLite: library sections, activities |

### Tautulli Logs
| File | Purpose |
|------|---------|
| `/mnt/user/appdata/tautulli/logs/tautulli.log` | Main log — Plex connectivity, websocket errors |
| `/mnt/user/appdata/tautulli/logs/plex_websocket.log` | Websocket event stream |
| `/mnt/user/appdata/tautulli/logs/tautulli_api.log` | API call log |

### ARR Stack DBs
| File | Purpose |
|------|---------|
| `/mnt/user/appdata/sonarr/sonarr.db` | SQLite — import mode, config |
| `/mnt/user/appdata/radarr/radarr.db` | SQLite — same structure |
| `/mnt/user/appdata/radarr-4k/radarr.db` | SQLite — 4K library config |
| `/mnt/user/appdata/bazarr/config/config.yaml` | Plex integration, API key, webhook config |

### Library Roots
| Path | Library |
|------|---------|
| `/tv` | TV Shows |
| `/movies` | Movies |
| `/movies-4k` | Movies (4K) |
| `/music/CCM`, `/music/Rock` | Music |
| `/concerts` | Concerts |

### Runtime / API Sources
```bash
docker inspect plex                        # container config, device passthrough, env vars
docker exec plex nvidia-smi               # GPU visibility inside container
nvidia-smi                                 # host GPU status
lspci                                      # hardware detection
ip route                                   # routing / gateway
```

API endpoints (token from Preferences.xml):
```
http://192.168.1.12:32400/myplex/account?X-Plex-Token=<token>   # remote access mapping
https://plex.tv/api/resources?X-Plex-Token=<token>              # advertised external IPs
```

---

## Key SQLite Queries

```sql
-- Library section paths
SELECT name, root_path FROM section_locations
JOIN library_sections ON section_locations.library_section_id = library_sections.id;

-- Activities table schema
.schema activities

-- Sonarr/Radarr import mode
SELECT Key, Value FROM Config WHERE Key IN ('importmode','copyusinghardlinks','usehardjoinpaths');

-- Codec survey (for Tdarr planning)
SELECT container, video_codec, COUNT(*) as count
FROM media_items
GROUP BY container, video_codec
ORDER BY count DESC;

-- Resolution breakdown
SELECT width, height, COUNT(*) as count
FROM media_streams
WHERE stream_type = 1
GROUP BY width, height ORDER BY count DESC;
```

---

## Analysis Playbooks

Read `references/playbooks.md` for detailed step-by-step instructions per analysis type.
Choose the relevant playbook based on the user's query:

| User asks about... | Playbook |
|-------------------|---------|
| Transcoding failures, HW→SW fallback, buffering | `performance` |
| Remote client issues, bandwidth, relay vs direct | `remote-streaming` |
| Best codec for library, Tdarr configuration | `codec-tdarr` |
| Client compatibility, what each client can direct play | `client-compat` |
| General log review, health check | `health-check` |

---

## Output Format

Always structure responses as:

```
## Summary
One paragraph: what was found and the severity.

## [Issue Type / Analysis Area]
### Finding
What was observed (with log line excerpts or query results where relevant).
### Impact
Who/what is affected.
### Recommendation
Specific actionable fix.

## [Next Issue Type...]
...

## Priority Action List
Numbered list of recommended actions, highest priority first.
```

---

## Important Notes

- Unraid's root filesystem is RAM-based — `/root/.bashrc`, `/root/.local/bin` are wiped on reboot. Persistent config lives in `/boot/config/go`.
- Claude Code is at `/mnt/user/appdata/claude-bin/claude` (persistent).
- Mullvad VPN must be **off** when using Anthropic cloud API from Pop!_OS desktop.
- Ollama runs in Docker on Caladan with `OLLAMA_GPU_OVERHEAD` set to reserve ~2GB VRAM for Plex transcoding headroom.
- RTX 3060 supports NVENC H.264 and H.265 (HEVC) — relevant for Tdarr codec choices.
