# Pop!\_OS Full Rebuild Guide

*Last Updated: 2026-02-19*

## Phase 1 -- Fresh Install

1.  Install Pop!\_OS (UEFI, encrypted)
2.  Update system: sudo apt update && sudo apt full-upgrade -y

## Phase 2 -- Core Tools

Install: - git - curl - neovim - tmux - build-essential - ntfs tools -
openssh

## Phase 3 -- Mount Data Drives

1.  Identify UUID: lsblk -f
2.  Add to /etc/fstab: UUID=XXXX /mnt/DriveName ntfs3
    rw,uid=1000,gid=1000,windows_names,noatime,nofail,umask=0002 0 0
3.  Test: sudo mount -a

## Phase 4 -- Dropbox Setup

1.  Install deb version
2.  Confirm data location on NTFS
3.  Validate permissions

## Phase 5 -- VPN Setup

1.  Install Mullvad
2.  Connect WireGuard
3.  Validate routing: curl -4 ifconfig.me

## Phase 6 -- SSH Setup

1.  Generate key: ssh-keygen -t ed25519
2.  Copy to servers: ssh-copy-id user@host
3.  Test login

## Phase 7 -- VS Code Remote

1.  Install VS Code
2.  Install Remote-SSH extension
3.  Connect to caladan.local

## Phase 8 -- Audio Stack

1.  Install abcde
2.  Configure \~/.abcde.conf
3.  Rip to \~/out/rip
4.  Tag in Picard

## Phase 9 -- Hardening

1.  Configure UFW
2.  Review sysctl settings
3.  Disable unnecessary services

## Phase 10 -- Snapshot Backup

Commit configs to GitHub: - \~/.abcde.conf - \~/.ssh/config - /etc/fstab
(sanitized) - Any custom scripts

Tag release: git tag build-2026-02-19
