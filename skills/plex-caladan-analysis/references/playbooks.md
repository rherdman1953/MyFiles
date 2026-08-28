# Analysis Playbooks

---

## `performance` — Transcoding Failures, HW→SW Fallback, Buffering

### Step 1: Check main Plex log for NVENC failures
```bash
grep -i "nvenc\|hwaccel\|hardware\|fallback\|software transcode" \
  "/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/Logs/Plex Media Server.log" \
  | tail -100
```
Look for: `Failed to open NVENC`, `Falling back to software`, `hw transcode unavailable`

### Step 2: Check Transcoder Statistics log
```bash
cat "/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/Logs/Plex Transcoder Statistics.log" \
  | grep -A5 -B2 "bufferCount\|throttleReason\|videoDecision\|audioDecision"
```
Key XML fields:
- `<videoDecision>` — `transcode` vs `copy` vs `directplay`
- `<throttleReason>` — why transcode slowed (bandwidth, CPU, GPU limit)
- `<bufferCount>` — number of buffer events in session

### Step 3: GPU health check
```bash
docker exec plex nvidia-smi
nvidia-smi --query-gpu=name,memory.used,memory.free,utilization.gpu --format=csv
```

### Step 4: Check VRAM headroom
Ollama reserves ~2GB overhead via `OLLAMA_GPU_OVERHEAD`. If active Ollama model + active Plex
NVENC sessions exceed ~10GB VRAM, expect transcode failures. Check both concurrently.

### Step 5: Check rotated logs for historical failures
```bash
for f in "/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/Logs/Plex Media Server"*.log; do
  echo "=== $f ==="; grep -c "NVENC\|fallback" "$f" 2>/dev/null
done
```

---

## `remote-streaming` — Remote Client Buffering, Bandwidth, Relay

### Step 1: Check remote access state
```bash
# Get token from Preferences.xml first
TOKEN=$(grep -oP 'PlexOnlineToken="\K[^"]+' \
  "/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/Preferences.xml")
curl -s "http://192.168.1.12:32400/myplex/account?X-Plex-Token=$TOKEN" | grep -i "mappingState\|mappingError\|publicAddress"
```
`mappingState="mapped"` = direct connections working. `"failed"` = relay only.

### Step 2: Check bandwidth caps in Preferences.xml
```bash
grep -E "WanUpload|WanPerStream|LanUpload" \
  "/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/Preferences.xml"
```

### Step 3: Check Tautulli websocket log for stream events
```bash
grep -i "transcode\|buffer\|remote\|relay" \
  /mnt/user/appdata/tautulli/logs/plex_websocket.log | tail -50
```

### Step 4: Check Tautulli main log for Plex connectivity
```bash
grep -i "error\|warning\|timeout\|connect" \
  /mnt/user/appdata/tautulli/logs/tautulli.log | tail -50
```

---

## `codec-tdarr` — Codec Survey & Tdarr Retranscode Planning

Goal: determine optimal target codec given RTX 3060 capabilities and client mix.

### Step 1: Codec inventory from Plex DB
```bash
sqlite3 "/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db" \
"SELECT mi.container, ms.codec, COUNT(*) as count
 FROM media_items mi
 JOIN media_streams ms ON ms.media_item_id = mi.id
 WHERE ms.stream_type_id = 1
 GROUP BY mi.container, ms.codec
 ORDER BY count DESC;"
```

### Step 2: Resolution breakdown
```bash
sqlite3 "...com.plexapp.plugins.library.db" \
"SELECT ms.width, ms.height, COUNT(*) as count
 FROM media_streams ms
 WHERE ms.stream_type_id = 1
 GROUP BY ms.width, ms.height
 ORDER BY count DESC;"
```

### Step 3: HDR/SDR breakdown (check `color_transfer` field)
```bash
sqlite3 "...com.plexapp.plugins.library.db" \
"SELECT color_trc, COUNT(*) FROM media_streams
 WHERE stream_type_id = 1
 GROUP BY color_trc ORDER BY 2 DESC;"
```
`smpte2084` or `arib-std-b67` = HDR content.

### Step 4: RTX 3060 codec support matrix
| Codec | NVENC encode | NVDEC decode | Notes |
|-------|-------------|-------------|-------|
| H.264 (AVC) | ✅ | ✅ | Universal client support |
| H.265 (HEVC) 8-bit | ✅ | ✅ | Good compression, most modern clients |
| H.265 (HEVC) 10-bit | ✅ | ✅ | Required for HDR passthrough |
| AV1 | ✅ (Ampere+) | ✅ | Best compression, limited client support |
| VP9 | ❌ encode | ✅ | Decode only |

### Step 5: Tdarr recommendation framework
- **High-bitrate H.264 1080p** → transcode to H.265 (HEVC) 8-bit, CRF 20-22, saves ~40-50%
- **4K HDR content** → keep HEVC 10-bit or transcode to HEVC 10-bit, do NOT strip HDR
- **Old MPEG2/VC-1/XviD** → transcode to H.264 for universal compatibility
- **AV1** → only if client mix supports it (check client-compat playbook first)

---

## `client-compat` — Client Compatibility Survey

### Common client direct play capabilities
| Client | H.264 | HEVC 8-bit | HEVC 10-bit | AV1 | Notes |
|--------|-------|------------|------------|-----|-------|
| Apple TV 4K (2nd gen+) | ✅ | ✅ | ✅ | ✅ | Excellent |
| Apple TV HD | ✅ | ✅ | ✅ | ❌ | |
| iOS 14+ | ✅ | ✅ | ✅ | ❌ | |
| Android TV (modern) | ✅ | ✅ | varies | varies | Check per device |
| Roku (2019+) | ✅ | ✅ | limited | ❌ | |
| Fire TV Stick 4K Max | ✅ | ✅ | ✅ | ✅ | |
| Chrome/Firefox browser | ✅ | ❌ | ❌ | varies | Always transcodes HEVC |
| Plex Web (Chrome) | ✅ | ❌ | ❌ | ❌ | Worst for direct play |
| Windows Plex app | ✅ | ✅ | ✅ | ✅ | |
| Android Plex app | ✅ | varies | varies | ❌ | Hardware-dependent |

Check Tautulli history to identify which clients Rich actually uses before optimizing.

### Step: Query Tautulli DB for client breakdown
```bash
sqlite3 /mnt/user/appdata/tautulli/tautulli.db \
"SELECT player, platform, COUNT(*) as streams,
        SUM(CASE WHEN transcode_decision='direct play' THEN 1 ELSE 0 END) as direct_play,
        SUM(CASE WHEN transcode_decision='transcode' THEN 1 ELSE 0 END) as transcoded
 FROM session_history
 GROUP BY player, platform
 ORDER BY streams DESC LIMIT 20;"
```

---

## `health-check` — General Log Review

Quick health scan across all sources:
1. Run `performance` Step 1 + Step 3
2. Run `remote-streaming` Step 1 + Step 2
3. Check Tautulli main log for last 24h errors
4. Check Docker container status: `docker ps --filter name=plex --filter name=tautulli`
5. Summarize: any errors, GPU health, remote access state, open issues
