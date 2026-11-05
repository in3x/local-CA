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
./provisioning/scripts/new-site.sh <site-id> [domain] [organization]

# Example:
./provisioning/scripts/new-site.sh pw-dc dc.paradigm-works.com "Paradigm Works"
```
This copies `conf/site.env.example` and `conf/inventory.yaml.example` into `site-conf/pw-dc/` and substitutes your site parameters.

### Option B: Zed Agent Skill (Suspenders)
If using the Zed editor agent, run the skill:
```
/init-site
```
The agent will query you for the site parameters (site ID, organization name, domain, network mode) and write the customized files directly.

*Note:* `site-conf/` is git-ignored, ensuring private hostnames and infrastructure details remain strictly local.

---

## Quick-Start: Build and Ceremony Flow

### 1. Build Cloud-Init ISOs
```bash
cd provisioning/scripts
./build-cidata-iso.sh root-ca /path/to/iso-sr/root-ca-cidata.iso
./build-cidata-iso.sh intermediate-ca /path/to/iso-sr/intermediate-ca-cidata.iso
```

### 2. Boot VMs & Execute Signing Ceremony
1. **Boot Root CA VM** with `root-ca-cidata.iso` attached (no network interface). Run:
   ```bash
   /usr/local/bin/init-root-ca.sh
   ```
2. **Boot Intermediate CA VM** with `intermediate-ca-cidata.iso` attached (connected to internal network). Run:
   ```bash
   /usr/local/bin/request-intermediate-csr.sh
   ```
3. **Transfer CSR to Root CA** using `wormhole send` or console paste.
4. **Sign CSR on Root CA**:
   ```bash
   /usr/local/bin/sign-intermediate-csr.sh /root/ceremonies/intermediate.csr
   ```
5. **Transfer signed certs back to Intermediate CA** (`intermediate_ca.crt` and `root_ca.crt`).
6. **Start Intermediate CA**:
   ```bash
   /usr/local/bin/bootstrap-intermediate.sh
   ```
7. **Shut down Root CA VM** and disconnect its virtual interface.
