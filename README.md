# Proxmox VE ZFS Root Installation on Hetzner Dedicated Servers (Legacy/UEFI Auto-Detect)

This guide and script collection enables the installation of **Proxmox VE with native ZFS Root** (e.g., RAID1 on NVMe) on Hetzner Dedicated Servers. 

It solves common issues encountered when using standard installation methods or older QEMU guides:
* **Network Interface Mismatch:** Handles the discrepancy between QEMU (`ens18`) and Bare Metal (`enpKs0`) naming.
* **Boot Mode detection:** Automatically detects if the server is running in **Legacy BIOS** or **UEFI** mode and configures QEMU accordingly (fixing the "No bootable device" loop).
* **Subnet Issues:** Automatically handles Hetzner's `/32` vs `/27` routing requirements.

## ⚠️ Disclaimer
**Use at your own risk.** This process involves wiping hard drives (`wipefs`). Ensure you have backups. I am not responsible for data loss.

## Prerequisites
* Hetzner Dedicated Server (tested on AX/EX lines with NVMe).
* Server booted into **Rescue System (Linux 64bit)**.
* SSH Access to the Rescue System.
* A VNC Viewer on your local machine.

## Installation Steps

### 1. Preparation
SSH into your server in Rescue Mode:

```bash
ssh root@<your-server-ip>
```

Download the scripts from this repo (or create them manually):

```bash
wget https://raw.githubusercontent.com/rewulff/hetzner-proxmox-zfs/main/install_pve.sh
wget https://raw.githubusercontent.com/rewulff/hetzner-proxmox-zfs/main/post_install.sh
chmod +x install_pve.sh post_install.sh

```

### 2. Start the Installation (QEMU)

Run the main install script. It will detect your hardware, wipe old signatures, download the Proxmox ISO, and start the VNC session.

```bash
./install_pve.sh

```

Follow the on-screen instructions. The script will tell you the **VNC Password** and the **SSH Tunnel Command**.

### 3. VNC Installation

1. Open a terminal on your **local machine** and create the tunnel (as displayed by the script):
```bash
ssh -L 5900:localhost:5900 root@<your-server-ip>

```


2. Open your VNC Viewer and connect to `localhost:5900`.
3. Proceed through the Proxmox Installer:
* **Target Disk:** Options -> **ZFS (RAID1)** (or RAID0/RAIDZ).
* **Advanced Options:** Set `ashift=12` (Critical for NVMe performance!).
* **Network:** Leave everything as default (DHCP). **Uncheck** "Pin network interface names".


4. **CRITICAL:** When installation finishes, click **"Reboot"** in the VNC window.
5. **IMMEDIATELY** switch back to your SSH terminal.

### 4. The Fix (Post-Install)

Once the VNC window goes black or disconnects, QEMU has rebooted. **Do not let it try to boot again.**

Kill the QEMU process and run the post-install script to inject the correct network configuration and host settings:

```bash
./post_install.sh

```

This script will:

1. Mount your new ZFS pool.
2. Inject the correct `enp*` network interface name (detected from hardware).
3. Fix the `/etc/hosts` and `/etc/resolv.conf`.
4. Reboot the server.

### 5. Done

After a few minutes, your Proxmox VE server should be reachable via SSH and the Web Interface (`https://<your-ip>:8006`).

---

**Credits:** Based on extensive debugging of Hetzner hardware quirks.
