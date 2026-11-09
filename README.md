# local-CA: Two-Tier Private PKI

An automated, two-tier internal Public Key Infrastructure (PKI) built on [Smallstep](https://smallstep.com) (`step-ca` and `step-cli`).

Designed for hypervisors (XCP-ng, TrueNAS, Proxmox, or QEMU/KVM) using decoupled Cloud-Init manifests, short-lived ACME certificates, and batch generation for legacy/non-ACME devices.

---

## Architecture Summary

- **Tier 1: Root CA (`root-ca.dc.paradigm-works.com`)**
  - Offline trust anchor (powered down 99.9% of the time, disconnected vNIC).
  - Lifespan: 10–20 years.
  - Generates self-signed root certificate and signs Intermediate CSRs.
- **Tier 2: Intermediate CA (`ica.dc.paradigm-works.com`)**
  - Online issuing authority on the internal management network.
  - Lifespan: 2–5 years.
  - ACME endpoint with **24-hour** validity for automated renewal (Traefik, Caddy, Certbot).
  - Dedicated Admin/JWK provisioner with **1-year (8760h)** validity for static/non-ACME devices.
  - Zero root private key contamination; CSR signing ceremony executed via [Magic Wormhole](https://magic-wormhole.readthedocs.io/).

---

## Repository Structure

```
├── conf/
│   ├── site.env.example       # Template environment variables for a site/cluster
│   └── inventory.yaml.example # Template non-ACME device declaration inventory
│
├── site-conf/                 # (Git-ignored) Local site configurations
│   ├── .gitignore             # Enforces strict isolation of all site configs
│   └── <site-id>/             # Local site configurations (e.g. pw-dc)
│
├── docs/
│   ├── DESIGN.md              # Topology, certificate profiles, and recovery strategy
│   ├── SECURITY.md            # Threat model, key storage, passphrase policies
│   ├── ANTI-PATTERNS.md       # Explicitly rejected designs and rationales
│   └── HYPERVISOR_GUIDE.md    # XCP-ng, TrueNAS, and WSL2 VM build specifics
│
├── provisioning/
│   ├── cloud-init/
│   │   ├── root-ca/           # user-data & meta-data for Root CA
│   │   └── intermediate-ca/   # user-data & meta-data for Intermediate CA
│   ├── step-ca/
│   │   ├── templates/
│   │   │   └── x509-leaf.tpl  # Baseline Go template for common attributes
│   │   └── ica-config.json.tpl# Reference Step-CA intermediate configuration
│   └── scripts/
│       ├── new-site.sh               # Scaffolds site-conf/<site-id>/ from templates
│       ├── build-cidata-iso.sh       # Builds NoCloud ISOs for VM first-boot
│       ├── init-root-ca.sh           # Offline Root CA generation ceremony
│       ├── request-intermediate.sh   # Intermediate key & CSR generation
│       ├── sign-intermediate.sh      # Root CA signature ceremony
│       └── bootstrap-intermediate.sh # Intermediate service assembler & starter
```

---

## Site Configuration Setup

You can initialize a new site profile (`site-conf/<site-id>/`) using either method:

### Option A: Shell Script (Belt)
```bash
./admin/ca-site-new.sh <site-id> [domain] [organization]

# Example:
./admin/ca-site-new.sh pw-dc dc.paradigm-works.com "Paradigm Works"
```
This copies `conf/site.env.example` and `conf/inventory.yaml.example` into `site-conf/pw-dc/` and substitutes your site parameters.

### Option B: Zed Agent Skill (Suspenders)
If using the Zed editor agent, run the skill:
```
/init-site
```
The agent will query you for the site parameters (site ID, organization name, domain, network mode) and write the customized files directly.

*Note:* `site-conf/` is git-ignored, ensuring private hostnames and infrastructure details remain strictly local. Backup is the responsibility of the local admin. 

---

## Quick-Start: Build and Ceremony Flow

### 1. Provision VMs

#### Method A: Xen Orchestra Native (Recommended - No ISO needed)
1. **Root CA VM:**
   - In Xen Orchestra, create a VM from a cloud template (Debian 12 or Ubuntu 24.04).
   - Resources: 1 vCPU, 1024 MB RAM, 10 GB disk.
   - Network: **No network interface (VIF)**.
   - Cloud-init: Select **Custom config** and paste the contents of [`provisioning/cloud-init/root-ca/user-data`](provisioning/cloud-init/root-ca/user-data).
2. **Intermediate CA VM:**
   - Create a VM from the same cloud template.
   - Resources: 1–2 vCPUs, 2048 MB RAM, 15 GB disk.
   - Network: 1 VIF connected to internal network (`ica.dc.paradigm-works.com`).
   - Cloud-init: Select **Custom config** and paste the contents of [`provisioning/cloud-init/intermediate-ca/user-data`](provisioning/cloud-init/intermediate-ca/user-data).

#### Method B: Generic / Manual Hypervisor (Using NoCloud ISOs)
If your hypervisor does not support direct cloud-init text injection:
```bash
# Scripts organized in admin/ and ceremonies/
./build-cidata-iso.sh root-ca /path/to/iso-sr/root-ca-cidata.iso
./build-cidata-iso.sh intermediate-ca /path/to/iso-sr/intermediate-ca-cidata.iso
```
Attach each generated `.iso` to the respective VM's CD drive before first boot.

---

### 2. VM Credentials & First-Time Login Ceremony

Each VM is pre-configured with a temporary single-use password:
* **Username:** `stepadmin`
* **Temporary Initial Password:** Located in your `user-data` file under `chpasswd.list` (default: `kjX:bu4pM^y*VLL3ylyLr:T0`).

#### First-Time Login Verification
When logging into either the XO console or SSH for the first time:
1. The shell intercepts login and generates a unique, cryptographically random permanent passphrase:
   ```text
   ========================================================================
    FIRST-TIME LOGIN SECURITY CEREMONY: STEPADMIN PASSWORD SETUP
   ========================================================================

    A new cryptographically secure permanent passphrase has been generated (XKCD/Diceware):

      -->   recycling-overpay-duress-proved-371-3197   <--

    INSTRUCTIONS:
    1. Copy and store this password in an encrypted vault or password manager.
    2. Type 'captured' or 'got it' when you have safely saved it.
   ========================================================================
   ```
2. Type `captured` or `got it` once saved in your password manager.
3. You will be prompted to re-enter/paste the permanent passphrase to prove capture.
4. Once verified, the password is permanently applied to `stepadmin` and shell access is unlocked.

---

### 3. Signing Ceremony & Service Activation

1. **Initialize Root CA (Air-Gapped):**
   - In Xen Orchestra (v6) Console for `root-ca`, run:
     ```bash
     /usr/local/bin/init-root-ca.sh
     ```
   - Enter your Root CA passphrase when prompted. **Record it in your encrypted vault or password manager.**

2. **Generate Intermediate CSR:**
   - In the Intermediate CA terminal/console, run:
     ```bash
     /usr/local/bin/request-intermediate-csr.sh
     cat /root/ceremonies/intermediate.csr
     ```
   - Copy the CSR PEM text block.

3. **Transfer and Sign CSR on Root CA:**
   - In the Root CA Console (via XO 6 console paste or after temporarily enabling network access use Magic Wormhole):
     ```bash
     cat << 'EOF' > /root/ceremonies/intermediate.csr
     <paste CSR here>
     EOF
     /usr/local/bin/sign-intermediate-csr.sh /root/ceremonies/intermediate.csr
     ```
   - View the signed cert and root cert:
     ```bash
     cat /root/ceremonies/intermediate.crt
     cat /etc/step-ca/certs/root_ca.crt
     ```

4. **Install Certs & Start Intermediate CA:**
   - On the Intermediate CA, paste both certificates:
     ```bash
     cat << 'EOF' > /root/ceremonies/intermediate_ca.crt
     <paste intermediate.crt here>
     EOF

     cat << 'EOF' > /root/ceremonies/root_ca.crt
     <paste root_ca.crt here>
     EOF
     ```
   - Launch and verify the service:
     ```bash
     /usr/local/bin/bootstrap-intermediate.sh
     ```

5. **Power Down Root CA:**
   - In the Root CA Console, shut down the VM:
     ```bash
     poweroff
     ```
   - Keep the Root CA VM powered off until the next intermediate rotation (in 2–3 years).
