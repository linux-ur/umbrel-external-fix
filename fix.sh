#!/usr/bin/env bash
# umbrel-storage-patch.sh — Enable external storage on any hardware
# Usage: sudo bash umbrel-storage-patch.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }
error()   { echo -e "${RED}✗${NC} $1" >&2; }
info()    { echo -e "${CYAN}→${NC} $1"; }
banner()  {
    echo
    echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}${BOLD}║       Umbrel Storage Patch v1.0          ║${NC}"
    echo -e "${BLUE}${BOLD}║  Enable external drives on any hardware  ║${NC}"
    echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo
}
section() {
    echo
    echo -e "${BOLD}── $1 ──────────────────────────────────────${NC}"
    echo
}

confirm() {
    local MSG="$1"
    local DEFAULT="${2:-y}"
    local PROMPT
    if [[ "$DEFAULT" == "y" ]]; then
        PROMPT="[Y/n]"
    else
        PROMPT="[y/N]"
    fi
    read -rp "$(echo -e "${YELLOW}?${NC} $MSG $PROMPT: ")" REPLY
    REPLY="${REPLY:-$DEFAULT}"
    [[ "$REPLY" =~ ^[Yy]$ ]]
}

# ── Root check ──────────────────────────────────────────────────────────────
banner

if [[ $EUID -ne 0 ]]; then
    error "Please run as root: sudo bash $0"
    exit 1
fi

# ── Umbrel check ─────────────────────────────────────────────────────────────
UMBRELD_DIR="/opt/umbreld/source/modules"
if [[ ! -d "$UMBRELD_DIR" ]]; then
    error "Umbrel not found at /opt/umbreld. Is UmbrelOS installed?"
    exit 1
fi

UMBREL_VERSION=$(cat /opt/umbreld/package.json 2>/dev/null | grep '"version"' | head -1 | grep -oP '[\d.]+' || echo "unknown")
log "UmbrelOS $UMBREL_VERSION detected"

# ── Show available disks ─────────────────────────────────────────────────────
section "Available Storage Devices"

echo -e "${BOLD}  NAME       TRAN   SIZE    MODEL${NC}"
echo -e "  ─────────────────────────────────────────"
while IFS= read -r LINE; do
    NAME=$(echo "$LINE" | awk '{print $1}')
    TRAN=$(echo "$LINE" | awk '{print $2}')
    SIZE=$(echo "$LINE" | awk '{print $3}')
    MODEL=$(echo "$LINE" | awk '{$1=$2=$3=""; print substr($0,4)}')

    case "$TRAN" in
        usb)  COLOR="$GREEN"  ;;
        nvme) COLOR="$CYAN"   ;;
        mmc)  COLOR="$YELLOW" ;;
        sata) COLOR="$BLUE"   ;;
        *)    COLOR="$NC"     ;;
    esac

    printf "  ${COLOR}%-10s %-6s %-7s %s${NC}\n" "$NAME" "$TRAN" "$SIZE" "$MODEL"
done < <(lsblk -d -n -o NAME,TRAN,SIZE,MODEL 2>/dev/null | grep -v "^loop")

echo
info "Green=USB  Cyan=NVMe  Yellow=MMC  Blue=SATA"

# ── Select disk to mount ─────────────────────────────────────────────────────
section "Select a Disk to Mount"

mapfile -t ALL_DISKS < <(lsblk -d -n -o NAME,TRAN,SIZE,MODEL 2>/dev/null | grep -v "^loop" | grep -v "^mmcblk0 ")

if [[ ${#ALL_DISKS[@]} -eq 0 ]]; then
    warn "No external disks detected. Patches will still be applied."
    SELECTED_PART=""
else
    echo -e "  ${BOLD}#   Device     Tran   Size    Model${NC}"
    echo -e "  ─────────────────────────────────────────────"
    for i in "${!ALL_DISKS[@]}"; do
        NAME=$(echo "${ALL_DISKS[$i]}" | awk '{print $1}')
        TRAN=$(echo "${ALL_DISKS[$i]}" | awk '{print $2}')
        SIZE=$(echo "${ALL_DISKS[$i]}" | awk '{print $3}')
        MODEL=$(echo "${ALL_DISKS[$i]}" | awk '{$1=$2=$3=""; print substr($0,4)}')
        printf "  ${CYAN}[%d]${NC} %-10s %-6s %-7s %s\n" "$i" "$NAME" "$TRAN" "$SIZE" "$MODEL"
    done
    echo -e "  ${YELLOW}[s]${NC} Skip — apply patches only, no mount"
    echo

    read -rp "$(echo -e "${YELLOW}?${NC} Choose a disk [0-$((${#ALL_DISKS[@]}-1))/s]: ")" CHOICE

    if [[ "$CHOICE" == "s" || "$CHOICE" == "S" ]]; then
        SELECTED_PART=""
        info "Skipping disk mount"
    else
        SELECTED_NAME=$(echo "${ALL_DISKS[$CHOICE]}" | awk '{print $1}')
        SELECTED_DEV="/dev/$SELECTED_NAME"

        # List partitions
        mapfile -t PARTS < <(lsblk -n -o NAME,SIZE,FSTYPE "$SELECTED_DEV" 2>/dev/null | tail -n +2)

        if [[ ${#PARTS[@]} -eq 0 ]]; then
            warn "No partitions found on $SELECTED_DEV"
            SELECTED_PART=""
        elif [[ ${#PARTS[@]} -eq 1 ]]; then
            SELECTED_PART="/dev/$(echo "${PARTS[0]}" | awk '{print $1}')"
            SELECTED_FSTYPE=$(echo "${PARTS[0]}" | awk '{print $3}')
            log "Using partition: $SELECTED_PART ($SELECTED_FSTYPE)"
        else
            echo
            echo -e "  ${BOLD}#   Partition   Size    Filesystem${NC}"
            echo -e "  ───────────────────────────────────"
            for i in "${!PARTS[@]}"; do
                PNAME=$(echo "${PARTS[$i]}" | awk '{print $1}')
                PSIZE=$(echo "${PARTS[$i]}" | awk '{print $2}')
                PFS=$(echo "${PARTS[$i]}" | awk '{print $3}')
                printf "  ${CYAN}[%d]${NC} %-12s %-7s %s\n" "$i" "$PNAME" "$PSIZE" "$PFS"
            done
            echo
            read -rp "$(echo -e "${YELLOW}?${NC} Choose a partition [0-$((${#PARTS[@]}-1))]: ")" PCHOICE
            SELECTED_PART="/dev/$(echo "${PARTS[$PCHOICE]}" | awk '{print $1}')"
            SELECTED_FSTYPE=$(echo "${PARTS[$PCHOICE]}" | awk '{print $3}')
            log "Using partition: $SELECTED_PART ($SELECTED_FSTYPE)"
        fi
    fi
fi

# ── Mount path ───────────────────────────────────────────────────────────────
MOUNT_PATH=""
MOUNT_NAME="External"

if [[ -n "${SELECTED_PART:-}" ]]; then
    section "Mount Configuration"

    DETECTED_FSTYPE=$(blkid -s TYPE -o value "$SELECTED_PART" 2>/dev/null || echo "exfat")
    DETECTED_UUID=$(blkid -s UUID -o value "$SELECTED_PART" 2>/dev/null || echo "")

    read -rp "$(echo -e "${YELLOW}?${NC} Mount folder name [default: External]: ")" MOUNT_NAME
    MOUNT_NAME="${MOUNT_NAME:-External}"
    MOUNT_NAME="${MOUNT_NAME// /_}"

    MOUNT_PATH="/data/umbrel-os/home/umbrel/$MOUNT_NAME"
    info "Will mount at: /home/umbrel/$MOUNT_NAME"
fi

# ── Apply patches ─────────────────────────────────────────────────────────────
section "Applying Patches"

PATCH_DIR="/data/umbrel-patches"
mkdir -p "$PATCH_DIR"

patch_file() {
    local FILE="$1"
    local SEARCH="$2"
    local REPLACE="$3"
    local DESC="$4"

    if [[ ! -f "$FILE" ]]; then
        warn "$DESC — file not found, skipping"
        return
    fi

    if grep -qF "$REPLACE" "$FILE" 2>/dev/null; then
        log "$DESC — already patched"
        return
    fi

    cp "$FILE" "${FILE}.bak-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    sed -i "s|$SEARCH|$REPLACE|g" "$FILE"

    if grep -qF "$REPLACE" "$FILE" 2>/dev/null; then
        log "$DESC"
    else
        warn "$DESC — pattern not found (Umbrel may have changed this file)"
    fi
}

patch_file \
    "$UMBRELD_DIR/files/external-storage.ts" \
    "device.transport === 'usb'" \
    "['usb','nvme','mmc','sata'].includes(device.transport)" \
    "Enable all transport types (USB, NVMe, MMC, SATA)"

patch_file \
    "$UMBRELD_DIR/is-umbrel-home.ts" \
    "return manufacturer === 'Umbrel, Inc.' && model === 'Umbrel Home'" \
    "return true" \
    "Remove Umbrel Home hardware restriction"

patch_file \
    "$UMBRELD_DIR/files/external-storage.ts" \
    "return isNotRaspberryPi" \
    "return true" \
    "Remove Raspberry Pi restriction"

# Save patched files to /data so they survive reboots
cp "$UMBRELD_DIR/files/external-storage.ts" "$PATCH_DIR/external-storage.ts" 2>/dev/null || true
cp "$UMBRELD_DIR/is-umbrel-home.ts"          "$PATCH_DIR/is-umbrel-home.ts"   2>/dev/null || true

log "Patched files saved to $PATCH_DIR"

# ── Install permanent hook ───────────────────────────────────────────────────
section "Installing Permanent Hook"

HOOK_DIR="/home/umbrel/umbrel/custom-hooks"
HOOK_FILE="$HOOK_DIR/pre-start"
mkdir -p "$HOOK_DIR"

{
cat << 'HOOK'
#!/bin/bash
# umbrel-storage-patch — re-applied on every boot

UMBRELD_DIR="/opt/umbreld/source/modules"
PATCH_DIR="/data/umbrel-patches"

# Restore patched files
[[ -f "$PATCH_DIR/external-storage.ts" ]] && cp "$PATCH_DIR/external-storage.ts" "$UMBRELD_DIR/files/external-storage.ts"
[[ -f "$PATCH_DIR/is-umbrel-home.ts"   ]] && cp "$PATCH_DIR/is-umbrel-home.ts"   "$UMBRELD_DIR/is-umbrel-home.ts"

HOOK

if [[ -n "${MOUNT_PATH:-}" ]]; then
    if [[ -n "${DETECTED_UUID:-}" ]]; then
        MOUNT_SRC="UUID=$DETECTED_UUID"
    else
        MOUNT_SRC="$SELECTED_PART"
    fi

    cat << HOOK
# Mount external drive
mkdir -p "$MOUNT_PATH"
if ! mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
    mount -t $DETECTED_FSTYPE -o uid=1000,gid=1000,umask=0022 $MOUNT_SRC "$MOUNT_PATH" 2>/dev/null || true
fi
HOOK
fi

} > "$HOOK_FILE"

chmod +x "$HOOK_FILE"
log "Hook installed at $HOOK_FILE"

# ── Mount now ─────────────────────────────────────────────────────────────────
if [[ -n "${MOUNT_PATH:-}" ]]; then
    section "Mounting Drive"

    mkdir -p "$MOUNT_PATH"

    if mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
        warn "Already mounted, unmounting first..."
        umount -l "$MOUNT_PATH" 2>/dev/null || true
    fi

    if [[ -n "${DETECTED_UUID:-}" ]]; then
        mount -t "$DETECTED_FSTYPE" -o uid=1000,gid=1000,umask=0022 "UUID=$DETECTED_UUID" "$MOUNT_PATH" 2>/dev/null || \
        mount -t "$DETECTED_FSTYPE" -o uid=1000,gid=1000,umask=0022 "$SELECTED_PART" "$MOUNT_PATH" 2>/dev/null || true
    else
        mount -t "$DETECTED_FSTYPE" -o uid=1000,gid=1000,umask=0022 "$SELECTED_PART" "$MOUNT_PATH" 2>/dev/null || true
    fi

    if mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
        log "Drive mounted at /home/umbrel/$MOUNT_NAME"
        AVAIL=$(df -h "$MOUNT_PATH" | tail -1 | awk '{print $4}')
        info "Available space: $AVAIL"
    else
        warn "Could not mount the drive right now — will retry on next boot"
    fi
fi

# ── Restart Umbrel ────────────────────────────────────────────────────────────
section "Restarting Umbrel"

info "This may take a moment..."
if systemctl restart umbrel 2>/dev/null; then
    log "Umbrel restarted successfully"
else
    warn "Could not restart Umbrel automatically"
    info "Run manually: sudo systemctl restart umbrel"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║              All done! 🎉                ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo
log "Patches applied and permanent hook installed"

if [[ -n "${MOUNT_PATH:-}" ]]; then
    echo -e "  ${CYAN}Drive path:${NC}     /home/umbrel/$MOUNT_NAME"
fi

echo -e "  ${CYAN}Hook location:${NC}  $HOOK_FILE"
echo -e "  ${CYAN}Patch storage:${NC}  $PATCH_DIR"
echo
info "Patches survive reboots and are re-applied automatically."
info "If Umbrel updates break this, just run the script again."
echo
warn "Open Umbrel Files — your drive should appear under External Drives!"
echo
