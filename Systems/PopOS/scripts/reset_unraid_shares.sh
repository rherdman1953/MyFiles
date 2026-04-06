#!/usr/bin/env bash
set -u

# Reset and remount Unraid CIFS shares on Pop!_OS
#
# Shares:
#   W -> /home/rich/W
#   X -> /home/rich/X
#   Y -> /home/rich/Y
#   Z -> /home/rich/Z
#
# What this script does:
#   1. Lazy-unmounts the share mount points to clear stale file handles
#   2. Reloads systemd mount state
#   3. Mounts each share from /etc/fstab
#   4. Verifies each mount
#   5. Tests basic directory access with ls
#   6. Writes a timestamped log file
#
# Usage:
#   chmod +x ~/reset_unraid_shares.sh
#   ~/reset_unraid_shares.sh
#
# Optional:
#   sudo ~/reset_unraid_shares.sh
#
# Log location:
#   ~/reset_unraid_shares_YYYY-MM-DD_HH-MM-SS.log

MOUNTS=(
  "/home/rich/W"
  "/home/rich/X"
  "/home/rich/Y"
  "/home/rich/Z"
)

LOGFILE="$HOME/reset_unraid_shares_$(date +%F_%H-%M-%S).log"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOGFILE"
}

run_cmd() {
  log "RUN: $*"
  "$@" 2>&1 | tee -a "$LOGFILE"
  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    log "Command failed with exit code $rc"
  fi
  return $rc
}

log "Starting Unraid share reset"
log "Log file: $LOGFILE"

log "Step 1: lazy-unmounting mount points if needed"
for mnt in "${MOUNTS[@]}"; do
  if mountpoint -q "$mnt"; then
    log "$mnt is mounted; attempting lazy unmount"
    run_cmd sudo umount -l "$mnt" || true
  else
    log "$mnt is not currently mounted"
  fi
done

log "Step 2: reloading systemd daemon state"
run_cmd sudo systemctl daemon-reload || true

log "Step 3: mounting shares from /etc/fstab"
for mnt in "${MOUNTS[@]}"; do
  if [[ ! -d "$mnt" ]]; then
    log "Mount point missing, creating directory: $mnt"
    run_cmd mkdir -p "$mnt" || continue
  fi

  log "Mounting $mnt"
  run_cmd sudo mount "$mnt" || true
done

log "Step 4: verifying mount status"
FAILURES=0
for mnt in "${MOUNTS[@]}"; do
  if mountpoint -q "$mnt"; then
    log "OK: $mnt is mounted"
  else
    log "FAIL: $mnt is not mounted"
    FAILURES=$((FAILURES + 1))
  fi
done

log "Step 5: testing directory access"
for mnt in "${MOUNTS[@]}"; do
  if mountpoint -q "$mnt"; then
    log "Testing access to $mnt"
    if ls -la "$mnt" >/dev/null 2>>"$LOGFILE"; then
      log "OK: readable: $mnt"
    else
      log "FAIL: mounted but not readable: $mnt"
      FAILURES=$((FAILURES + 1))
    fi
  else
    log "Skipping access test for unmounted path: $mnt"
  fi
done

log "Step 6: active CIFS mounts"
mount | grep cifs | tee -a "$LOGFILE" || log "No active CIFS mounts found"

if [[ $FAILURES -eq 0 ]]; then
  log "Completed successfully with no detected failures"
  echo
  echo "All four shares appear to be mounted and readable."
else
  log "Completed with $FAILURES failure(s)"
  echo
  echo "There were $FAILURES failure(s). Review the log:"
  echo "$LOGFILE"
fi