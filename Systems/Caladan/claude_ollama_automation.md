# Claude Code & Ollama on Caladan — Runbook

**Last Updated:** 20 October 2026 (rev 1)
**Companion to:** `caladan_automation_guide.md` (Sections 6.8, 8.20, 9.13, 10.7)

How to run Claude Code on Caladan for Plex, Tautulli and Unraid log review, how it is wired, and what to check when it misbehaves.

---

## Contents

1. [Quick Start](#1-quick-start)
2. [Cloud or Local](#2-cloud-or-local)
3. [How It Is Wired](#3-how-it-is-wired)
4. [Using It Well](#4-using-it-well)
5. [Local Mode and Ollama](#5-local-mode-and-ollama)
6. [Ollama Report Scripts](#6-ollama-report-scripts)
7. [Common Changes](#7-common-changes)
8. [Troubleshooting](#8-troubleshooting)
9. [Rebuild From Scratch](#9-rebuild-from-scratch)
10. [Appendix A: Launcher Source](#appendix-a-launcher-source)
11. [Appendix B: CLAUDE.md Source](#appendix-b-claudemd-source)
12. [Change Log](#change-log)

---

## 1. Quick Start

From the Pop!_OS desktop:

```bash
ssh root@192.168.1.12
claude-caladan cloud
```

The first line printed is the banner. Check it before typing anything:

```
backend=cloud model=claude-sonnet-5-5 cwd=/mnt/cache/appdata/claude-work
```

Then ask in plain English, for example:

```
Review today's Plex Media Server.log: group the ERROR and WARN lines, explain what each group means, and tell me what needs action.
```

Leave the session with `/exit` or Ctrl+D.

| Command | What it does |
|---------|--------------|
| `claude-caladan cloud` | Anthropic models — use for real investigations |
| `claude-caladan` | Local Ollama (`qwen3:8b`) — quick lookups you will check yourself |
| `claude-caladan cloud --continue` | Resume the most recent session |
| `claude-caladan cloud -p "question"` | One-shot answer, no interactive session |

Anything after the mode is passed straight to Claude Code.

> **Do not run plain `claude`** for this work. It skips the work folder, the log-folder access and
> the `CLAUDE.md` rules, and uses whatever `ANTHROPIC_*` variables happen to be in the shell.
> The old `claude-local` / `claude-cloud` aliases are gone; a shell opened before 20 Oct 2026
> may still have them, and they point at the rotated key.

---

## 2. Cloud or Local

**Default to cloud.** Decided 20 Oct 2026 after testing both on the same request.

| | Cloud | Local (`qwen3:8b`) |
|--|-------|--------------------|
| Reliability on multi-step tasks | Good | Poor — loses track, misreads tool results |
| Speed | Seconds per step | ~3 minutes for a two-search question |
| Cost | API usage | Free; uses GPU shared with Plex |
| Data leaves the box | Yes, to Anthropic | No |

**What went wrong locally (20 Oct 2026).** Asked to grep today's Plex log for ERROR lines, the model ran the right search, got back "1 file matched" — meaning matches existed — and reported none. The log had 56. Claude Code's Grep tool returns file names by default; the small model never asked for the lines.

Use local mode only when you will check the answer yourself, or when the data must not leave Caladan.

The welcome box shows "API Usage Billing" in both modes. In local mode that label is cosmetic — requests go to `localhost:11434` and nothing is billed.

---

## 3. How It Is Wired

### 3.1 Files

| Path | Survives reboot? | Purpose |
|------|------------------|---------|
| `/mnt/user/appdata/claude-bin/claude` | Yes (array) | Claude Code binary, v2.1.100 |
| `/boot/config/claude-caladan.sh` | Yes (flash) | Launcher master copy — [Appendix A](#appendix-a-launcher-source) |
| `/usr/local/bin/claude-caladan` | No — copied at boot | What you actually run |
| `/mnt/cache/appdata/claude-config/` | Yes (cache) | Claude Code config: login, history, settings, sessions. Mode `700` |
| `/mnt/cache/appdata/claude-config/cloud.env` | Yes (cache) | One line: `ANTHROPIC_API_KEY=sk-ant-…`. Mode `600` |
| `/mnt/cache/appdata/claude-work/` | Yes (cache) | Working folder Claude Code starts in |
| `/mnt/cache/appdata/claude-work/CLAUDE.md` | Yes (cache) | House rules, loaded every session — [Appendix B](#appendix-b-claudemd-source) |
| `/boot/config/bash_profile` | Yes (flash) | Master profile; sets `CLAUDE_LOCAL_MODEL` |
| `/root/.bash_profile` | No — copied at boot | Live profile your SSH shell reads |

`/root` is RAM on Unraid and is wiped every boot, so nothing Claude-related may live only there. `/root/.claude` still exists from before the change; it is no longer used because `CLAUDE_CONFIG_DIR` points elsewhere.

### 3.2 What the `go` file does

Relevant lines in `/boot/config/go`:

```bash
export PATH="/mnt/user/appdata/claude-bin:$PATH"
cp /boot/config/bash_profile /root/.bash_profile
cp /boot/config/claude-caladan.sh /usr/local/bin/claude-caladan
chmod +x /usr/local/bin/claude-caladan
```

The `go` file must hold **no** API keys and no `ANTHROPIC_*` variables. Its exports reach only processes started at boot, not SSH sessions, which is why the earlier selector there never affected interactive use.

Check it any time:

```bash
grep -n -e sk-ant -e ANTHROPIC -e claude /boot/config/go
```

Expected: the PATH line and the two launcher lines, nothing else.

### 3.3 What the launcher does

1. Reads the mode from the first argument (`local` if none).
2. Sets `CLAUDE_CONFIG_DIR=/mnt/cache/appdata/claude-config`.
3. **Local:** points Claude Code at Ollama (`ANTHROPIC_BASE_URL=http://localhost:11434`), uses `$CLAUDE_LOCAL_MODEL` (fallback `glm-4.7-flash`, which does not fit the GPU — keep the variable set), and exits if Ollama does not answer.
4. **Cloud:** clears any Ollama variables, loads `cloud.env` if present, uses `claude-sonnet-5-5`. With no `cloud.env` it falls back to the claude.ai login stored in the config dir.
5. Changes to the work folder, prints the banner, and starts Claude Code with the Plex and Tautulli log folders added through `--add-dir`.

### 3.4 What Claude Code can reach

- **The work folder** — full read/write.
- **Plex logs** (`/mnt/cache/appdata/plex/Library/Application Support/Plex Media Server/Logs`) and **Tautulli logs** (`/mnt/cache/appdata/tautulli/logs`) — added folders.
- **Anything else** through shell commands, which Claude Code asks permission to run.

`CLAUDE.md` tells it to stay read-only unless you ask, never open a live SQLite database, use `/mnt/cache` paths, and mask secrets. Those are instructions, not enforcement — read each command before approving it.

---

## 4. Using It Well

### 4.1 Prompts that work

```
What do the Plex logs say about transcoding in the last 24 hours? Was anything falling back from hardware to software?
```
```
Check Tautulli's logs for Plex connection or websocket errors this week.
```
```
Plex restarted several times today. Line up the log rotations with docker inspect plex and tell me whether they were crashes or updates.
```
```
Copy the Sonarr database to /tmp and tell me which series have the most cutoff-unmet episodes.
```

Name the time window, and say what you want back — a count, a cause, or a fix.

### 4.2 Check what it actually did

Press **Ctrl+O** to expand collapsed tool calls ("Read 1 file", "Searched for 2 patterns"). Look at:

- **The path** — should be under the Plex or Tautulli log folder, not `claude-work`.
- **The pattern** — is it what you meant?
- **The raw result** — does the summary match it?

Press Ctrl+O again to collapse.

### 4.3 Spot-check a log answer yourself

```bash
LOG="/mnt/cache/appdata/plex/Library/Application Support/Plex Media Server/Logs/Plex Media Server.log"
grep -c " ERROR - " "$LOG"                                      # all ERROR lines in the current log
grep "^$(date '+%b %d, %Y')" "$LOG" | grep -c " ERROR - "       # today's only
grep " ERROR - " "$LOG" | sed 's/^.* ERROR - //; s/[0-9]\{3,\}/N/g' | sort | uniq -c | sort -rn | head -15
```

The last line groups repeats by replacing long numbers with `N`.

### 4.4 Reading Plex log rotation

`X.log` is current, `X.1.log` the previous run, down to `X.5.log`. Every rotation of `Plex Media Server.log` is a Plex restart. New `Plex Crash Uploader` files at the same time look like crashes, but **container updates produce the same pattern** (the 20 Oct 06:31 and 07:13 restarts were updates). Check against `docker inspect plex --format '{{.State.StartedAt}}'` before calling it a crash.

---

## 5. Local Mode and Ollama

### 5.1 Why local needs 32k context

Claude Code sends ~20k tokens of instructions and tool definitions on every request, before any log content. Ollama's built-in default context is 4096. When the prompt is longer, Ollama keeps the tail and drops the rest — **silently**, apart from a log line:

```
msg="truncating input prompt" limit=2050 prompt=19857 keep=4 new=2050
```

The model then sees a fragment and answers something unrelated. This is what happened on the first local test.

### 5.2 Ollama container settings

Unraid Docker tab → `ollama` → Edit. Set on 20 Oct 2026:

| Variable | Value |
|----------|-------|
| `OLLAMA_CONTEXT_LENGTH` | `32768` |
| `OLLAMA_FLASH_ATTENTION` | `1` |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` |
| `OLLAMA_HOST` | `0.0.0.0:11434` (pre-existing) |
| `OLLAMA_ORIGINS` | `*` (pre-existing) |

`OLLAMA_GPU_OVERHEAD` is **not** set, although older notes say it reserves VRAM for Plex. Open item.

### 5.3 Model choice

The RTX 3060 has 12 GB, shared with Plex transcoding and Tdarr's internal node. At 32k context:

| Model | Fits on GPU? | Notes |
|-------|--------------|-------|
| `qwen3:8b` | Yes — 7.6 GB, measured | **Claude Code local mode** |
| `qwen2.5-coder:7b` | Yes — ~5.6 GB, estimated | **Ollama report scripts** |
| `qwen3:14b`, `qwen2.5-coder:14b` | No — ~12 GB | Spills to CPU, very slow |
| `devstral`, `glm-4.7-flash` | No | Too large at any context |

`qwen3` handles Claude Code's tool calls better than `qwen2.5-coder`, which is better at writing code than at agent work.

### 5.4 Health checks

```bash
docker exec ollama env | grep OLLAMA_
docker exec ollama ollama list
docker exec ollama ollama ps                 # run while Claude Code is working
docker logs --since 1h ollama 2>&1 | grep -i 'truncating input prompt'
```

Good: `ollama ps` shows `CONTEXT 32768` and `100% GPU`; the truncation grep prints nothing.

- **`ollama ps` empty** while Claude Code says it is working: the model is still loading (~30 s after a container restart), or the model name is wrong. Check `ollama list` and `docker logs --since 5m ollama`.
- **CPU/GPU split** in `ollama ps`: the model spilled. Use a smaller model or set `OLLAMA_CONTEXT_LENGTH=24576`.
- **First reply takes ~1 minute**; later turns are faster because Ollama reuses the cached part of the prompt.

---

## 6. Ollama Report Scripts

Three User Scripts also use the Ollama container. They do **not** use the launcher, `bash_profile` or `CLAUDE.md`; the only shared piece is the container's context setting.

| User Script | Conf | Model |
|-------------|------|-------|
| `Daily arr Media Stack Review` | `/boot/config/ollama-arr-review.conf` | `qwen2.5-coder:7b` |
| `Daily system summary` | `/boot/config/ollama-sysreview.conf` | `qwen2.5-coder:7b` |
| `Script log summary` | `/boot/config/ollama-review.conf` | `qwen2.5-coder:7b` |

None sets `num_ctx`, so all three now get 32k context. Before 20 Oct they were truncating any input over ~4k tokens, so their reports may now be longer or more complete. They were moved from `qwen2.5-coder:14b` to `7b` because 14b no longer fits at 32k.

If a report script and a local Claude Code session run within ~5 minutes of each other, both models may be loaded at once alongside Plex. Avoid local sessions around the report times.

Detail: guide Section 6.8.

---

## 7. Common Changes

### 7.1 Change the local model

```bash
docker exec ollama ollama pull <model>
sed -i 's/^export CLAUDE_LOCAL_MODEL=.*/export CLAUDE_LOCAL_MODEL="<model>"/' /boot/config/bash_profile
cp /boot/config/bash_profile /root/.bash_profile && source /root/.bash_profile
claude-caladan        # banner should show the new model
```

Use the exact name from `ollama list`, tag included.

### 7.2 Change the cloud model

The cloud model is set inside the launcher. Edit the master, then copy it:

```bash
cp /boot/config/claude-caladan.sh /boot/config/claude-caladan.sh.bak-$(date +%Y%m%d)
nano /boot/config/claude-caladan.sh          # the ANTHROPIC_MODEL line under cloud)
cp /boot/config/claude-caladan.sh /usr/local/bin/claude-caladan && chmod +x /usr/local/bin/claude-caladan
md5sum /boot/config/claude-caladan.sh /usr/local/bin/claude-caladan
```

Editing only `/usr/local/bin/claude-caladan` is lost at the next reboot.

### 7.3 Rotate the API key

1. Create a new key at console.anthropic.com → API Keys; revoke the old one.
2. Replace it:
   ```bash
   echo 'ANTHROPIC_API_KEY=sk-ant-NEWKEY' > /mnt/cache/appdata/claude-config/cloud.env
   chmod 600 /mnt/cache/appdata/claude-config/cloud.env
   ```
3. `claude-caladan cloud` and ask a one-line question.

Rotate whenever the key has been printed anywhere — a terminal you are sharing, a chat, a `bash -x` trace. Check without printing it:

```bash
. /mnt/cache/appdata/claude-config/cloud.env && echo "${ANTHROPIC_API_KEY:0:12}…"
```

### 7.4 Edit the house rules

```bash
nano /mnt/cache/appdata/claude-work/CLAUDE.md
```

It lives on the cache pool, so there is no copy step. Start a new session to pick it up, and test with: *"What are the rules for working on this box?"*

### 7.5 Update Claude Code

```bash
claude --version
```

v2.1.100 as of 20 Oct 2026, binary dated Apr 2026. How it was originally installed is not recorded, so the update method is unconfirmed. Whatever method is used, the binary must end up at `/mnt/user/appdata/claude-bin/claude` — anything installed under `/root` disappears at reboot.

---

## 8. Troubleshooting

| Symptom | Likely cause | Check / fix |
|---------|--------------|-------------|
| `claude-caladan: command not found` | Boot copy missing | `grep claude-caladan /boot/config/go`; copy manually per [7.2](#72-change-the-cloud-model) |
| Banner shows wrong model in local mode | `CLAUDE_LOCAL_MODEL` unset in this shell | `echo "$CLAUDE_LOCAL_MODEL"`; `source /root/.bash_profile` |
| `Ollama not answering on localhost:11434` | Container stopped | `docker ps \| grep ollama`; start it |
| Local reply unrelated to the question | Prompt truncated | `docker logs --since 1h ollama \| grep -i truncat`; check `OLLAMA_CONTEXT_LENGTH` |
| Local session "Puttering…" for minutes | Model loading, or not pulled | `ollama ps`, `ollama list`, `docker logs --since 5m ollama` |
| Local answer wrong or incomplete | Small-model limits | Check with Ctrl+O; rerun in cloud |
| Cloud asks you to log in | Config dir not used, or `cloud.env` missing | Banner `cwd` correct? `ls -la /mnt/cache/appdata/claude-config` |
| Cloud auth error | Key revoked or mistyped | Rotate per [7.3](#73-rotate-the-api-key) |
| Rules not followed | `CLAUDE.md` not loaded | Session must start in `claude-work` — check the banner |
| Plex transcodes stutter during a local session | VRAM contention | `nvidia-smi`; end the session; consider `OLLAMA_GPU_OVERHEAD` |

### 8.1 After every reboot

```bash
which claude-caladan && echo "$CLAUDE_LOCAL_MODEL"
claude-caladan cloud
```

Expected: `/usr/local/bin/claude-caladan`, then `qwen3:8b`, then the cloud banner with no login prompt. **Not yet verified across a real reboot** — do this the first time Caladan restarts.

---

## 9. Rebuild From Scratch

1. **Binary:** place Claude Code at `/mnt/user/appdata/claude-bin/claude`.
2. **Folders:**
   ```bash
   mkdir -p /mnt/cache/appdata/claude-config /mnt/cache/appdata/claude-work
   chmod 700 /mnt/cache/appdata/claude-config
   ```
3. **Launcher:** write [Appendix A](#appendix-a-launcher-source) to `/boot/config/claude-caladan.sh`, confirm its md5, copy to `/usr/local/bin/claude-caladan`, `chmod +x`.
4. **House rules:** write [Appendix B](#appendix-b-claudemd-source) to `/mnt/cache/appdata/claude-work/CLAUDE.md`.
5. **Key:** create `cloud.env` per [7.3](#73-rotate-the-api-key).
6. **Profile:** add `export CLAUDE_LOCAL_MODEL="qwen3:8b"` to `/boot/config/bash_profile`; no `ANTHROPIC_*` lines.
7. **`go` file:** add the lines in [3.2](#32-what-the-go-file-does).
8. **Ollama:** container variables per [5.2](#52-ollama-container-settings); `ollama pull qwen3:8b` and `ollama pull qwen2.5-coder:7b`.
9. **Report scripts:** restore the three confs with `OLLAMA_MODEL="qwen2.5-coder:7b"`.
10. **Verify:** [8.1](#81-after-every-reboot), then the rules read-back in [7.4](#74-edit-the-house-rules).

---

## Appendix A: Launcher Source

`/boot/config/claude-caladan.sh` as deployed 20 Oct 2026. md5 `cb10db71f71514a66ec8cc6664e63412` (both the `/boot` copy and `/usr/local/bin/claude-caladan`). After any edit, confirm the deployed file before relying on this copy.

```bash
#!/bin/bash
# claude-caladan — launch Claude Code on Caladan for Plex/Unraid log review
# Usage: claude-caladan [local|cloud] [extra claude args...]
#   local (default): Ollama on localhost:11434 (override model with CLAUDE_LOCAL_MODEL)
#   cloud:           Anthropic. Uses ANTHROPIC_API_KEY from cloud.env if present,
#                    otherwise the claude.ai login stored in the config dir.
# Persist: keep at /boot/config/claude-caladan.sh; the go file copies it to
#          /usr/local/bin/claude-caladan on boot.

BACKEND="${1:-local}"
shift 2>/dev/null

export CLAUDE_CONFIG_DIR=/mnt/cache/appdata/claude-config
CLAUDE_BIN=/mnt/user/appdata/claude-bin/claude
WORK=/mnt/cache/appdata/claude-work
PLEX_LOGS="/mnt/cache/appdata/plex/Library/Application Support/Plex Media Server/Logs"
TAUT_LOGS=/mnt/cache/appdata/tautulli/logs

case "$BACKEND" in
  local)
    export ANTHROPIC_BASE_URL="http://localhost:11434"
    export ANTHROPIC_AUTH_TOKEN="ollama"
    export ANTHROPIC_API_KEY=""
    export ANTHROPIC_MODEL="${CLAUDE_LOCAL_MODEL:-glm-4.7-flash}"
    if ! curl -sf -o /dev/null http://localhost:11434/api/tags; then
      echo "Ollama not answering on localhost:11434 — is the container up?" >&2
      exit 1
    fi
    ;;
  cloud)
    unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY
    # cloud.env holds one line: ANTHROPIC_API_KEY=sk-ant-...  (chmod 600)
    [ -f "$CLAUDE_CONFIG_DIR/cloud.env" ] && . "$CLAUDE_CONFIG_DIR/cloud.env" && export ANTHROPIC_API_KEY
    export ANTHROPIC_MODEL="claude-sonnet-5-5"
    ;;
  *)
    echo "usage: claude-caladan [local|cloud] [claude args...]" >&2
    exit 1
    ;;
esac

cd "$WORK" || { echo "missing $WORK" >&2; exit 1; }
echo "backend=$BACKEND model=$ANTHROPIC_MODEL cwd=$WORK"
exec "$CLAUDE_BIN" --add-dir "$PLEX_LOGS" --add-dir "$TAUT_LOGS" "$@"
```

---

## Appendix B: CLAUDE.md Source

`/mnt/cache/appdata/claude-work/CLAUDE.md` as written 20 Oct 2026 (read-back confirmed in a new session). If you have edited it since, the live file wins.

```markdown
# Caladan — Claude Code working notes

You are helping Rich review logs and diagnose issues on Caladan, his Unraid media server.
You are an analyst here, not an operator: investigate, explain, recommend.

## Hard rules
- READ-ONLY by default. Do not edit, move or delete files, restart containers, change
  container settings, or call write/POST APIs unless Rich explicitly asks in this session.
  When a fix is needed, give the exact command and let Rich run it.
- Never open a live SQLite database. Copy it first, then query the copy:
    cp /mnt/cache/appdata/<app>/<db> /tmp/<db>.copy && sqlite3 /tmp/<db>.copy
- Always use /mnt/cache/appdata/... paths for appdata, never /mnt/user/appdata/...
  (the shfs FUSE layer is a known SQLite corruption vector on this box).
- Never print secrets in full. Mask API keys, Plex tokens and webhooks to 4 chars: ${KEY:0:4}…
  Secrets live in /boot/config/arr-rescans.conf (SONARR_KEY, RADARR_KEY, LIDARR_KEY,
  DISCORD_WEBHOOK) and Plex's Preferences.xml (PlexOnlineToken).
- Verify before concluding. Quote the actual log lines or command output a finding rests on.
  If a search returns nothing, say what you searched (file, pattern) so Rich can check it.
- Before calling a Plex restart a crash, check whether it lines up with a container
  update (docker inspect plex --format '{{.Created}}' / {{.State.StartedAt}}).

## Searching logs
- Use Bash `grep -n` / `grep -c`, or the Grep tool with content output. A "files matched"
  result means matches EXIST — follow up and read the lines.
- Group repeated errors before summarizing:
    grep ' ERROR - ' "$LOG" | sed 's/^.* ERROR - //; s/[0-9]\{3,\}/N/g' | sort | uniq -c | sort -rn
- Plex log lines look like: `Oct 20, 2026 13:12:21.140 [tid] ERROR - message`
  Levels to grep: ' ERROR - ', ' WARN - '. Today's lines: grep "^$(date '+%b %d, %Y')"
- Logs rotate: X.log is current, X.1.log the previous run, up to X.5.log. A new rotation
  means Plex restarted. Check all of them when looking at history.

## System
- Unraid 7.2.4, host 192.168.1.12. Root filesystem is RAM; /boot (flash) and /mnt/cache persist.
- GPU: RTX 3060 12 GB — NVENC/NVDEC H.264 + HEVC. Shared by Plex (HW transcode), Tdarr's
  internal node, and Ollama (OLLAMA_GPU_OVERHEAD reserves headroom for Plex).
- No nerdtools/iotop on Unraid 7. Use iostat -x, /proc/diskstats, docker stats.

## Key paths
- Plex logs:   /mnt/cache/appdata/plex/Library/Application Support/Plex Media Server/Logs/
    Plex Media Server.log            main log: errors, transcode decisions, NVENC events
    Plex Transcoder Statistics.log   per-session XML: buffering, bitrates, decisions
    Plex Crash Uploader.log          crash reports
- Plex config: .../Plex Media Server/Preferences.xml
- Plex DB:     .../Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db
- Tautulli:    /mnt/cache/appdata/tautulli/logs/ (tautulli.log, plex_websocket.log, tautulli_api.log)
- *arr DBs:    /mnt/cache/appdata/{sonarr,radarr,radarr-4k,lidarr}/
- Custom scripts: /boot/config/plugins/user.scripts/scripts/  (shared conf: /boot/config/arr-rescans.conf)

## Containers and APIs (localhost)
- plex :32400 · tautulli · sonarr :8989 /api/v3 · radarr :7878 /api/v3 · radarr-4k
- lidarr :8686 /api/v1 (v1, not v3) · prowlarr · bazarr · unpackerr · tdarr · ollama :11434
- binhex-syncthing :8384 (key in /mnt/cache/appdata/binhex-syncthing/syncthing/config/config.xml)
- Useful read-only checks: docker logs --since 1h <name>, docker inspect <name>,
  docker exec plex nvidia-smi, nvidia-smi

## Pipeline context
Seedbox qBittorrent → Syncthing → /mnt/user/media/download/sync/ → Unpackerr (RARs)
→ arr-rescans triggers imports → Sonarr/Radarr/Lidarr → library → Plex/Jellyfin.
Plex's own file watcher is OFF; Sonarr/Radarr notify Plex on import. Tdarr does health
checks and audio/subtitle normalization. Custom monitor scripts alert to Discord.

## Report format
## Summary — one paragraph: what you found and how serious it is.
## <Issue> — Finding (with quoted lines/output) · Impact · Recommendation (exact command)
## Priority Action List — numbered, most important first.
Keep it tight. If everything is healthy, say so in a sentence and stop.
```

> **Known inaccuracy in this file:** the System section says `OLLAMA_GPU_OVERHEAD` reserves
> headroom for Plex. The variable is not set on the container (20 Oct 2026). Fix the line, or set
> the variable, when the open item is resolved.

---

## Change Log

### 20 October 2026 (rev 1)

- First version. Covers the `claude-caladan` launcher, persistent config on the cache pool, `CLAUDE.md`, cloud-by-default decision, Ollama 32k context settings, and the three Ollama report scripts' move to `qwen2.5-coder:7b`.
- **Open:** cold-boot verification ([8.1](#81-after-every-reboot)); confirm the report-script model switch with a test run; decide on `OLLAMA_GPU_OVERHEAD`; record how Claude Code is installed and updated.
