# Linux Desktop UPS Configuration

Version: Baseline v1.0  
System: Pop!_OS / Linux desktop  
UPS software: Network UPS Tools (NUT)  
UPS model: APC Back-UPS NS 900M  

---

## 1. Purpose

This document describes the UPS monitoring and safe shutdown configuration for the Linux desktop.

The desktop uses Network UPS Tools (NUT) to monitor a USB-connected APC UPS and initiate a clean shutdown during extended power outages.

The shutdown policy is:

- Ignore short power blips.
- Start a shutdown timer when the UPS goes on battery.
- Cancel the shutdown timer if line power returns.
- Shut down after 5 minutes on battery.
- Shut down immediately if the UPS reports low battery.

---

## 2. Current UPS Details

Detected UPS:

```text
Vendor: American Power Conversion
Model: Back-UPS NS 900M
USB vendor ID: 051d
USB product ID: 0002
NUT driver: usbhid-ups
NUT UPS name: desktop-ups
```

Initial verified status:

```text
battery.charge: 100
battery.runtime: 1808
battery.runtime.low: 120
battery.charge.low: 10
input.voltage: 117.0
ups.load: 24
ups.status: OL
ups.model: Back-UPS NS 900M
ups.realpower.nominal: 480
```

At approximately 24% load, estimated runtime was about 30 minutes.

Status meanings:

```text
OL = On line power
OB = On battery
LB = Low battery
```

---

## 3. Install Required Packages

Install NUT and the USB library package required for USB scanning:

```bash
sudo apt update
sudo apt install nut nut-client nut-server libusb-1.0-0-dev -y
```

Notes:

- `libusb-1.0-0` may already be installed.
- `libusb-1.0-0-dev` is required because `nut-scanner` expects the unversioned `libusb-1.0.so` library.
- Without `libusb-1.0-0-dev`, `nut-scanner -U` may report:

```text
Cannot load USB library (libusb-1.0.so) : file not found. USB search disabled.
```

---

## 4. Detect the UPS

Run:

```bash
sudo nut-scanner -U
```

Expected result for the APC Back-UPS NS 900M:

```ini
[nutdev1]
    driver = "usbhid-ups"
    port = "auto"
    vendorid = "051D"
    productid = "0002"
    product = "Back-UPS NS 900M FW:932.a10.D USB FW:a10"
    vendor = "American Power Conversion"
```

Other scanner warnings about SNMP, XML, Avahi, IPMI, or old NUT discovery can be ignored for a local USB-connected UPS.

---

## 5. Configure NUT Mode

Edit:

```bash
sudo nano /etc/nut/nut.conf
```

Set:

```ini
MODE=standalone
```

---

## 6. Configure the UPS

Edit:

```bash
sudo nano /etc/nut/ups.conf
```

Configuration:

```ini
[desktop-ups]
    driver = usbhid-ups
    port = auto
    vendorid = 051D
    productid = 0002
    desc = "APC Back-UPS NS 900M"
```

---

## 7. Configure USB Permissions

The NUT driver runs as the `nut` user and must be allowed to open the USB HID UPS device.

Create the udev rule:

```bash
sudo nano /etc/udev/rules.d/62-nut-usbups.rules
```

Configuration:

```udev
SUBSYSTEM=="usb", ATTR{idVendor}=="051d", ATTR{idProduct}=="0002", MODE="0660", GROUP="nut", TAG+="uaccess"
```

Reload udev:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Then unplug and reconnect the UPS USB cable.

If this rule is missing or not applied, the driver may fail with:

```text
libusb1: Could not open any HID devices: insufficient permissions on everything
No matching HID UPS found
```

---

## 8. Configure the NUT Monitor User

Edit:

```bash
sudo nano /etc/nut/upsd.users
```

Configuration:

```ini
[upsmon]
    password = ChangeThisPassword
    upsmon master
```

Use a local-only password. The same password must be used in `/etc/nut/upsmon.conf`.

---

## 9. Configure UPS Monitoring

Edit:

```bash
sudo nano /etc/nut/upsmon.conf
```

Required configuration:

```ini
MONITOR desktop-ups@localhost 1 upsmon ChangeThisPassword master

SHUTDOWNCMD "/sbin/shutdown -h +0"
POWERDOWNFLAG /etc/killpower

NOTIFYCMD /sbin/upssched

NOTIFYFLAG ONLINE   SYSLOG+WALL+EXEC
NOTIFYFLAG ONBATT   SYSLOG+WALL+EXEC
NOTIFYFLAG LOWBATT  SYSLOG+WALL+EXEC
NOTIFYFLAG FSD      SYSLOG+WALL+EXEC
NOTIFYFLAG COMMOK   SYSLOG+WALL
NOTIFYFLAG COMMBAD  SYSLOG+WALL
NOTIFYFLAG SHUTDOWN SYSLOG+WALL
```

If `NOTIFYFLAG` entries already exist, update them rather than duplicating them.

---

## 10. Configure Shutdown Timer Behavior

Edit:

```bash
sudo nano /etc/nut/upssched.conf
```

Configuration:

```ini
CMDSCRIPT /etc/nut/upssched-cmd
PIPEFN /run/nut/upssched.pipe
LOCKFN /run/nut/upssched.lock

AT ONLINE * CANCEL-TIMER onbatt_shutdown
AT ONLINE * EXECUTE online

AT ONBATT * START-TIMER onbatt_shutdown 300
AT ONBATT * EXECUTE onbatt

AT LOWBATT * EXECUTE lowbatt
```

The `300` value means 300 seconds, or 5 minutes.

Resulting behavior:

| Event | Behavior |
|---|---|
| UPS goes on battery | Start shutdown timer |
| Power returns before timer expires | Cancel shutdown timer |
| UPS remains on battery for 5 minutes | Start clean shutdown |
| UPS reports low battery | Start immediate clean shutdown |

---

## 11. Create the upssched Command Script

Create:

```bash
sudo nano /etc/nut/upssched-cmd
```

Script:

```bash
#!/bin/sh

case "$1" in
    onbatt)
        logger -t upssched-cmd "UPS on battery. Shutdown timer started."
        ;;

    online)
        logger -t upssched-cmd "UPS back on line power. Shutdown timer cancelled."
        ;;

    onbatt_shutdown)
        logger -t upssched-cmd "UPS has been on battery for 5 minutes. Starting clean shutdown."
        /sbin/upsmon -c fsd
        ;;

    lowbatt)
        logger -t upssched-cmd "UPS low battery. Starting immediate clean shutdown."
        /sbin/upsmon -c fsd
        ;;

    *)
        logger -t upssched-cmd "Unknown upssched event: $1"
        ;;
esac
```

Make it executable:

```bash
sudo chmod 755 /etc/nut/upssched-cmd
```

---

## 12. Start and Enable Services

Start the UPS driver:

```bash
sudo upsdrvctl start
```

Restart NUT services:

```bash
sudo systemctl restart nut-server nut-monitor
```

Enable services:

```bash
sudo systemctl enable nut-server nut-monitor
```

Optional: check whether a generated NUT driver service exists:

```bash
systemctl list-units 'nut-driver*' --all
```

If `nut-driver@desktop-ups.service` exists, enable and restart it:

```bash
sudo systemctl enable nut-driver@desktop-ups
sudo systemctl restart nut-driver@desktop-ups
sudo systemctl restart nut-server nut-monitor
```

---

## 13. Verify Status

Check service status:

```bash
systemctl status nut-server nut-monitor --no-pager
```

Expected good signs:

```text
Active: active (running)
Connected to UPS [desktop-ups]: usbhid-ups-desktop-ups
UPS: desktop-ups@localhost (primary)
```

Check live UPS status:

```bash
upsc desktop-ups@localhost
```

Quick status command:

```bash
upsc desktop-ups@localhost | egrep 'ups.status|battery.charge|battery.runtime|battery.runtime.low|battery.charge.low|input.voltage|ups.load|ups.model'
```

Expected normal status:

```text
ups.status: OL
```

---

## 14. Safe Test Procedure

Open a log watcher:

```bash
journalctl -f -t upssched-cmd -u nut-monitor -u nut-server
```

Open a second terminal:

```bash
watch -n 2 "upsc desktop-ups@localhost | egrep 'ups.status|battery.charge|battery.runtime|ups.load'"
```

Briefly unplug the UPS from wall power for 30-60 seconds.

Expected UPS status:

```text
ups.status: OB
```

Expected log message:

```text
UPS on battery. Shutdown timer started.
```

Plug the UPS back into wall power before the 5-minute shutdown timer expires.

Expected UPS status:

```text
ups.status: OL
```

Expected log message:

```text
UPS back on line power. Shutdown timer cancelled.
```

Do not leave the UPS unplugged longer than the configured timer unless intentionally testing full shutdown behavior.

---

## 15. Known Benign Messages

The following messages may appear at service startup and are not currently considered problems if the UPS later connects successfully.

```text
fopen /run/nut/upsmon.pid: No such file or directory
Could not find PID file to see if previous upsmon instance is already running!
```

This message is also benign for this local setup:

```text
upsnotify: failed to notify about state 2: no notification tech defined
```

The important operational checks are:

```text
Connected to UPS [desktop-ups]: usbhid-ups-desktop-ups
Communications with UPS desktop-ups@localhost established
ups.status: OL
```

---

## 16. Troubleshooting

### Scanner cannot load USB library

Symptom:

```text
Cannot load USB library (libusb-1.0.so) : file not found. USB search disabled.
```

Fix:

```bash
sudo apt install libusb-1.0-0-dev -y
```

Then rerun:

```bash
sudo nut-scanner -U
```

### Driver reports insufficient permissions

Symptom:

```text
libusb1: Could not open any HID devices: insufficient permissions on everything
No matching HID UPS found
```

Fix:

1. Confirm the udev rule exists:

```bash
cat /etc/udev/rules.d/62-nut-usbups.rules
```

2. Reload udev:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

3. Unplug and reconnect the UPS USB cable.

4. Restart the driver:

```bash
sudo upsdrvctl stop
sudo upsdrvctl start
```

### Server says driver is not connected

Symptom:

```text
Can't connect to UPS [desktop-ups] (usbhid-ups-desktop-ups): No such file or directory
Poll UPS [desktop-ups@localhost] failed - Driver not connected
```

Fix:

```bash
sudo upsdrvctl start
sudo systemctl restart nut-server nut-monitor
upsc desktop-ups@localhost
```

If the final status shows connected, earlier startup messages can be ignored.

---

## 17. Rebuild Checklist

After a clean OS rebuild:

```bash
sudo apt update
sudo apt install nut nut-client nut-server libusb-1.0-0-dev -y

sudo nut-scanner -U

sudo nano /etc/nut/nut.conf
sudo nano /etc/nut/ups.conf

sudo nano /etc/udev/rules.d/62-nut-usbups.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
# Unplug and reconnect the UPS USB cable here.

sudo nano /etc/nut/upsd.users
sudo nano /etc/nut/upsmon.conf
sudo nano /etc/nut/upssched.conf
sudo nano /etc/nut/upssched-cmd
sudo chmod 755 /etc/nut/upssched-cmd

sudo upsdrvctl start
sudo systemctl enable nut-server nut-monitor
sudo systemctl restart nut-server nut-monitor

upsc desktop-ups@localhost
```

---

## 18. Repository Cross-References

Recommended filename:

```text
UPS_Configuration.md
```

Recommended references from other system documentation:

- `Detailed_Rebuild_Guide.md`
- `Hardened_Sysadmin_Build.md`
- `Setup_Checklist.md`

Suggested link text:

```markdown
For UPS monitoring and shutdown configuration, see [UPS_Configuration.md](UPS_Configuration.md).
```
