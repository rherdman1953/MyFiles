# Pop!_OS Hardened Sysadmin Build

## Design Goals
- Reproducible workstation
- Minimal attack surface
- Remote-first management
- High-performance local storage

---

## Filesystem Strategy
- Root: ext4
- Data: NTFS (ntfs3 driver)
- Mount under /mnt
- Use noatime to reduce write overhead

---

## Networking
- Tailscale for remote access
- No direct WAN exposure
- IPv6 disabled (intentional)

---

## Remote Access: RustDesk

### Installation
sudo apt install ./rustdesk-*.deb -y

### Enable
sudo systemctl enable rustdesk --now

### Service Behavior
- Runs as system service
- Starts at boot
- Spawns user session process

---

## RustDesk Limitation (Wayland)

- GDM login screen runs on Wayland
- RustDesk cannot control login screen

### Recommended Solution

Enable auto-login:

/etc/gdm3/custom.conf

AutomaticLoginEnable=true
AutomaticLogin=rich

### Result
- System boots directly into session
- RustDesk works immediately

---

## Fast Search (FSearch)

### Purpose
Provides instant filename search (Windows Everything equivalent)

### Include
- /mnt/Sm980Pro1tb
- /mnt/Crucial4tb
- /home/rich

### Exclude
- /proc, /sys, /dev, /run, /tmp
- network mounts (W, X, Y, Z)

### Performance Tuning
- Enable "One filesystem"
- 24h update interval
- Avoid indexing transient directories

---

## Tooling
- VS Code (Remote SSH)
- RustDesk
- FSearch
- Tailscale
- VLC
- ABCDE + Picard

---

## Security Posture
- SSH key-based auth
- No exposed services to WAN
- Firewall optional (UFW baseline)
 
---

## Power protection
 - For UPS monitoring and shutdown configuration, see [UPS_Configuration.md](UPS_Configuration.md).
