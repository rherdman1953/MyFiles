# Pop!_OS Hardened Sysadmin Build Guide

## Security Model
- No WAN inbound ports
- SSH key-only auth
- UFW enabled
- Tailscale for remote access

## Filesystem Layout
Root: ext4
Shared drives: NTFS (ntfs3)
Mounted under /mnt

## Networking
- IPv6 disabled intentionally
- fq_codel enabled
- Mullvad optional

## Tailscale Mesh
MagicDNS enabled
No exit node
No subnet routes
Access devices via:
ssh root@caladan.tail1def1.ts.net

DNS health warning expected due to IPv6 disabled.

## Fast filename search (FSearch) with NTFS + network-mount exclusions

### Why
- Provides Windows “Everything”-like filename search speed via an indexed database.
- Avoids performance issues by excluding transient pseudo-filesystems and network mounts.

### FSearch configuration baseline
Include:
- `/mnt/Sm980Pro1tb` (One Filesystem enabled)
- `/mnt/Crucial4tb`  (One Filesystem enabled)
- `/home/rich`       (One Filesystem enabled)

Exclude:
- `/proc`, `/sys`, `/dev`, `/run`, `/tmp`
- Network mounts: `/home/rich/W`, `/home/rich/X`, `/home/rich/Y`, `/home/rich/Z`
- Optional heavy paths (e.g. download staging trees)

Update schedule:
- Update on start
- Daily update or manual update (avoid frequent updates on large NTFS volumes)

### NTFS mount performance notes
- Use `noatime` on NTFS mounts to reduce metadata updates.
- Prefer stable UUID-based mounts in `/etc/fstab`.
- Ensure mounts are `rw` if the volume must be writable (check via `mount | grep ntfs`).

## Core Applications
- VS Code
- RealVNC
- VLC
- ABCDE + Picard
- Dropbox (bind mount)
- Fabric Minecraft stack

All configuration documented in GitHub repo.
