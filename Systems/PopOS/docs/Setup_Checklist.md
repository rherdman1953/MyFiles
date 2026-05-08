# Pop!_OS Sysadmin Setup Checklist

## Base System
- Install Pop!_OS (latest LTS)
- sudo apt update && sudo apt upgrade -y

## SSH + GitHub
- Generate SSH key (ed25519)
- Add key to GitHub
- Clone repo:
  git clone git@github.com:rherdman1953/MyFiles.git

## VS Code
- Install VS Code
- Install extensions:
  - Remote - SSH
  - GitLens
  - Markdown All in One

## Network Shares (CIFS)
- Credentials stored in:
  /etc/samba/credentials-caladan
- Use:
  _netdev,x-systemd.automount
- Mount under:
  /home/rich/W, X, Y, Z

## NTFS Drives
Mount using ntfs3:

Options:
rw,uid=1000,gid=1000,windows_names,noatime,nofail,umask=0002

Mount points:
- /mnt/Sm980Pro1tb
- /mnt/Crucial4tb

## Tailscale
- Install and login:
  tailscale up

Verify:
tailscale status
tailscale netcheck

## Remote Access (RustDesk)

### Install (.deb)
cd ~/Downloads
sudo apt install ./rustdesk-*.deb -y

### Enable Service
sudo systemctl enable rustdesk --now

### Verify
sudo systemctl status rustdesk

## Fast File Search (FSearch)

### Install
sudo add-apt-repository ppa:christian-boxdoerfer/fsearch-stable -y
sudo apt update
sudo apt install fsearch -y

### Configure

Include:
- /mnt/Sm980Pro1tb
- /mnt/Crucial4tb
- /home/rich

Exclude:
- /proc
- /sys
- /dev
- /run
- /tmp
- /home/rich/W
- /home/rich/X
- /home/rich/Y
- /home/rich/Z

Settings:
- Update on start ✔
- Update interval: 24 hours
- Include hidden files ✔


## UPS
### For UPS monitoring and shutdown configuration, see [UPS_Configuration.md](UPS_Configuration.md).