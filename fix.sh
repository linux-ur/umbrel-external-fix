#!/usr/bin/env bash

set -euo pipefail

PATCH_FILE="/opt/umbreld/source/modules/files/external-storage.ts"
BACKUP_FILE="${PATCH_FILE}.backup"

log() {
    echo "[+] $1"
}

error() {
    echo "[!] $1" >&2
}

# Verify file exists
log "Verifying Umbrel installation"

if [[ ! -f "$PATCH_FILE" ]]; then
    error "File not found: $PATCH_FILE"
    exit 1
fi

# Apply patch
log "Applying patch"

if grep -q "\['usb','nvme','mmc'\]" "$PATCH_FILE"; then
    log "Patch already applied"
else
    cp "$PATCH_FILE" "$BACKUP_FILE"

    # Safer sed (handles variations better)
    sed -i \
    "s/device\.transport === 'usb'/['usb','nvme','mmc'].includes(device.transport)/g" \
    "$PATCH_FILE"

    log "Patch applied successfully"
fi

# List devices
echo
log "Detected devices"
lsblk -d -o NAME,TRAN,SIZE,MODEL

echo
log "Eligible devices (usb, nvme, mmc)"

while read -r DEV TRAN; do
    case "$TRAN" in
        usb|nvme|mmc)
            echo " - $DEV ($TRAN)"
            ;;
    esac
done < <(lsblk -d -n -o NAME,TRAN)

# Restart service
echo
log "Restarting Umbrel"

if systemctl restart umbrel; then
    log "Umbrel restarted successfully"
else
    error "Failed to restart Umbrel"
    exit 1
fi

echo
log "Done"
