# Tdarr Library Codec Analysis & Configuration Recommendations
*Generated: 2026-04-30*

---

## Library Overview (17,896 total files)

### Video Codecs

| Codec | Count | % | Resolution Breakdown | Avg Size | Est. Total Storage |
|-------|------:|--:|----------------------|---------:|-------------------:|
| H.264 | 13,181 | 73.6% | 1080p: 9,942 / 720p: 1,567 / 480p: 1,515 / 576p: 157 | ~2.0 GB | ~26.3 TB |
| HEVC | 3,825 | 21.4% | 1080p: 3,736 / 720p: 32 / 4K: 4 / 480p: 27 / 576p: 26 | ~1.1 GB | ~4.3 TB |
| AV1 | 550 | 3.1% | 1080p: 550 | ~411 MB | ~221 GB |
| MPEG-4 (DivX) | 302 | 1.7% | 480p: 299 / 720p: 3 | ~429 MB | ~124 GB |
| MS-MPEG4v3 | 26 | 0.1% | 480p: 26 | ~178 MB | ~5 GB |
| MPEG-2 | 6 | <0.1% | 480p: 5 / 1080p: 1 | ~484 MB | ~3 GB |
| VP9 | 1 | <0.1% | 720p: 1 | — | — |

### Audio Codecs

| Codec | Count | % | Notes |
|-------|------:|--:|-------|
| AAC | 7,376 | 41.2% | Universally compatible, keep |
| EAC3 | 5,240 | 29.3% | Dolby Digital Plus, keep |
| AC3 | 3,126 | 17.5% | Dolby Digital, keep |
| DTS | 1,312 | 7.3% | Limited device support, conversion candidate |
| MP3 | 309 | 1.7% | Legacy, low priority conversion candidate |
| Opus | 249 | 1.4% | Efficient, keep |
| FLAC | 219 | 1.2% | Lossless, keep |
| TrueHD | 55 | 0.3% | Lossless, always keep |
| MP2 | 5 | <0.1% | Legacy, remux candidate |

### Containers

| Container | Count | % |
|-----------|------:|--:|
| MKV | 15,768 | 88.1% |
| MP4 | 1,760 | 9.8% |
| AVI | 213 | 1.2% |
| M4V | 154 | 0.9% |
| MOV | 1 | <0.1% |

### Special Content

| Type | Count | Action |
|------|------:|--------|
| HDR files (bt2020 / smpte2084 / HLG) | 43 | **Never re-encode** — skip entirely |
| HEVC Main 10 / 10-bit | Present | Skip unless container issue |

### Transcode Status

| Status | Count |
|--------|------:|
| Queued | 12,471 |
| Not Required | 5,379 |
| Transcode Success | 46 |
| **Total storage saved to date** | **75.7 MB** |

---

## Hardware

| Component | Detail |
|-----------|--------|
| GPU | NVIDIA GeForce RTX 3060 (12 GB VRAM) |
| Driver | 595.58.03 |
| CUDA | 13.2 |
| NVENC support | H.264, HEVC, **AV1** |
| Node | MyInternalNode (single, internal, mapped) |
| Workers seen | transcodegpu (ornery-olm), transcodecpu (olive-oxen) |

---

## Current Configuration — Issues

Your only active flow is **"English/Spanish Only - Remux"** (ID: `4UieIRZiG`).
It only strips non-English/Spanish audio and subtitle tracks, then remuxes — **no video re-encoding occurs.**

This explains why 12,471 files are queued but only 75 MB has been saved total.

**The RTX 3060 is sitting largely idle for video encoding.**

Additional issues found:
- `gpuSelect` is set to `-` in node config (unspecified), so GPU workers may not reliably target GPU 0
- Legacy Migz plugin stack is still defined on both libraries but flows are enabled — redundant
- Zero health checks have been run against 17,896 files
- Both libraries share one flow; no video codec conversion flow exists

---

## Recommended Flows

### Flow 1 — Keep (Minor Fix): "English/Spanish Only - Remux"

Your existing remux/language-strip flow is well-built. Keep it.

**Fix:** In Node settings, set `gpuSelect` to `0` instead of `-` to ensure GPU workers reliably target the RTX 3060.

---

### Flow 2 — New: "H.264 → HEVC NVENC"

**Target:** 13,181 H.264 files (~26 TB)
**Expected savings:** ~8–10 TB (30–40% file size reduction)

#### Flow Logic

```
[Input File]
    |
    ├── video_codec = h264? ── NO ──→ [No Action]
    |
    YES
    |
    ├── HDR? (bt2020 / smpte2084 / arib-std-b67) ── YES ──→ [No Action]
    |
    NO
    |
[FFmpeg: Begin Command]
[Set Video Encoder: h265_nvenc]
    preset:   p4
    CQ:       24 (1080p) / 26 (720p, 480p)
    pix_fmt:  yuv420p
    profile:  main
[Set Audio:     copy all streams]
[Set Subtitles: copy all streams]
[FFmpeg: Execute]
    |
    ├── output_size < 97% of input_size? ── NO ──→ [Keep Original, no replace]
    |
    YES
    |
[Replace Original File]
[Notify Radarr]
[Notify Sonarr]
[Discord: file processed ✓]
```

#### Key Settings Notes

| Setting | Value | Reason |
|---------|-------|--------|
| Encoder | `h265_nvenc` | 10–20× faster than libx265 on RTX 3060 |
| Preset | `p4` | Balanced quality/speed; p7 adds time with negligible quality gain |
| CQ 24 (1080p) | — | Visually lossless; matches libx265 CRF 22 output |
| pix_fmt | `yuv420p` | 8-bit SDR content — do not force 10-bit on SDR sources |
| 97% size check | — | Prevents replacing files where encoding didn't compress further |
| Audio | copy | Never re-encode audio in this flow |
| HDR gate | first check | HDR must be excluded — tone-mapping SDR would destroy the file |

---

### Flow 3 — New: "Legacy Format Cleanup"

**Target:** 302 MPEG-4 + 26 MS-MPEG4v3 + 6 MPEG-2 + 213 AVI + 154 M4V = ~701 files

#### Flow Logic

```
[Input File]
    |
    ├── codec IN (mpeg4, msmpeg4v3, mpeg2video)?  ── OR ──┐
    ├── container IN (avi, m4v, mov)?             ─────────┘
    |
    YES to any
    |
[FFmpeg: Begin Command]
[Set Video: h265_nvenc, CQ 26]
[Set Audio:
    - copy if codec IN (aac, ac3, eac3, dts, flac, truehd, opus)
    - convert to aac 192k if codec IN (mp3, mp2, other)]
[Set Output Container: mkv]
[FFmpeg: Execute]
    |
    ├── output_size < 95% of input_size? ── NO ──→ [Keep Original]
    |
    YES
    |
[Replace Original File]
[Notify Radarr / Sonarr]
```

---

### Flow 4 — Optional: "DTS Audio → EAC3"

**Target:** ~1,312 DTS files
**Why:** Standard DTS requires a license for direct play on most Plex clients, smart TVs, and streaming devices. EAC3 (Dolby Digital Plus) plays natively on virtually everything.

**Skip:** DTS:X and DTS-HD MA — these are lossless/object-based formats; downconverting loses quality. Only convert standard DTS Core.

#### Flow Logic

```
[Input File]
    |
    ├── audio_codec = dts? ── NO ──→ [No Action]
    |
    YES
    |
    ├── DTS:X or DTS-HD MA? ── YES ──→ [No Action — preserve lossless]
    |
    NO (standard DTS Core)
    |
[FFmpeg: Begin Command]
[Set Video: copy]
[Set Audio: convert dts → eac3, 640k, channels: copy (up to 7.1)]
[Set Subtitles: copy]
[FFmpeg: Execute]
    |
[Replace Original File]
[Notify Radarr / Sonarr]
```

---

### Flow 5 — New: "4K - Stream Cleanup & Container Fix"

**Target:** `/media/films-4k/` — 16 files, all HEVC, local Plex playback via Google TV Streamer

> **This library is not yet configured in Tdarr.** It requires its own library entry and a dedicated flow.
> The existing flows must NOT be assigned to this library — video re-encoding of 4K HDR content would be destructive.

#### 4K Library — File Inventory

| File | Codec | Container | Audio | Status |
|------|-------|-----------|-------|--------|
| Avatar (2009) | HEVC/x265 | MKV | EAC3 Atmos | OK |
| Avatar - Fire and Ash (2025) | HEVC/x265 | **MP4** | EAC3 Atmos | ⚠️ Fix container |
| Avatar - Way of Water (2022) | HEVC | MKV | TrueHD Atmos | OK |
| Blade Runner 2049 (2017) | HEVC/x265 | MKV | EAC3 | OK |
| Dune (2021) | HEVC | MKV | TrueHD Atmos | OK |
| Dune - Part Two (2024) | HEVC | MKV | TrueHD Atmos | OK |
| F1 (2025) | HEVC/x265 | MKV | EAC3 Atmos | OK |
| Ford v Ferrari (2019) | HEVC | MKV | TrueHD Atmos | OK |
| TRON - Ares (2025) | HEVC | MKV | TrueHD Atmos | OK |
| Top Gun (1986) | HEVC/x265 | MKV | TrueHD Atmos | OK |
| Top Gun: Maverick (2022) IMAX | HEVC | MKV | TrueHD Atmos | OK |
| Tron (1982) | HEVC/x265 | MKV | EAC3 Atmos | OK |
| Tron Legacy (2010) | HEVC/x265 | MKV | EAC3 | OK |
| Star Wars 4K77 | HEVC/x265 | MKV | — | SDR fan restoration — protected |
| Star Wars 4K80 (ESB) | HEVC/x265 | MKV | — | SDR fan restoration — protected |
| Return of the Jedi 4K83 | HEVC/x265 10-bit | MKV | DD 5.1 | SDR fan restoration — protected |

#### Plex + Google TV Streamer Compatibility

| Format | Direct Play | Notes |
|--------|:-----------:|-------|
| HEVC 4K HDR10 MKV | ✅ | Full direct play |
| HEVC 4K SDR MKV | ✅ | Full direct play |
| EAC3 / EAC3 Atmos | ✅ | Native on Google TV Streamer |
| TrueHD Atmos | ⚠️ Passthrough only | Works via HDMI → Atmos AVR. Direct to TV: Plex transcodes TrueHD → AC3 server-side (CPU load) |
| MP4 container (Avatar: Fire and Ash) | ⚠️ | Plex handles it but MKV is more reliable for HEVC — remux needed |

#### Flow Logic

```
[Input File]
    |
    ├── container = mp4?
    |       ↓ YES
    |   [FFmpeg: Begin Command]
    |   [Set Video:    copy]
    |   [Set Audio:    copy]
    |   [Set Subtitles: copy]
    |   [Set Output Container: mkv]
    |   [FFmpeg: Execute]
    |   [Replace Original File]
    |   [Notify Radarr]
    |       ↓ End
    |
    ├── Has non-English/Spanish audio or subtitle streams?
    |       ↓ YES
    |   [FFmpeg: Begin Command]
    |   [Remove audio streams: language not eng, not spa]
    |   [Remove subtitle streams: language not eng, not spa]
    |   [Set Video:    copy]      ← ALWAYS copy, never re-encode
    |   [Set Audio:    copy]      ← Preserve TrueHD Atmos / EAC3 Atmos intact
    |   [Set Subtitles: copy]
    |   [FFmpeg: Execute]
    |   [Replace Original File]
    |   [Notify Radarr]
    |
    └── No issues → [No Action]
```

#### Critical Rules for This Flow

| Rule | Reason |
|------|--------|
| Video stream: **always copy** | Re-encoding 4K HDR would strip HDR metadata and destroy quality |
| Audio stream: **always copy** | TrueHD Atmos and EAC3 Atmos must be preserved intact |
| No size gate | A remux may be fractionally larger — that is acceptable |
| No CQ/quality settings | This flow must never trigger any video encode path |
| No DTS → EAC3 conversion | No DTS files in this library; Flow 4 must not be assigned here |

#### Folders to Ignore (add to library settings)

Protect the irreplaceable Star Wars fan restorations by adding these to the library's "Folders to Ignore" list:

```
Star.Wars.4K77.2160p.UHD.no-DNR.35mm.x265-v1.4
Star_Wars_Episode_V_The_Empire_Strikes_Back_1980_Project_4k80_v1.0_No-DNR_2160p
Star_Wars_Episode_VI_Return_of_the_Jedi_1983_Project_4k83_v2-0_No-DNR_35MM_2160P_DD_5-1_H265
```

---

## Library Assignment

| Library | Folder | Assigned Flow(s) |
|---------|--------|-----------------|
| Movies | `/media/films` | Flow 1 → Flow 2 → Flow 3 → Flow 4 (optional) |
| TV | `/media/tv` | Flow 1 → Flow 2 → Flow 3 → Flow 4 (optional) |
| Movies-4K | `/media/films-4k` | Flow 5 only — **no other flows** |

Run Flow 1 (remux/language) first on Movies and TV — it's fast and risk-free. Queue video re-encode (Flow 2) after.

---

## Decision Maker Settings

### Movies & TV Libraries

| Setting | Recommended Value |
|---------|------------------|
| Mode | Flows only (`settingsFlows: true`, `settingsPlugin: false`) |
| Video exclude list | `hevc`, `av1` — already efficient, do not re-encode |
| Process health checks | Enable — 0 health checks run against 17,896 files |
| Health check type | Thorough (ffmpeg re-mux test) |
| Folder watching | Enable for new content |
| Hold new files | 1 hour (default) — good, keep |

Disable/remove the legacy Migz plugin stack entries from both libraries — they are superseded by flows and add confusion.

### Movies-4K Library

| Setting | Recommended Value |
|---------|------------------|
| Mode | Flows only (`settingsFlows: true`, `settingsPlugin: false`) |
| Video exclude list | `hevc`, `av1`, `h264` — never re-encode any 4K video |
| Process health checks | Enable |
| Health check type | Basic (ffprobe only — avoid any re-mux risk on large remux files) |
| Folder watching | Enable for new content |
| Hold new files | 1 hour (default) |
| Folders to Ignore | See Flow 5 section above for Star Wars fan restoration paths |

---

## Worker Configuration

| Worker Type | Recommended Count | Handles |
|-------------|:-----------------:|---------|
| transcodegpu | 2 | Flows 2, 3 (video re-encode — NVENC) |
| transcodecpu | 2 | Flows 1, 4, 5 (remux / stream copy / audio convert) |

**Why separate:** Remux and audio-only jobs (Flows 1, 4, 5) are I/O bound and don't need the GPU. Running them on CPU workers keeps both GPU slots free for encode-heavy jobs at all times.

---

## Expected Outcomes

| Action | Files | Est. Space Saved |
|--------|------:|-----------------:|
| H.264 1080p → HEVC NVENC | ~9,942 | ~6.0–8.0 TB |
| H.264 720p/480p → HEVC NVENC | ~3,239 | ~0.8–1.2 TB |
| Legacy MPEG-4 / AVI / M4V cleanup | ~701 | ~50–80 GB |
| DTS → EAC3 (optional, size-neutral) | ~1,312 | negligible |
| **Total estimated savings** | | **~7–10 TB** |

### Throughput Estimate (RTX 3060 NVENC)

- ~60–120 files/hour at 1080p (depending on source bitrate and duration)
- Full queue of ~13,000 H.264 files: **~4–9 weeks** of continuous background processing
- Pausing during peak hours (2am–6am blackout already present on Sunday in your schedule) will add proportional time

---

## Files Requiring No Action

| Content | Reason |
|---------|--------|
| HEVC video (all) | Already efficient; skip unless container issue |
| AV1 video (all 550) | State-of-the-art codec; do not re-encode |
| HDR content (43 files in main library) | Must never be re-encoded without a proper HDR-aware pipeline |
| All 4K video (16 files) | Already HEVC; re-encoding would be destructive |
| TrueHD audio (55 files) | Lossless; always copy, never transcode |
| FLAC audio (219 files) | Lossless; always copy, never transcode |
| DTS-HD MA / DTS:X audio | Lossless/object-based; keep as-is, only standard DTS Core is a conversion candidate |
| Star Wars fan restorations (3 files) | Irreplaceable grain-preserved sources; explicitly ignored in 4K library |

---

## Complete Flow Summary

| Flow | Name | Libraries | Action | GPU? |
|------|------|-----------|--------|:----:|
| 1 | English/Spanish Only - Remux | Movies, TV | Strip non-eng/spa audio & subtitle tracks | No |
| 2 | H.264 → HEVC NVENC | Movies, TV | Re-encode H.264 → HEVC (skip HDR, skip already-HEVC) | Yes |
| 3 | Legacy Format Cleanup | Movies, TV | Re-encode MPEG-4/AVI/M4V → HEVC MKV | Yes |
| 4 | DTS Audio → EAC3 | Movies, TV | Convert standard DTS Core → EAC3 640k (skip DTS-HD/DTS:X) | No |
| 5 | 4K - Stream Cleanup & Container Fix | Movies-4K **only** | Remux MP4→MKV; strip non-eng/spa tracks; video always copy | No |

---

## Implementation Order

1. **Add Movies-4K library** to Tdarr pointing at `/media/films-4k`, assign Flow 5, add ignore folders
2. **Fix Node gpuSelect** from `-` to `0` in Node settings
3. **Remove Migz plugin stack** entries from Movies and TV libraries
4. **Run Flow 1** across Movies and TV (fast, safe, no quality risk)
5. **Enable Flow 2** once Flow 1 queue is clear — monitor first few encodes to validate CQ settings
6. **Run Flow 3** for legacy format cleanup in parallel or after Flow 2
7. **Enable Flow 4** (optional) after evaluating whether DTS compatibility is a real issue on your setup
8. **Enable health checks** on Movies and TV after transcoding is complete

---

*Analysis based on Tdarr DB2 SQLite database, 47,216 job reports, and live nvidia-smi output.*
*Tdarr version: 2.70.01 — Node: MyInternalNode*
*Updated: 2026-04-30 — added Movies-4K library analysis (Flow 5), per-library Decision Maker settings, and implementation order*
