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
