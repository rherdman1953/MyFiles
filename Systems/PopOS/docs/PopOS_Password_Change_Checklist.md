# Pop!_OS Password Change Checklist

**System:** Pop!_OS workstation (`pop-os`)  
**User:** `rich`  
**Purpose:** Safely change the local Pop!_OS password and, when applicable, the Caladan SMB/CIFS password, then verify that privileged access, network shares, SSH, and Tailscale still work.

---

## 1. Change the local Pop!_OS password

On this system, running `passwd` directly produced:

```text
passwd: Authentication token manipulation error
passwd: password unchanged
```

The working method is to reset the password with `sudo`:

```bash
sudo -k
sudo passwd rich
```

Enter the new password twice when prompted.

Expected result:

```text
passwd: password updated successfully
```

### Verify the new local password

Clear any cached `sudo` authentication and test again:

```bash
sudo -k
sudo whoami
```

Enter the **new Pop!_OS password**.

Expected result:

```text
root
```

> `whoami` by itself only confirms that the current shell is running as `rich`; it does not verify the new password.

---

## 2. Update the Caladan SMB/CIFS password

Only perform this section if the password used for the `rich` SMB account on Caladan was also changed.

Edit the stored credentials file:

```bash
sudo nano /etc/samba/credentials-caladan
```

Keep the format:

```text
username=rich
password=NEW_PASSWORD
```

Save and exit.

### Verify credential-file permissions

Run these as **two separate commands**:

```bash
sudo chmod 600 /etc/samba/credentials-caladan
sudo ls -l /etc/samba/credentials-caladan
```

Expected permissions:

```text
-rw------- 1 root root ...
```

The credentials file should be readable and writable only by `root`.

---

## 3. Reload and test CIFS network shares

The workstation documentation uses systemd automounting for the Caladan shares mounted at:

- `/home/rich/W`
- `/home/rich/X`
- `/home/rich/Y`
- `/home/rich/Z`

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Unmount any currently mounted copies so the new credentials will be used:

```bash
sudo umount /home/rich/W 2>/dev/null
sudo umount /home/rich/X 2>/dev/null
sudo umount /home/rich/Y 2>/dev/null
sudo umount /home/rich/Z 2>/dev/null
```

Trigger the automounts again:

```bash
ls /home/rich/W
ls /home/rich/X
ls /home/rich/Y
ls /home/rich/Z
```

Verify mounted CIFS shares:

```bash
findmnt -t cifs
```

Confirm that the expected Caladan shares appear and can be browsed.

---

## 4. Verify SSH access to Caladan

The hardened workstation uses SSH key-based access.

Use the configured SSH host alias:

```bash
ssh caladan
```

Expected behavior:

- Connects without asking for the Caladan account password.
- Logs in as `root`.
- Uses the existing SSH key configuration.

Exit the remote shell:

```bash
exit
```

### Important hostname note

On this workstation:

```bash
ssh caladan
```

works with the configured SSH key and logs in as `root`.

However:

```bash
ssh caladan.local
```

defaults to the local username (`rich`) and may prompt for a password.

Therefore, use **`ssh caladan`** as the normal verification command unless the SSH configuration is intentionally changed.

Optional configuration check:

```bash
ssh -G caladan | grep -E '^(hostname|user|identityfile) '
```

---

## 5. Verify GitHub SSH authentication

Changing the Pop!_OS account password does **not** require regenerating the existing SSH key.

Optional verification:

```bash
ssh -T git@github.com
```

A successful GitHub authentication message confirms that the existing key still works.

---

## 6. Verify Tailscale

The local Pop!_OS password is independent of Tailscale authentication.

Check status:

```bash
tailscale status
```

Confirm the workstation is connected to the tailnet and expected devices are visible.

---

## 7. Auto-login behavior

The hardened workstation documentation enables automatic login for `rich` so RustDesk can reach the desktop session after boot.

Changing the Pop!_OS password does **not** disable automatic login.

The new local password is still required for:

- `sudo`
- privilege-elevation prompts
- other local authentication requests

No RustDesk configuration change is required solely because the Pop!_OS password changed.

---

## 8. Final verification

Run:

```bash
sudo -k
sudo whoami
ssh caladan
tailscale status
findmnt -t cifs
```

Confirm:

- [ ] New Pop!_OS password works with `sudo`.
- [ ] Caladan SSH key login works using `ssh caladan`.
- [ ] Caladan SMB/CIFS shares mount and are accessible.
- [ ] `/etc/samba/credentials-caladan` has mode `600`.
- [ ] Tailscale is connected.
- [ ] GitHub SSH still works, if tested.
- [ ] Automatic login behavior is unchanged.

---

## Notes

- The local Pop!_OS password and the Caladan SMB/CIFS password are separate credentials unless they are intentionally kept the same.
- Do not regenerate SSH keys simply because the local Pop!_OS password changes.
- The workstation's hardened design relies on SSH key-based access and Tailscale rather than password-based remote SSH access.
