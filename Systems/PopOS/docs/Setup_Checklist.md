# Pop!_OS Hardened Sysadmin Setup Checklist

## Base Install
- Install Pop!_OS (latest LTS)
- sudo apt update && sudo apt upgrade -y
- Enable UFW (default deny incoming)

## SSH & GitHub
- Generate ed25519 SSH key
- Add key to GitHub
- Clone repo:
  git clone git@github.com:rherdman1953/MyFiles.git

## Network Shares (CIFS)
- Credentials in /etc/samba/credentials-caladan
- systemd automount + _netdev

## NTFS Dual Boot
Use ntfs3 with:
rw,uid=1000,gid=1000,windows_names,noatime,nofail,umask=0002
Disable Windows Fast Startup

## Dropbox
- Use deb version
- Bind mount NTFS Dropbox location
- Enable systemd user service

## VS Code
- Install
- Add Remote SSH extension
- Connect to caladan.local

## RealVNC
- Install RealVNC Connect
- Enable rvncserver-x11-serviced.service

## Tailscale (Hardened)
- tailscale up
- MagicDNS enabled
- No exit node
- No subnet routes
- No Tailscale SSH
- No router port forwarding
Verify:
tailscale status
tailscale netcheck

## Fast local filename search (Everything-like): FSearch

Goal: Instant filename search across local disks (including NTFS), while excluding network mounts.

### Install
> Prefer distro package if available; otherwise use upstream PPA/build instructions.

Verify:
- `fsearch --version` (or launch “FSearch” from Applications)

### Configure (Preferences → Database)
**Include:**
- `/mnt/Sm980Pro1tb`  (check “One Filesystem”)
- `/mnt/Crucial4tb`   (check “One Filesystem”)
- `/home/rich`        (check “One Filesystem”)

**Exclude:**
- `/proc`
- `/sys`
- `/dev`
- `/run`
- `/tmp`
- `/home/rich/W`
- `/home/rich/X`
- `/home/rich/Y`
- `/home/rich/Z`
- `/mnt/Crucial4tb/foo/bf`  (heavy working tree; optional)

**Database update cadence:**
- Enable “Update database on start”
- Set periodic update to **24 hours** (or disable periodic updates and refresh manually)
  - Avoid frequent reindex on large NTFS volumes (4TB) unless needed

**Search preferences:**
- Recommended for sysadmin use: disable “Exclude hidden files and folders” so dotfiles are searchable
