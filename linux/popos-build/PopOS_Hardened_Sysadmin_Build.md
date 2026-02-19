# Pop!\_OS Hardened Sysadmin Build

*Last Updated: 2026-02-19*

## 1. Base System Install

-   Install latest Pop!\_OS LTS (UEFI mode)
-   Full disk encryption enabled
-   Separate NVMe drives documented
-   Verify Secure Boot status

## 2. System Update & Core Packages

``` bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install curl wget git htop neovim tmux build-essential                  gnome-shell-extension-appindicator                  ntfs-3g ntfs3g e2fsprogs                  openssh-client openssh-server                  ca-certificates ufw fail2ban -y
```

## 3. Filesystem Hardening

### NTFS Mount Options (Dual Boot Safe)

Use:

    rw,uid=1000,gid=1000,windows_names,noatime,nofail,umask=0002

### Security Notes

-   Avoid `exec` on data drives if not required
-   Use `nodev,nosuid` for external storage when possible

## 4. Network Hardening

### Disable IPv6 (if required)

    /etc/sysctl.d/99-disable-ipv6.conf
    net.ipv6.conf.all.disable_ipv6 = 1
    net.ipv6.conf.default.disable_ipv6 = 1

### Firewall

``` bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable
```

## 5. VPN (Mullvad WireGuard)

-   Default route via wg0
-   Verify with: `curl ifconfig.me`
-   Optional: Policy routing for specific apps

## 6. SSH Best Practices

-   ed25519 keys only
-   Disable password login on servers
-   \~/.ssh/config for hosts
-   Use SSH agent

## 7. Dropbox Best Practice

-   Mount NTFS under /mnt
-   Store Dropbox on NTFS
-   Use bind mount or symlink
-   Verify permissions (rw for user)

## 8. Audio Ripping Stack

-   abcde configured for FLAC -8
-   Output to \~/out/rip
-   MusicBrainz over HTTPS
-   Picard post-tag verification

## 9. Development Stack

-   VS Code + Remote SSH
-   Git configured with SSH keys
-   Neovim minimal config
-   tmux

## 10. Remote Management

-   RealVNC server (X11 mode)
-   SSH primary management path
-   Avoid exposing VNC to internet directly

## 11. Backup Strategy

-   External drive with rsync
-   Periodic config backup:

``` bash
rsync -a ~/.ssh ~/.abcde.conf /etc/fstab ~/Documents/sys-backup/
```

## 12. System Audit Checklist

-   `lsblk -f`
-   `mount`
-   `ip a`
-   `systemctl --failed`
-   `journalctl -p 3 -xb`
