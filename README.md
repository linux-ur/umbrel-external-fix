# Umbrel External Storage Fix

This fix patches Umbrel's external storage detection logic to allow additional storage device types (`NVMe` and `MMC`) alongside standard USB devices.

## Overview

By default, Umbrel only recognizes storage devices whose transport type is `usb`.

This patch modifies the detection logic in:

```text
/opt/umbreld/source/modules/files/external-storage.ts
```

so that the following device types are accepted:

* USB (`usb`)
* NVMe (`nvme`)
* MMC / SD Card (`mmc`)

## What the Patch Changes

Original condition:

```typescript
device.transport === 'usb'
```

Patched condition:

```typescript
['usb', 'nvme', 'mmc'].includes(device.transport)
```

This allows Umbrel to detect and use NVMe drives and SD/MMC storage devices as external storage.

## Requirements

* Umbrel installed and running
* Root or sudo access
* Linux system with `systemd`
* Bash shell

## Installation

1. Download the reposity:

```bash
git clone https://github.com/linux-ur/umbrel-external-fix
```

2. Change the directory
```bash
cd umbrel-external-fix
```

3. Make it executable:

```bash
chmod +x fix.sh
```

4. Run the script:

```bash
sudo ./fix.sh
```

## What the Script Does

1. Verifies that the Umbrel source file exists.
2. Creates a backup of the original file.
3. Applies the storage detection patch.
4. Lists all detected block devices.
5. Displays devices eligible for Umbrel storage.
6. Restarts the Umbrel service.

## Example Output

```text
[+] Verifying Umbrel installation
[+] Applying patch
[+] Patch applied successfully

[+] Detected devices

NAME    TRAN  SIZE MODEL
sda     usb   1.8T Samsung SSD
nvme0n1 nvme  2.0T WD Black SN850

[+] Eligible devices (usb, nvme, mmc)

 - sda (usb)
 - nvme0n1 (nvme)

[+] Restarting Umbrel
[+] Umbrel restarted successfully

[+] Done
```

## Backup and Rollback

Before modifying the file, the script automatically creates a backup:

```text
/opt/umbreld/source/modules/files/external-storage.ts.backup
```

To restore the original version:

```bash
sudo cp \
/opt/umbreld/source/modules/files/external-storage.ts.backup \
/opt/umbreld/source/modules/files/external-storage.ts

sudo systemctl restart umbrel
```

## Verify Detection

Check available storage devices:

```bash
lsblk -d -o NAME,TRAN,SIZE,MODEL
```

Check transport types:

```bash
lsblk -d -o NAME,TRAN
```

Expected supported transport values:

```text
usb
nvme
mmc
```

## Disclaimer

This is an unofficial modification and is not maintained by the Umbrel team. Future Umbrel updates may overwrite the patched file, requiring the fix to be applied again. Use at your own risk and always keep backups before modifying system files.
