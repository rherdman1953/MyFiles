#!/usr/bin/env bash

set -Eeuo pipefail

# Incrementally back up the 2026 camera-image folder from the Samsung T7
# USB drive to the mounted Unraid share. Files removed from the USB drive
# are intentionally NOT deleted from Unraid.

readonly SOURCE_MOUNT="/media/rich/T7 1tb IMG"
readonly SOURCE_DIR="${SOURCE_MOUNT}/images/2026/"
readonly DEST_MOUNT="/home/rich/Y"
readonly DEST_DIR="${DEST_MOUNT}/images/2026/"

usage() {
    cat <<'EOF'
Usage: backup-camera-images.sh [--dry-run]

Options:
  -n, --dry-run  Show what would be copied without changing anything
  -h, --help     Show this help

The script copies only new or changed files. It does not delete files from
the Unraid backup when they are removed from the USB source.
EOF
}

dry_run=false

case "${1:-}" in
    "") ;;
    -n|--dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    *)
        printf 'Unknown option: %s\n\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

if (( $# > 1 )); then
    printf 'Only one option may be supplied.\n\n' >&2
    usage >&2
    exit 2
fi

if ! command -v rsync >/dev/null 2>&1; then
    printf 'ERROR: rsync is not installed.\n' >&2
    printf 'Install it with: sudo apt install rsync\n' >&2
    exit 1
fi

# Checking the mount points prevents the script from silently reading from or
# writing to ordinary local directories when either drive/share is disconnected.
if ! mountpoint -q -- "$SOURCE_MOUNT"; then
    printf 'ERROR: The camera USB drive is not mounted at:\n  %s\n' "$SOURCE_MOUNT" >&2
    exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    printf 'ERROR: The source folder does not exist:\n  %s\n' "$SOURCE_DIR" >&2
    exit 1
fi

if ! mountpoint -q -- "$DEST_MOUNT"; then
    printf 'ERROR: The Unraid share is not mounted at:\n  %s\n' "$DEST_MOUNT" >&2
    exit 1
fi

if [[ ! -d "$DEST_DIR" ]]; then
    printf 'ERROR: The destination folder does not exist:\n  %s\n' "$DEST_DIR" >&2
    exit 1
fi

if [[ ! -w "$DEST_DIR" ]]; then
    printf 'ERROR: The destination folder is not writable:\n  %s\n' "$DEST_DIR" >&2
    exit 1
fi

rsync_options=(
    --recursive
    --times
    --verbose
    --human-readable
    --info=progress2
    --partial
)

if [[ "$dry_run" == true ]]; then
    rsync_options+=(--dry-run)
    printf 'DRY RUN: no files will be changed.\n'
fi

printf 'Source:      %s\n' "$SOURCE_DIR"
printf 'Destination: %s\n\n' "$DEST_DIR"

rsync "${rsync_options[@]}" -- "$SOURCE_DIR" "$DEST_DIR"

printf '\nBackup completed successfully.\n'
