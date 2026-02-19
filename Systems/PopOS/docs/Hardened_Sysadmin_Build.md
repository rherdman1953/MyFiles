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

## Core Applications
- VS Code
- RealVNC
- VLC
- ABCDE + Picard
- Dropbox (bind mount)
- Fabric Minecraft stack

All configuration documented in GitHub repo.
