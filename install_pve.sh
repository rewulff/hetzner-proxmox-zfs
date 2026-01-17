#!/bin/bash
set -e

# --- CONFIGURATION ---
ISO_DEST="/tmp/proxmox.iso"
ISO_BASE_URL="https://enterprise.proxmox.com/iso/"

# Define disks
DISK1="/dev/nvme0n1"
DISK2="/dev/nvme1n1"

echo "================================================="
echo "   HETZNER PVE ZFS INSTALLER (REV 3.0)"
echo "================================================="

# --- 1. INTERFACE DETECTION ---
echo "[1/8] Analyzing Network..."
CURRENT_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
ALT_NAME=$(ip link show dev "$CURRENT_IF" | grep -oP 'altname \Ken\w+' | head -n1)

if [ -n "$ALT_NAME" ]; then
    REAL_IFACE="$ALT_NAME"
    echo " -> Detected Altname: $ALT_NAME (will be used)"
else
    REAL_IFACE="$CURRENT_IF"
    echo " -> No Altname found. Using: $CURRENT_IF"
fi

MY_IP=$(ip -4 addr show "$CURRENT_IF" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
MY_GW=$(ip route | grep default | awk '{print $3}')
MY_CIDR="27"

if [ -d /sys/firmware/efi ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="LEGACY"
fi
echo " -> Mode: $BOOT_MODE | IP: $MY_IP | GW: $MY_GW"


# --- 2. SETTINGS QUERY ---

# A) ISO Version
echo ""
echo "Which Proxmox Major Version should be loaded?"
echo " (Automatically searches for the latest Minor-Version in the Repo)"
read -p "Version [8]: " PVE_VER
PVE_VER=${PVE_VER:-8} # Default to 8 if empty

# B) Keyboard Layout
echo ""
echo "Keyboard layout for installer:"
echo " 1) German (de) - Default"
echo " 2) English (en-us)"
read -p "Choice [1]: " KEY_CHOICE
case "$KEY_CHOICE" in
    2) K_LAYOUT="en-us" ;;
    *) K_LAYOUT="de" ;;
esac

# C) VNC Password
echo ""
echo -n "Set VNC Password: "
read -s VNC_PASSWORD
echo
if [ -z "$VNC_PASSWORD" ]; then echo "Error: Password cannot be empty!"; exit 1; fi

# D) Wipe Option (NEW!)
echo ""
echo "-----------------------------------------------------"
echo " WIPE DISKS OPTION"
echo " Should the disks ($DISK1 & $DISK2) be completely wiped?"
echo " Choose 'n' if you only want to restart QEMU (Resume)."
echo " Choose 'y' for a fresh installation."
echo "-----------------------------------------------------"
read -p "Wipe disks? (y/n) [y]: " WIPE_CONFIRM
WIPE_CONFIRM=${WIPE_CONFIRM:-y}


# --- 3. WIPE ROUTINE (OPTIONAL) ---
if [[ "$WIPE_CONFIRM" =~ ^[Yy]$ ]]; then
    echo ""
    echo "[2/8] Wiping Disks (Deep Clean)..."
    
    # Kill old QEMU instances
    killall qemu-system-x86_64 2>/dev/null || true
    
    # Stop RAID/ZFS
    mdadm --stop --scan >/dev/null 2>&1 || true
    swapoff -a >/dev/null 2>&1 || true
    
    # Remove ZFS Labels
    zpool labelclear -f "$DISK1" >/dev/null 2>&1 || true
    zpool labelclear -f "$DISK2" >/dev/null 2>&1 || true
    
    # Delete Filesystem Signatures
    wipefs -a -f "$DISK1" >/dev/null
    wipefs -a -f "$DISK2" >/dev/null
    
    # Zeroing Boot Sectors
    dd if=/dev/zero of="$DISK1" bs=1M count=100 status=none
    dd if=/dev/zero of="$DISK2" bs=1M count=100 status=none
    echo " -> Wipe completed."
else
    echo ""
    echo "[2/8] SKIP WIPE: Existing data will be preserved."
    killall qemu-system-x86_64 2>/dev/null || true
fi


# --- 4. PREPARATION ---
echo "[3/8] Checking Tools..."
apt-get update -qq >/dev/null
apt-get install -y qemu-system-x86 curl netcat-openbsd ovmf >/dev/null 2>&1


# --- 5. DOWNLOAD ISO (DYNAMIC) ---
# Check if ISO already exists AND we don't want to wipe (Resume)
# If we're wiping, we want to make sure we have the correct version?
# No, ISO Download is independent of Disk Wipe. We simply check for existence.

if [ ! -f "$ISO_DEST" ]; then
    echo "[4/8] Searching for latest Proxmox VE $PVE_VER ISO..."
    
    # Regex builds dynamically: proxmox-ve_9.*\.iso or proxmox-ve_8.*\.iso
    ISO_FILENAME=$(curl -s "$ISO_BASE_URL" | grep -o "proxmox-ve_${PVE_VER}[^\"]*\.iso" | sort -V | tail -n1)

    if [[ -z "$ISO_FILENAME" ]]; then
        echo "❌ ERROR: No ISO found for version $PVE_VER at $ISO_BASE_URL!"
        echo "   Check your version input."
        exit 1
    fi
    
    echo "   → Found: $ISO_FILENAME"
    echo "   → Downloading to $ISO_DEST..."

    curl -L "${ISO_BASE_URL}${ISO_FILENAME}" -o "$ISO_DEST"
    
    if [ ! -f "$ISO_DEST" ]; then
        echo "❌ Download failed."
        exit 1
    fi
else
    echo "[4/8] ISO already exists ($ISO_DEST). Skipping download."
    echo "      (Delete the file manually to force a new download)"
fi


# --- 6. CONFIG GENERATION ---
echo "[5/8] Generating network config..."
cat > /tmp/interfaces.final << EOF
auto lo
iface lo inet loopback

iface $REAL_IFACE inet manual

auto vmbr0
iface vmbr0 inet static
    address $MY_IP/$MY_CIDR
    gateway $MY_GW
    bridge-ports $REAL_IFACE
    bridge-stp off
    bridge-fd 0
EOF


# --- 7. START QEMU ---
echo "[6/8] Starting VM ($BOOT_MODE)..."

COMMON_OPTS="-daemonize -enable-kvm -m 8192 -cpu host -smp 4 \
-drive file=$DISK1,format=raw,media=disk,if=virtio \
-drive file=$DISK2,format=raw,media=disk,if=virtio \
-cdrom $ISO_DEST -boot d \
-k $K_LAYOUT \
-vnc :0,password \
-monitor telnet:127.0.0.1:4444,server,nowait \
-net nic,model=virtio -net user"

if [ "$BOOT_MODE" == "UEFI" ]; then
    cp /usr/share/OVMF/OVMF_VARS.fd /tmp/ovmf_vars.fd
    qemu-system-x86_64 $COMMON_OPTS \
      -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
      -drive if=pflash,format=raw,file=/tmp/ovmf_vars.fd
else
    qemu-system-x86_64 $COMMON_OPTS
fi

sleep 3
echo "change vnc password $VNC_PASSWORD" | nc -q 1 127.0.0.1 4444 >/dev/null

echo ""
echo "================================================="
echo "   READY TO INSTALL"
echo "================================================="
echo "1. SSH Tunnel: ssh -L 5900:localhost:5900 root@$MY_IP"
echo "2. VNC: localhost:5900"
echo "3. Installer: ZFS (RAID1), ashift=12"
echo "4. IMPORTANT: After Reboot -> Run './post_install.sh'!"
