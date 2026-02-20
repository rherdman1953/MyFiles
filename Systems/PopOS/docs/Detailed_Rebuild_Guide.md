# Pop!_OS Hardened Sysadmin Rebuild Guide
Version: Baseline v1.0

Purpose: Fully reproducible workstation rebuild using infrastructure-as-code principles.

---

# 0. Architecture Philosophy

This workstation is built with:

- Zero WAN inbound exposure
- SSH key-only authentication
- Tailscale secure mesh networking
- NTFS shared drives for Windows interoperability
- All documentation version-controlled in GitHub

---

# 1. Install Pop!_OS

1. Boot latest Pop!_OS ISO
2. Select Clean Install
3. Filesystem: ext4 root
4. Create user: rich
5. Reboot

---

# 2. System Update & Firewall

sudo apt update
sudo apt upgrade -y
sudo apt install curl git ufw -y

Enable firewall:

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

Verify:

sudo ufw status

Expected: Status: active

---

# 3. SSH Key Setup

Generate key:

ssh-keygen -t ed25519 -C "rich@pop-os"

Add public key to GitHub:

cat ~/.ssh/id_ed25519.pub

Paste into GitHub → Settings → SSH Keys

Test:

ssh -T git@github.com

Expected: Successfully authenticated

---

# 4. Clone Infrastructure Repo

cd ~
git clone git@github.com:rherdman1953/MyFiles.git
cd MyFiles

Configure git identity:

git config --global user.name "Rich Herdman"
git config --global user.email "your-email@example.com"

---

# 5. NTFS Shared Drives

Create mountpoints:

sudo mkdir -p /mnt/Sm980Pro1tb
sudo mkdir -p /mnt/Crucial4tb

Edit /etc/fstab:

UUID=624AEFCC4AEF9B55 /mnt/Sm980Pro1tb ntfs3 rw,uid=1000,gid=1000,windows_names,noatime,nofail,umask=0002 0 0
UUID=84B036F5B036ECF4 /mnt/Crucial4tb ntfs3 rw,uid=1000,gid=1000,windows_names,noatime,nofail,umask=0002 0 0

Apply:

sudo systemctl daemon-reload
sudo mount -a

Validate:

mount | grep ntfs

Disable Windows Fast Startup inside Windows.

---

# 6. CIFS Network Shares

Create credentials file:

sudo nano /etc/samba/credentials-caladan

Add:

username=rich
password=YOUR_PASSWORD

Secure file:

sudo chmod 600 /etc/samba/credentials-caladan

Configure automount entries in fstab using _netdev.

---

# 7. Dropbox (deb version)

Install:

sudo apt install ./dropbox.deb

If using NTFS Dropbox folder:

sudo mount --bind /mnt/Sm980Pro1tb/Users/rherd/Dropbox /home/rich/Dropbox

Enable user service:

systemctl --user enable dropbox
systemctl --user start dropbox

Verify:

dropbox status

---

# 8. Tailscale (Secure Mesh)

Install:

curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

Verify:

tailscale status
tailscale netcheck
tailscale dns status

Ensure:

- MagicDNS enabled
- No exit node
- No subnet routes
- No Tailscale SSH
- No router port forwarding

Access devices:

ssh root@caladan.tail1def1.ts.net

Note: IPv6 disabled may produce benign DNS warning.

---

# 9. VS Code

Install VS Code.
Install Remote SSH extension.
Test connection to caladan.local.

---

# 10. RealVNC

Install RealVNC Connect deb.

Enable service:

sudo systemctl enable rvncserver-x11-serviced.service
sudo systemctl start rvncserver-x11-serviced.service

Verify:

systemctl status rvncserver-x11-serviced.service

---

# 11. Audio Ripping Stack

sudo apt install abcde flac cdparanoia

Install MusicBrainz Picard.

Edit ~/.abcde.conf:

OUTPUTTYPE=flac
FLACOPTS='-8'
OUTPUTDIR="$HOME/out/rip"
PADTRACKS=y
EJECTCD=y

Test:

abcde -d /dev/sr0 -N -V

---

# 12. Minecraft Fabric Stack

Install correct Fabric loader version.
Install:

- Sodium
- Lithium
- FerriteCore
- ModMenu

Verify fabric-loader appears in F3 overlay.

---


# 13.  Install & configure FSearch (Everything-like)

### Install (preferred)
1) Install via apt if available:
   sudo add-apt-repository ppa:christian-boxdoerfer/fsearch-stable -y
   sudo apt update
   sudo apt install fsearch -y
   # verify
   fsearch --version

### Configure include/exclude paths
Open FSearch → Preferences → Database:

Include (and check “One Filesystem” for each):
- `/mnt/Sm980Pro1tb`
- `/mnt/Crucial4tb`
- `/home/rich`

Exclude:
- `/proc`
- `/sys`
- `/dev`
- `/run`
- `/tmp`
- `/home/rich/W`
- `/home/rich/X`
- `/home/rich/Y`
- `/home/rich/Z`
- `/mnt/Crucial4tb/foo/bf` (optional)

Set:
- Update database on start: ON
- Periodic update: 24h (or OFF)

### Verify
- Initial indexing completes without errors
- Searches return results instantly

# 14. Final Validation

tailscale status
ssh caladan.local
mount | grep ntfs
sudo ufw status
dropbox status

Confirm:

- No public port forwards
- SSH via tailnet works
- NTFS mounts persistent
- Repo cloned and updated

---

# 15. Tag Baseline

git tag -a popos-baseline-v1 -m "PopOS hardened baseline"
git push origin popos-baseline-v1

---

End of Document
