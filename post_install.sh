#!/bin/bash
echo "================================================="
echo "   POST-INSTALL FIXER"
echo "================================================="

# 1. Kill QEMU
echo "-> Killing QEMU process..."
killall qemu-system-x86_64 2>/dev/null || true
sleep 2

# 2. Activate Hetzner ZFS Tools
echo "-> Activating ZFS tools (Hetzner wrapper)..."
echo "y" | zpool status >/dev/null 2>&1 || true
sleep 5

# 3. Mount ZFS
echo "-> Importing ZFS rpool..."
# We use -f (force) and -R (altroot)
zpool import -f -R /mnt rpool

# CHECK: Did the import work?
if ! zpool status rpool >/dev/null 2>&1; then
    echo "❌ ERROR: ZFS Pool 'rpool' could not be imported."
    echo "   Did the installation finish successfully?"
    echo "   Did you select ZFS RAID1 in the installer?"
    exit 1
fi

if [ ! -d "/mnt/etc" ]; then
    echo "❌ ERROR: /mnt/etc not found."
    echo "   The pool is imported, but the dataset seems empty or not mounted."
    echo "   Try running: zfs mount -a"
    zfs mount -a
fi

# 4. Inject Network Config
echo "-> Injecting correct network configuration..."
if [ -f /tmp/interfaces.final ]; then
    cp /tmp/interfaces.final /mnt/etc/network/interfaces
    echo "   [OK] interfaces copied."
else
    echo "❌ ERROR: /tmp/interfaces.final not found. Did you run install_pve.sh?"
    exit 1
fi

# 5. Fix Hosts & DNS
echo "-> Fixing /etc/hosts and DNS..."
sed -i '/127.0.1.1/d' /mnt/etc/hosts

MY_IP=$(grep "address" /tmp/interfaces.final | awk '{print $2}' | cut -d'/' -f1)
echo "$MY_IP pve.mygpg.de pve" >> /mnt/etc/hosts

echo "nameserver 185.12.64.1" > /mnt/etc/resolv.conf
echo "nameserver 185.12.64.2" >> /mnt/etc/resolv.conf

# 6. Finish
echo "-> Exporting pool..."
zpool export rpool

echo "================================================="
echo "   SUCCESS! REBOOTING NOW..."
echo "================================================="
reboot
