#!/usr/bin/env bash
# ==============================================================================
# backup-caladan-user-scripts.sh
# Pulls all Unraid user scripts from Caladan to the local git repo.
#
# Source (Caladan): /boot/config/plugins/user.scripts/scripts/
# Destination:      /home/rich/MyFiles/Systems/Caladan/user-scripts/
#
# Usage: ./backup-caladan-user-scripts.sh [ssh-host]
#   ssh-host defaults to "caladan" — adjust to IP/hostname/Tailscale name as needed
# ==============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
CALADAN_HOST="${1:-caladan}"                          # Override with IP/hostname if needed
CALADAN_USER="root"                                   # Unraid SSH user is root
REMOTE_SCRIPTS_DIR="/boot/config/plugins/user.scripts/scripts"
LOCAL_DEST="/home/rich/MyFiles/Systems/Caladan/user-scripts"
GIT_REPO_ROOT="/home/rich/MyFiles/Systems/Caladan"
# ──────────────────────────────────────────────────────────────────────────────

echo "==> Backing up Caladan user scripts"
echo "    Remote : ${CALADAN_USER}@${CALADAN_HOST}:${REMOTE_SCRIPTS_DIR}"
echo "    Local  : ${LOCAL_DEST}"
echo ""

# ── Verify SSH connectivity ───────────────────────────────────────────────────
echo "[1/4] Checking SSH connection to ${CALADAN_HOST}..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "${CALADAN_USER}@${CALADAN_HOST}" true 2>/dev/null; then
    echo "ERROR: Cannot reach ${CALADAN_HOST} via SSH."
    echo "       Make sure Caladan is up and Tailscale is connected (or use the local IP)."
    exit 1
fi
echo "      OK"

# ── Create destination directory ──────────────────────────────────────────────
echo "[2/4] Preparing local destination..."
mkdir -p "${LOCAL_DEST}"

# ── rsync scripts from Caladan ────────────────────────────────────────────────
# Each user script lives in its own folder under REMOTE_SCRIPTS_DIR:
#   scripts/
#     MyScriptName/
#       script        ← the actual bash script
#       name          ← friendly display name (sometimes present)
#       description   ← optional description
#       schedule      ← optional cron schedule
#       icon          ← optional icon
#
# We sync the whole tree, preserving the folder-per-script structure.
echo "[3/4] Syncing scripts from Caladan..."
rsync -avz --delete \
    --exclude='*.lock' \
    "${CALADAN_USER}@${CALADAN_HOST}:${REMOTE_SCRIPTS_DIR}/" \
    "${LOCAL_DEST}/"

# Post-process: make every 'script' file executable locally (nice for review)
find "${LOCAL_DEST}" -name "script" -exec chmod +x {} \;

echo ""
echo "      Sync complete. Contents:"
# Print a clean summary: one line per script folder
while IFS= read -r -d '' dir; do
    script_dir=$(basename "${dir}")
    # Try to read the friendly name if present
    name_file="${dir}/name"
    if [[ -f "${name_file}" ]]; then
        friendly=$(cat "${name_file}")
        echo "        • ${script_dir}  (\"${friendly}\")"
    else
        echo "        • ${script_dir}"
    fi
done < <(find "${LOCAL_DEST}" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

# ── Git commit ────────────────────────────────────────────────────────────────
echo ""
echo "[4/4] Committing to git..."
cd "${GIT_REPO_ROOT}"

# Make sure this is actually a git repo
if ! git rev-parse --git-dir &>/dev/null; then
    echo "ERROR: ${GIT_REPO_ROOT} is not a git repository."
    echo "       Run 'git init' there first, or adjust GIT_REPO_ROOT in this script."
    exit 1
fi

git add "${LOCAL_DEST}"

if git diff --cached --quiet; then
    echo "      No changes detected — nothing to commit."
else
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
    git commit -m "caladan: backup user scripts (${TIMESTAMP})"
    echo "      Committed successfully."
    echo ""
    echo "      Run 'git push' from ${GIT_REPO_ROOT} when ready to push upstream."
fi

echo ""
echo "==> Done."
