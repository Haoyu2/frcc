# FRCC VM Creation on vCenter

## VM Specifications

### Choose your tier:

**Minimum (smoke tests + small reruns)**
- vCPU: 8
- RAM: 16 GB
- Disk: 120 GB thin-provisioned
- Datastore: SSD preferred
- Network: 1 vNIC (VMXNET3)
- Ubuntu: 22.04 LTS (Server)

**Recommended (overnight full sweeps)** ← Suggested for production
- vCPU: 16
- RAM: 32 GB
- Disk: 250 GB thin-provisioned (or 200+ GB)
- Datastore: local NVMe/SSD strongly preferred
- Network: 1 vNIC (VMXNET3)
- Ubuntu: 22.04 LTS (Server)

---

## Step-by-Step VM Creation in vCenter

### 1. Launch VM Creation Wizard
   - In vCenter, right-click on your target cluster/host → **New Virtual Machine**
   - Or go to **VMs and Templates** → **Create / Register VM**

### 2. Select Creation Type
   - Choose **Create a new virtual machine**
   - Click **Next**

### 3. Name and Folder
   - VM Name: `frcc-ubuntu-vm` (or your preferred name)
   - Select appropriate folder/datacenter
   - Click **Next**

### 4. Select a Compute Resource
   - Choose target cluster or ESXi host
   - Click **Next**

### 5. Select Storage
   - Choose SSD-backed datastore (NVMe/local SSD preferred)
   - Click **Next**

### 6. Select Compatibility
   - ESXi version: Select latest compatible (usually default)
   - Click **Next**

### 7. Select a Guest OS
   - **Guest OS family**: Linux
   - **Guest OS version**: Ubuntu Linux (64-bit)
   - Click **Next**

### 8. Customize Hardware
Configure with specs for your chosen tier:

| Setting | Value |
|---------|-------|
| **CPU** | 8-16 vCPU (check "Preferred core count per socket") |
| **Memory** | 16-32 GB |
| **Disk 1** | 120-250 GB, thin-provisioned |
| **Disk Controller** | VMware Paravirtual (default) |
| **Network** | 1 vNIC, adapter type: **VMXNET3** |
| **Firmware** | UEFI (default) |
| **CD/DVD Drive** | Connect to Ubuntu 22.04 LTS ISO |

#### CPU Topology Details:
- For 8 vCPU: 1 socket × 8 cores
- For 16 vCPU: 1 socket × 16 cores (or 2 sockets × 8 cores)

### 9. Ready to Complete
   - Review settings
   - Click **Finish**

---

## Post-Creation: Initial Ubuntu Setup

After VM boots:

```bash
# Update system
sudo apt update
sudo apt upgrade -y
sudo apt install -y build-essential git openssh-server curl wget ca-certificates

# Install kernel headers (required for FRCC kernel module)
sudo apt install -y linux-headers-"$(uname -r)" linux-modules-extra-"$(uname -r)"

# Set timezone (optional but recommended)
sudo timedatectl set-timezone UTC

# Enable SSH
sudo systemctl enable --now ssh

# Reboot
sudo reboot
```

---

## vCenter-Specific Best Practices

### Time Synchronization
- Keep **VMware Tools time sync** enabled in VM settings
- Or configure NTP separately, but don't use both

### Memory Reservation
- Optional: Set memory reservation = allocated memory for lower jitter on busy hosts

### Snapshots (Recommended)
After each major step, take snapshots for recovery:
- **Snapshot A**: Fresh OS, patched, ready-to-use baseline
- **Snapshot B**: After installing FRCC dependencies (conda, kernel headers)
- **Snapshot C**: FRCC fully set up and tested (before long experiment runs)

To create: Power off → Right-click VM → **Snapshot** → **Take Snapshot**

### Monitoring
- Monitor VM CPU, memory, and disk usage during setup and tests
- Use vCenter performance charts to validate resource allocation

---

## Next Steps After VM Creation

Once VM is ready, follow the FRCC setup guide:
1. Clone FRCC repo and initialize submodules
2. Run `experiments/cc_bench/setup.sh` to install dependencies
3. Build kernel module in `frcc_kernel/`
4. Validate with `python sweep.py -t debug`

See the full guide for automation and testing workflows.

