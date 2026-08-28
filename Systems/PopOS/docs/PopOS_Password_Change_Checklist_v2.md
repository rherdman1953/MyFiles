# Pop!_OS Password Change Checklist

**System:** Pop!_OS workstation (`pop-os`)  
**User:** `rich`  
**Purpose:** Change the local Pop!_OS password and, when applicable, the Caladan SMB/CIFS password, then verify privileged access, network shares, SSH, Tailscale, and GNOME keyring behavior.

---

## 1. Change the local Pop!_OS password

On this system, running `passwd` directly produced:

```text
passwd: Authentication token manipulation error
passwd: password unchanged
```

Use the working method instead:

```bash
sudo -k
sudo passwd rich
```

Enter the new password twice.

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

## 2. Update the GNOME Login keyring password

Because the local password was changed with:

```bash
sudo passwd rich
```

the GNOME **Login** keyring password is not automatically changed with it.

After the next login/reboot, the desktop may display:

```text
Authentication required
The login keyring did not get unlocked when you logged into your computer.
```

Initially, the keyring will still unlock with the **old Pop!_OS password**.

### Change the keyring password to match the new Pop!_OS password

Open **Passwords and Keys** (`seahorse`).

If needed:

```bash
sudo apt install seahorse
```

Launch it with:

```bash
seahorse
```

Then:

- Find the keyring named **Login** under **Passwords**.
- Right-click **Login**.
- Select **Change Password**.
- Enter the **old Pop!_OS password** as the current keyring password.
- Enter the **new Pop!_OS password** as the new keyring password.
- Save the change.

### Expected behavior with automatic login

This workstation intentionally uses automatic login so the desktop session is available for RustDesk after reboot.

Because automatic login does not supply the account password to GNOME at login time, the encrypted Login keyring cannot unlock automatically.

Therefore, after a reboot:

- The desktop may prompt to unlock the Login keyring.
- Enter the **new Pop!_OS password**.
- This prompt is expected and is being intentionally retained.
- Do **not** remove the keyring password unless unattended keyring unlock becomes a requirement.

---

## 3. Update the Caladan SMB/CIFS password

Only perform this section if the password used for the `rich` SMB account on Caladan was also changed.

Edit:

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

Run these as two separate commands:

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

## 4. Reload and test CIFS network shares

The Caladan shares are mounted at:

- `/home/rich/W`
- `/home/rich/X`
- `/home/rich/Y`
- `/home/rich/Z`

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Unmount any currently mounted copies so the updated credentials will be used:

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

## 5. Verify SSH access to Caladan

The hardened workstation uses SSH key-based access.

Use the configured SSH host alias:

```bash
ssh caladan
```

Expected behavior:

- Connects without requesting the Caladan account password.
- Logs in as `root`.
- Uses the existing SSH key configuration.

Exit:

```bash
exit
```

### Hostname note

On this workstation:

```bash
ssh caladan
```

uses the configured SSH alias and key.

However:

```bash
ssh caladan.local
```

defaults to the local username (`rich`) and may prompt for a password.

Use **`ssh caladan`** as the normal verification command unless the SSH configuration is intentionally changed.

Optional configuration check:

```bash
ssh -G caladan | grep -E '^(hostname|user|identityfile) '
```

---

## 6. Verify GitHub SSH authentication

Changing the Pop!_OS account password does **not** require regenerating the existing SSH key.

Optional verification:

```bash
ssh -T git@github.com
```

A successful GitHub authentication message confirms that the existing key still works.

---

## 7. Verify Tailscale

The local Pop!_OS password is independent of Tailscale authentication.

Check:

```bash
tailscale status
```

Confirm the workstation is connected to the tailnet and expected devices are visible.

---

## 8. Auto-login / RustDesk behavior

The workstation uses automatic login for `rich` so RustDesk can reach the desktop session after reboot.

Changing the Pop!_OS password does **not** disable automatic login.

Expected behavior after reboot:

- Pop!_OS automatically logs into the `rich` desktop session.
- RustDesk can start with the user session.
- The encrypted GNOME Login keyring may prompt for the new Pop!_OS password.
- This keyring prompt is expected and intentionally retained.
- `sudo` and other privilege-elevation prompts use the new Pop!_OS password.

No RustDesk configuration change is required solely because the Pop!_OS password changed.

---

## 9. Final verification

Run:

```bash
sudo -k
sudo whoami
ssh caladan
tailscale status
findmnt -t cifs
```

Then reboot once and confirm the expected login/keyring behavior.

Checklist:

- [ ] New Pop!_OS password works with `sudo`.
- [ ] GNOME Login keyring password has been changed to the new Pop!_OS password.
- [ ] After reboot, the Login keyring accepts the new password.
- [ ] The keyring remains encrypted and the post-login unlock prompt is intentionally retained.
- [ ] Caladan SSH key login works using `ssh caladan`.
- [ ] Caladan SMB/CIFS shares mount and are accessible.
- [ ] `/etc/samba/credentials-caladan` has mode `600`.
- [ ] Tailscale is connected.
- [ ] GitHub SSH still works, if tested.
- [ ] Automatic login and RustDesk behavior remain unchanged.

---

## Notes

- The local Pop!_OS password and the Caladan SMB/CIFS password are separate credentials unless they are intentionally kept the same.
- The GNOME Login keyring is also a separate encrypted credential store.
- Using `sudo passwd rich` changes the local account password but does not automatically update the Login keyring password.
- Automatic login prevents GNOME from receiving the account password during login, so an encrypted Login keyring may require a manual unlock after each reboot.
- Do not regenerate SSH keys simply because the local password changes.
- Remote SSH access remains key-based.
