# Hypervisor Provisioning & VM Configuration Guide

This guide details what settings to configure when provisioning the Root CA and Intermediate CA VMs on **XCP-ng / Xen Orchestra**, **TrueNAS (KVM/bhyve)**, or **Local Workstations (QEMU/WSL2)** compared to a stock VM installation.

---

## 1. Summary: Stock VM vs. CA VMs

| Setting / Property | Stock Workload VM | Root CA VM (Offline) | Intermediate CA VM (`ica.dc.paradigm-works.com`) |
| :--- | :--- | :--- | :--- |
| **Lifecycle / State** | Powered on 24/7 | **Powered off 99.9% of the time** | Powered on 24/7 (systemd supervised) |
| **Virtual NICs** | 1+ interfaces on default LAN/VLAN | **0 interfaces, or detached virtual cable** | 1 interface on secure internal server VLAN |
| **IP Assignment** | DHCP or static | None | Static IP or DHCP reservation bound to MAC |
| **Disk Size** | 20 GB – 100+ GB | **8 GB – 10 GB** (Minimal) | **10 GB – 15 GB** (Minimal) |
| **Cloud-Init Source** | Optional / generic | Attached `root-ca-cidata.iso` on first boot | Attached `intermediate-ca-cidata.iso` on first boot |
| **Hypervisor Backups** | Nightly snapshot / VDI export | **Manual cold export only** (Encrypted) | Stateless rebuild strategy (No restore needed) |
| **Console Access** | SSH or hypervisor console | **Hypervisor Console Only** (SSH disabled) | SSH (port 22) + Web ports (80, 443) |
| **Guest Tools / Agent** | ISO install or repo package | `xe-guest-utilities` (via APT) | `xe-guest-utilities` (via APT) |
| **OS Patching / Updates** | Manual or scheduled | **Static / Frozen** (No automatic updates) | Automated security patches (`unattended-upgrades`) |

---

## 2. XCP-ng / Xen Orchestra Deployment Process

### Preferred Method: Native Cloud-Init (No ISO Needed)
Xen Orchestra has a built-in Cloud-Init / ConfigDrive injector:
1. When creating a VM from a Cloud template, scroll to the **Cloud-init / Config drive** section.
2. Select **Custom config**.
3. Paste the contents of `user-data` directly into the text box.
XO will automatically generate and attach an ephemeral config drive during first boot.

> **Note on Guest Agent & Updates:**
> - Both VMs install the native **`xe-guest-utilities`** package via APT. Do **not** attach the old XCP-ng guest tools ISO.
> - The Intermediate CA configures **`unattended-upgrades`** for automatic security patching.
> - The Root CA is kept frozen/immutable and receives no automated updates while powered down.

### Alternative Method: Generate NoCloud ISOs
If deploying via standard VM templates without native cloud-init injection:
```bash
cd /path/to/local-CA/provisioning/scripts

# Build Root CA ISO
./build-cidata-iso.sh root-ca /path/to/iso-sr/root-ca-cidata.iso

# Build Intermediate CA ISO
./build-cidata-iso.sh intermediate-ca /path/to/iso-sr/intermediate-ca-cidata.iso
```
Place these `.iso` files inside your XCP-ng ISO Storage Repository (NFS or SMB share).

---

### Step 2: Creating the Root CA VM in XCP-ng / Xen Orchestra
1. **Template:** Select a minimal cloud template (e.g., `Debian 12` or `Ubuntu Noble 24.04`).
2. **CPUs / Memory:** 1 vCPU, 1024 MB RAM (workload is near zero).
3. **Disks:** 8–10 GB virtual disk.
4. **Networking:**
   - **Do NOT attach any virtual network interface (VIF)**, or attach to an internal non-routed dummy network (`Host-internal management network`).
5. **Cloud-init Configuration:**
   - **Custom config (XO):** Paste the contents of `provisioning/cloud-init/root-ca/user-data`.
   - **Or CD-ROM (Manual):** Attach `root-ca-cidata.iso` to the virtual CD-ROM drive.
6. **Boot & Verify:**
   - Power on the VM.
   - Open the **Xen Orchestra (v6) Console tab**.
   - Cloud-init will automatically configure the system and install `step-cli`.
   - Log in as **`stepadmin`** using the initial temporary password in `user-data` (`chpasswd.list`, default: `kjX:bu4pM^y*VLL3ylyLr:T0`).
   - The first-login ceremony will generate a permanent complex passphrase:
     - Store it in an encrypted vault or password manager.
     - Type `captured` or `got it`.
     - Re-type or paste the passphrase to verify capture.
   - The host is now ready for `/usr/local/bin/init-root-ca.sh`.

---

### Step 3: Creating the Intermediate CA VM in XCP-ng / Xen Orchestra
1. **Template:** Same minimal cloud template (Debian 12 or Ubuntu 24.04).
2. **CPUs / Memory:** 1–2 vCPUs, 2048 MB RAM.
3. **Disks:** 10–15 GB virtual disk.
4. **Networking:**
   - Attach 1 VIF connected to your internal server network.
   - Note the MAC address and set a static DHCP reservation in your router/DNS for:
     `ica.dc.paradigm-works.com` -> `[Assigned IP]`
5. **Cloud-init Configuration:**
   - **Custom config (XO):** Paste the contents of `provisioning/cloud-init/intermediate-ca/user-data`.
   - **Or CD-ROM (Manual):** Attach `intermediate-ca-cidata.iso`.
6. **Boot & Verify:**
   - Power on the VM.
   - Monitor console until cloud-init finishes.
   - Log in via Console or SSH as **`stepadmin`** using the temporary password in `user-data` (`chpasswd.list`, default: `kjX:bu4pM^y*VLL3ylyLr:T0`).
   - Complete the first-login password ceremony (store generated password, enter `captured` or `got it`, and verify).

---

## 3. Alternative: Running Root CA on TrueNAS (VM)

If hosting the Root CA on a TrueNAS storage appliance:
1. Under **Virtualization > Add VM**:
   - Guest Operating System: `Linux`.
   - Boot method: `UEFI`.
   - vCPUs: 1, Memory: 1024 MiB.
   - Disk: Zvol 8 GiB.
2. **Network Interface:**
   - Choose **None** or delete the NIC from the VM device list.
3. **CD-ROM Devices:**
   - Device 1: Base OS cloud image or standard Debian netinst.
   - Device 2: `root-ca-cidata.iso` (Cloud-init datasource).
4. **State Management:**
   - Once the Root CA is initialized and the intermediate CSR is signed, power the VM off.
   - Mark the VM description: `COLD STORAGE - ROOT CA - DO NOT START WITHOUT CEREMONY`.

---

## 4. Alternative: Running Root CA on WSL2 / Physical Flash Drive

If you prefer keeping the Root CA completely air-gapped on physical media:
1. Store the Root CA directory on an encrypted USB flash drive (BitLocker, LUKS, or VeraCrypt).
2. When a signing ceremony is required:
   - Mount the USB drive in Windows 11 / WSL2.
   - Install `step-cli` in WSL2:
     ```bash
     curl -fsSL https://packages.smallstep.com/smallstep.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/smallstep.gpg
     echo "deb [signed-by=/etc/apt/trusted.gpg.d/smallstep.gpg] https://packages.smallstep.com/debian-security/ stable main" | sudo tee /etc/apt/sources.list.d/smallstep.list
     sudo apt update && sudo apt install step-cli magic-wormhole
     ```
   - Run `init-root-ca.sh` and `sign-intermediate.sh` targeting the mounted USB path (`STEPPATH=/mnt/d/step-ca`).
   - Unmount and physically disconnect the USB drive when done.

---

## 5. End-to-End Ceremony Execution Walkthrough

```
[ Intermediate VM ]                          [ Root CA Host ]
       |                                             |
1. Run request-intermediate-csr.sh                   |
   -> Generates intermediate_ca_key                  |
   -> Generates intermediate.csr                     |
       |                                             |
2. wormhole send intermediate.csr                    |
   (Code: 7-galaxy-meteor) ------------------------> 3. wormhole receive 7-galaxy-meteor
                                                     |
                                                     4. Run sign-intermediate.sh
                                                        -> Enters Root Passphrase
                                                        -> Generates intermediate_ca.crt
                                                     |
6. wormhole receive 3-comet-orbit <----------------- 5. wormhole send intermediate_ca.crt
                                                        wormhole send root_ca.crt
       |                                             |
7. Run bootstrap-intermediate.sh                     8. Power off Root CA VM
   -> Sets ca.json & permissions                        (Detach virtual cable)
   -> Starts step-ca.service
       |
[ ica.dc.paradigm-works.com ONLINE ]
```
