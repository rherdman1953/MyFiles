# Tdarr Library Codec Analysis & Configuration Recommendations
*Generated: 2026-04-30 — Updated: 2026-04-30*

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
| DTS | 1,312 | 7.3% | Limited device support — standard DTS Core is a conversion candidate |
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
| NVENC support | H.264, HEVC, AV1 |
| Node | MyInternalNode (single, internal, mapped) |
| Workers seen | transcodegpu (ornery-olm), transcodecpu (olive-oxen) |

---

## Current Configuration — Issues

The only active flow is **"English/Spanish Only - Remux"** (ID: `4UieIRZiG`).
It only strips non-English/Spanish audio and subtitle tracks, then remuxes — **no video re-encoding occurs.**

This explains why 12,471 files are queued but only 75 MB has been saved total.
The RTX 3060 is sitting largely idle for video encoding.

Additional issues found:
- `gpuSelect` is set to `-` in node config — GPU workers may not reliably target GPU 0
- Legacy Migz plugin stack is still defined on both libraries but flows are enabled — redundant
- Zero health checks have been run against 17,896 files
- No video codec conversion flow exists

> **Note:** Tdarr libraries can only be assigned one flow. All processing logic for Movies and TV must live inside a single flow with branching logic. See the combined flow below.

---

## Flow 1 — Movies & TV Pipeline (Combined)

A single flow handles all processing for the Movies and TV libraries. One `Custom JS Function` node analyses each file, determines what is needed, configures the FFmpeg command accordingly, and routes to either processing or no-action. All logic is handled in a single FFmpeg pass.

### Flow Structure

```
[Input File]
    ↓
[FFmpeg Command Start]
    ↓
[Custom JS Function: "Analyze & Configure"]
    ├─ Output 2: Nothing to do ──────────────────────────────→ [End]
    └─ Output 1: Processing needed
              ↓
[FFmpeg Command Remove Stream By Property]   ← strip non-eng/spa audio
[FFmpeg Command Remove Stream By Property]   ← strip non-eng/spa subtitles
[FFmpeg Command Set Container: mkv]
[FFmpeg Command Execute]
    ↓
[Compare File Size Ratio Live]   upper threshold: 101%
    ├─ OK  → [Replace Original File] → [Notify Radarr or Sonarr] → [Discord ✓]
    └─ Error (output grew) → [Discord ✗] → [End — keep original]
```

### Custom JS Function — Full Code

Paste this into the **Custom JS Function** node (found under the Tools category in the flow builder):

```javascript
module.exports = async (args) => {
  const file = args.inputFileObj;
  const streams = file.ffProbeData.streams;
  const videoStream = streams.find(s => s.codec_type === 'video');
  const audioStreams = streams.filter(s => s.codec_type === 'audio');
  const subtitleStreams = streams.filter(s => s.codec_type === 'subtitle');

  const videoCodec = videoStream?.codec_name ?? '';
  const container = file.container ?? '';

  // HDR detection — never re-encode HDR video
  const isHdr = !!(videoStream && (
    videoStream.color_transfer === 'smpte2084'       // HDR10 / HDR10+
    || videoStream.color_primaries === 'bt2020'      // BT.2020 wide colour gamut
    || videoStream.color_transfer === 'arib-std-b67' // HLG
  ));

  // Video decisions
  const isLegacyCodec = ['mpeg4', 'msmpeg4v3', 'mpeg2video'].includes(videoCodec);
  const isLegacyContainer = ['avi', 'm4v', 'mov'].includes(container);
  const needsVideoEncode = !isHdr && (videoCodec === 'h264' || isLegacyCodec);
  const cq = videoCodec === 'h264' ? 24 : 26; // h264 → CQ 24, legacy codecs → CQ 26

  // Audio decisions — only convert standard DTS Core, never DTS-HD MA or DTS:X
  const hasDtsCore = audioStreams.some(s =>
    s.codec_name === 'dts'
    && s.profile
    && !s.profile.includes('DTS-HD')
    && !s.profile.includes('DTS:X')
  );

  // Language decisions
  const keepLangs = ['eng', 'spa', 'und', ''];
  const hasNonEngAudio = audioStreams.some(s =>
    !keepLangs.includes(s.tags?.language ?? '')
  );
  const hasNonEngSubs = subtitleStreams.some(s =>
    !keepLangs.includes(s.tags?.language ?? '')
  );

  const needsProcessing = needsVideoEncode
    || isLegacyContainer
    || hasDtsCore
    || hasNonEngAudio
    || hasNonEngSubs;

  if (!needsProcessing) {
    // File is already optimal — no action needed
    return { outputFileObj: file, outputNumber: 2, variables: args.variables };
  }

  // Build FFmpeg output arguments directly on the command object
  const out = args.variables.ffmpegCommand.overallOuputArguments;

  // Video codec
  if (needsVideoEncode) {
    out.push(
      '-c:v', 'hevc_nvenc',
      '-rc', 'vbr',
      '-cq', String(cq),
      '-preset', 'p4',
      '-pix_fmt', 'yuv420p',
      '-profile:v', 'main'
    );
  } else {
    out.push('-c:v', 'copy');
  }

  // Audio codec — convert DTS Core to EAC3, copy everything else
  if (hasDtsCore) {
    out.push('-c:a', 'eac3', '-b:a', '640k');
  } else {
    out.push('-c:a', 'copy');
  }

  // Subtitles — always copy
  out.push('-c:s', 'copy');

  // Tell Tdarr this file needs processing
  args.variables.ffmpegCommand.shouldProcess = true;

  return { outputFileObj: file, outputNumber: 1, variables: args.variables };
};
```

### Remaining Node Settings

**FFmpeg Command Remove Stream By Property** — Audio language cleanup:

| Field | Value |
|-------|-------|
| Codec Type | `audio` |
| Property To Check | `tags.language` |
| Condition | `not_includes` |
| Values To Remove | `eng,spa,und` |

**FFmpeg Command Remove Stream By Property** — Subtitle language cleanup:

| Field | Value |
|-------|-------|
| Codec Type | `subtitle` |
| Property To Check | `tags.language` |
| Condition | `not_includes` |
| Values To Remove | `eng,spa` |

**FFmpeg Command Set Container:** `mkv`

**Compare File Size Ratio Live:**
| Field | Value |
|-------|-------|
| Compare Method | `estimatedFinalSize` |
| Upper Threshold | `101` |
| Lower Threshold | disabled / `0` |

> The 101% upper threshold rejects the output if it grew larger than the original. This catches H.264 sources that were already so well-compressed that NVENC at CQ 24 cannot improve them. The original file is kept and Tdarr marks the job as errored — review these files manually.

### How Each File Type Is Handled

| File type | Video | Audio | Result |
|-----------|-------|-------|--------|
| H.264 1080p, English, MKV | NVENC CQ 24 | copy | Re-encoded to HEVC |
| H.264 with non-eng tracks | NVENC CQ 24 | copy | Re-encoded + tracks stripped |
| H.264 with DTS Core | NVENC CQ 24 | → EAC3 640k | Re-encoded + audio converted |
| HEVC, MKV, English only | — | — | Output 2 → No action |
| HEVC with non-eng tracks | copy | copy | Remux, tracks stripped |
| HEVC with DTS Core | copy | → EAC3 640k | Audio-only conversion |
| MPEG-4 / AVI / M4V | NVENC CQ 26 | copy | Re-encoded + container → MKV |
| HDR content (any codec) | — | — | Output 2 → No action (HDR gate) |
| AV1 (any) | — | — | Output 2 → No action |
| DTS-HD MA or DTS:X | copy | copy | No audio conversion — lossless preserved |

---

## Flow 2 — Movies-4K Pipeline

> **This library (`/media/films-4k`) is not yet configured in Tdarr.** It requires its own library entry with this dedicated flow. The Movies & TV Pipeline must NOT be assigned to this library — video re-encoding of 4K HDR content would be destructive.

All 16 files are already HEVC. No video re-encoding is needed or appropriate. This flow only fixes the one MP4 container and strips any non-English/Spanish tracks.

### 4K Library — File Inventory

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

### Plex + Google TV Streamer Compatibility

| Format | Direct Play | Notes |
|--------|:-----------:|-------|
| HEVC 4K HDR10 MKV | ✅ | Full direct play |
| HEVC 4K SDR MKV | ✅ | Full direct play |
| EAC3 / EAC3 Atmos | ✅ | Native on Google TV Streamer |
| TrueHD Atmos | ⚠️ Passthrough only | Works via HDMI → Atmos AVR. Direct to TV: Plex transcodes TrueHD → AC3 server-side |
| MP4 container (Avatar: Fire and Ash) | ⚠️ | MKV is more reliable for HEVC in Plex — remux needed |

### Flow Structure

```
[Input File]
    ↓
[FFmpeg Command Start]
    ↓
[Check File Extension: mp4]
    ├─ YES → [FFmpeg Command Set Container: mkv]   ← video/audio/subs all copy by default
    |        [FFmpeg Command Execute]
    |        [Replace Original File]
    |        [Notify Radarr]
    |        → End
    |
    └─ NO
         ↓
[FFmpeg Command Remove Stream By Property]   codecType: audio | tags.language | not_includes | eng,spa,und
[FFmpeg Command Remove Stream By Property]   codecType: subtitle | tags.language | not_includes | eng,spa
[FFmpeg Command Execute]
    ↓
[Compare File Size Ratio Live]   upper threshold: 102%
    ├─ OK  → [Replace Original File] → [Notify Radarr] → End
    └─ Error → [End — keep original]
```

### Critical Rules for This Flow

| Rule | Reason |
|------|--------|
| Video stream: **always copy** | Re-encoding 4K HDR strips HDR metadata and destroys quality |
| Audio stream: **always copy** | TrueHD Atmos and EAC3 Atmos must be preserved intact |
| No DTS → EAC3 | No DTS files in this library |
| No size gate on container fix | Remux to MKV may be fractionally larger — acceptable |

### Folders to Ignore

Add these to the Movies-4K library's **Folders to Ignore** list to protect the Star Wars fan restorations:

```
Star.Wars.4K77.2160p.UHD.no-DNR.35mm.x265-v1.4
Star_Wars_Episode_V_The_Empire_Strikes_Back_1980_Project_4k80_v1.0_No-DNR_2160p
Star_Wars_Episode_VI_Return_of_the_Jedi_1983_Project_4k83_v2-0_No-DNR_35MM_2160P_DD_5-1_H265
```

---

## Library Assignment

| Library | Folder | Assigned Flow | Notes |
|---------|--------|---------------|-------|
| Movies | `/media/films` | Movies & TV Pipeline | Single combined flow |
| TV | `/media/tv` | Movies & TV Pipeline | Single combined flow |
| Movies-4K | `/media/films-4k` | Movies-4K Pipeline | **Only this flow — no others** |

---

## Decision Maker Settings

### Movies & TV Libraries

| Setting | Recommended Value |
|---------|------------------|
| Mode | Flows only (`settingsFlows: true`, `settingsPlugin: false`) |
| Process health checks | Enable — 0 health checks run against 17,896 files |
| Health check type | Thorough (ffmpeg re-mux test) |
| Folder watching | Enable for new content |
| Hold new files | 1 hour (default) — keep |

Remove the legacy Migz plugin stack entries from both libraries — they are superseded by the flow and add confusion.

### Movies-4K Library

| Setting | Recommended Value |
|---------|------------------|
| Mode | Flows only (`settingsFlows: true`, `settingsPlugin: false`) |
| Process health checks | Enable |
| Health check type | Basic (ffprobe only — avoid re-mux risk on large remux files) |
| Folder watching | Enable for new content |
| Hold new files | 1 hour (default) |
| Folders to Ignore | See above |

---

## Worker Configuration

| Worker Type | Recommended Count | Role |
|-------------|:-----------------:|------|
| transcodegpu | 2 | Video re-encode jobs (NVENC) within the Movies & TV Pipeline |
| transcodecpu | 2 | Remux / stream copy / audio-only jobs — keeps GPU slots free for encode work |

Fix: In Node settings set `gpuSelect` to `0` (not `-`) to ensure GPU workers reliably target the RTX 3060.

---

## Expected Outcomes

| Action | Files | Est. Space Saved |
|--------|------:|-----------------:|
| H.264 1080p → HEVC NVENC | ~9,942 | ~6.0–8.0 TB |
| H.264 720p/480p → HEVC NVENC | ~3,239 | ~0.8–1.2 TB |
| Legacy MPEG-4 / AVI / M4V → HEVC MKV | ~701 | ~50–80 GB |
| DTS Core → EAC3 (size-neutral) | ~1,312 | negligible |
| 4K MP4 → MKV remux | 1 | negligible |
| **Total estimated savings** | | **~7–10 TB** |

### Throughput Estimate (RTX 3060 NVENC)

- ~60–120 files/hour at 1080p (varies by source bitrate and duration)
- Full H.264 queue (~13,000 files): **~4–9 weeks** of continuous background processing
- Sunday 2am–6am processing gap (already in your schedule) adds proportional time

---

## Files Requiring No Action

| Content | Reason |
|---------|--------|
| HEVC video (all) | Already efficient; the JS function routes these to no-action |
| AV1 video (all 550) | State-of-the-art codec; do not re-encode |
| HDR content (43 files) | HDR gate in the JS function prevents any encode |
| All 4K video (16 files) | Already HEVC; Movies-4K flow never re-encodes video |
| TrueHD audio | Lossless; always copy, never transcode |
| FLAC audio (219 files) | Lossless; always copy, never transcode |
| DTS-HD MA / DTS:X | Lossless/object-based; JS function skips these, only DTS Core is converted |
| Star Wars fan restorations (3 files) | Explicitly ignored via Folders to Ignore setting |

---

## Implementation Order

1. **Add Movies-4K library** — point at `/media/films-4k`, assign Movies-4K Pipeline, add Folders to Ignore
2. **Fix Node gpuSelect** — change from `-` to `0` in Node settings
3. **Remove Migz plugin stack** entries from Movies and TV libraries
4. **Create Movies & TV Pipeline flow** using the Custom JS Function code above
5. **Assign the new flow** to both Movies and TV libraries
6. **Monitor the first 10–20 encodes** — check output quality and size ratios before letting it run unattended
7. **Enable health checks** on Movies and TV after the encode queue is clear

---

## Available Flow Nodes Reference

These are the community flow nodes confirmed installed on this system, relevant to the above flows:

| Category | Node Name | Used In |
|----------|-----------|---------|
| Input | Input File | Both flows |
| Tools | Custom JS Function | Movies & TV Pipeline |
| ffmpegCommand | FFmpeg Command Start | Both flows |
| ffmpegCommand | FFmpeg Command Execute | Both flows |
| ffmpegCommand | FFmpeg Command Set Container | Both flows |
| ffmpegCommand | FFmpeg Command Remove Stream By Property | Both flows |
| ffmpegCommand | FFmpeg Command Custom Arguments | Optional |
| file | Compare File Size Ratio Live | Both flows |
| file | Replace Original File | Both flows |
| file | Check File Extension | Movies-4K Pipeline |
| file | Check Stream Property | Optional (DTS profile check if needed) |
| audio | Check Audio Codec | Optional |
| tools | Notify Radarr or Sonarr | Both flows |
| tools | Check Flow Variable | Optional |
| tools | Set Flow Variable | Optional |

---

*Analysis based on Tdarr DB2 SQLite database, 47,216 job reports, and live nvidia-smi output.*
*Tdarr version: 2.70.01 — Node: MyInternalNode*
*Updated: 2026-04-30 — consolidated Movies & TV flows into single combined flow with branching JS logic; added Movies-4K pipeline; added flow node reference table*
