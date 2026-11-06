# Architecture & Design Specification

## 1. Overview and Goals

This project provides an automated, secure, two-tier Public Key Infrastructure (PKI) designed for local network infrastructure using Smallstep (`step-cli` and `step-ca`).

Key design objectives:
- **Two-tier hierarchy:** Offline Root Certificate Authority (CA) and an online Intermediate Certificate Authority (ICA).
- **Automated certificate provisioning:** ACME protocol support for compatible clients, issuing short-lived certificates (24 hours) to eliminate the need for complex revocation infrastructure (CRLs/OCSP).
- **Static / Non-ACME device support:** Declarative batch generation of longer-lived (1 year / 8760h) certificates using custom x509 templates for legacy hardware and embedded services.
- **Decoupled provisioning:** Decouples cloud-init bootstrap logic from hypervisor orchestration (XCP-ng, TrueNAS, Proxmox, or QEMU/KVM), enabling local testing and rapid disaster recovery.
- **Strict identity separation:** Clean base templates for every VM with zero key contamination between root and intermediate tiers.

---

## 2. Infrastructure Topology

```
                  +-----------------------------------+
                  |           Root CA (VM)            |
                  | - Offline / Powered off           |
                  | - Isolated vNIC (or no vNIC)      |
                  | - Lifetime: 10–20 years           |
                  | - Hosts: root_ca.crt, root_ca_key |
                  +-----------------+-----------------+
                                    |
            Signing Ceremony via Magic Wormhole / Console
                                    v
                  +-----------------------------------+
                  |       Intermediate CA (VM)        |
                  | FQDN: ica.dc.paradigm-works.com   |
                  | - Online, internal network access |
                  | - Port 443 (ACME/mTLS API)        |
                  | - Port 80 (HTTP-01 challenge)     |
                  | - Lifetime: 2–5 years             |
                  | - Hosts: intermediate_ca.crt/key  |
                  +-----------------+-----------------+
                                    |
        +---------------------------+---------------------------+
        |                                                       |
        v                                                       v
+-------------------------------+               +-------------------------------+
|         ACME Clients          |               |       Non-ACME Devices        |
| - Traefik, Caddy, Certbot     |               | - Switches, IPMI, Storage     |
| - Automated renewal (8-12h)   |               | - 1-year certificates         |
| - Validity: 24 hours          |               | - Batch generation script     |
+-------------------------------+               | - Push via SSH/SCP            |
                                                +-------------------------------+
```

---

## 3. Host Roles & Specifications

### 3.1 Root CA
- **Hostname:** `root-ca.dc.paradigm-works.com` (internal reference only)
- **Role:** Trust anchor. Signs the Intermediate CA Certificate Signing Request (CSR).
- **State:** Cold/Offline. VM is powered down when not actively executing a signing ceremony.
- **Hosting Options:**
  - Dedicated stopped VM on TrueNAS/XCP-ng with no active network bridge.
  - Or container/WSL2 run from an air-gapped encrypted USB flash drive.
- **Validity:** 10 to 20 years.
- **Maintenance Policy:** Immutable appliance. No automated OS updates. `xe-guest-utilities` provides hypervisor telemetry during rare boot cycles.

### 3.2 Intermediate CA
- **Hostname:** `ica.dc.paradigm-works.com`
- **Role:** Online issuing authority for internal network endpoints.
- **State:** Continuously running under systemd supervision (`step-ca.service`).
- **Storage/DB:** Local embedded key-value store (`bbolt`), minimal footprint (< 20 MB).
- **Maintenance Policy:** `unattended-upgrades` applies automatic distribution security patches. `xe-guest-utilities` provides XCP-ng agent integration.
- **Ports Exposed:**
  - `443/TCP`: Step-CA ACME directory and REST API.
  - `80/TCP`: HTTP-01 challenge verification.
  - `22/TCP`: Administrative SSH (restricted).
- **Validity:** 2 to 5 years (recommended 3 years).

---

## 4. Certificate Profiles & Lifetimes

| Profile | Target | Maximum Validity | Provisioner Type | Renewal Strategy |
| :--- | :--- | :--- | :--- | :--- |
| **ACME Leaf** | Workloads, web proxies, internal apps | **24 hours** | ACME (`/acme/acme/directory`) | Automated every 8–12h via client |
| **Static Leaf** | Switches, IPMI/iDRAC, NAS, printers | **8760 hours (1 year)** | JWK / Admin (`admin`) | Batch script + push deployment |
| **Intermediate CA** | `ica.dc.paradigm-works.com` | **2 to 5 years** | Root CA manual sign | Re-ceremony before expiration |
| **Root CA** | Internal Trust Anchor | **10 to 20 years** | Self-signed Root | Retained offline |

### 4.1 Rationale for 24-Hour ACME Lifetimes
Smallstep does not support automated real-time revocation checking via online OCSP responders without enterprise plugins, and CRL distribution in air-gapped/internal subnets is brittle. By restricting leaf certificates to 24 hours, compromised certificates expire naturally within a day, drastically reducing the attack window without requiring revocation lists.

### 4.2 x509 Baseline Go Template
Non-ACME certificates use a centralized Step-CA Go template (`x509-leaf.tpl`). This template enforces:
- Standard Organization (`Paradigm Works`) and Country (`US`).
- Default Key Usage (`Digital Signature`, `Key Encipherment`).
- Default Extended Key Usage (`Server Auth`, `Client Auth`).
- Dynamic SAN injection based on the requesting parameters.

---

## 5. Inter-Tier Ceremonies & Transport

### 5.1 Initial Bootstrap Ceremony
1. Intermediate VM boots from clean cloud-init template with Step-CA installed.
2. Intermediate initiates certificate request:
   - Generates its private key (`intermediate_ca_key`).
   - Generates a Certificate Signing Request (`intermediate.csr`).
3. Transport to Root CA:
   - Executed via **Magic Wormhole** (`wormhole send intermediate.csr`) over the network, or copied manually via hypervisor serial/console.
4. Root CA signs the CSR:
   - Invokes `step certificate sign intermediate.csr root_ca.crt root_ca_key --profile intermediate-ca`.
   - Produces `intermediate_ca.crt`.
5. Return Transport:
   - Sends `intermediate_ca.crt` and `root_ca.crt` back to Intermediate VM via Magic Wormhole or console paste.
6. Intermediate installs the certificate chain, verifies permissions, and launches `step-ca.service`.
7. Root CA VM is powered off and network interfaces disabled.

---

## 6. Disaster Recovery & Rebuild Strategy

The Intermediate CA VM is treated as **ephemeral and replaceable**:
- **Zero Restore Dependency:** If the Intermediate VM becomes corrupt or compromised, do not restore from old hypervisor backups.
- **Clean Slate Procedure:**
  1. Spin up a brand new VM using the intermediate cloud-init manifest.
  2. Perform the CSR signing ceremony against the offline Root CA.
  3. Re-run the batch script for non-ACME certificates.
  4. ACME clients will automatically obtain new certificates upon their next renewal cycle (as they already trust the Root CA).
- **Persistent Data to Version Control:**
  - Non-ACME device inventory file (`inventory.yaml`).
  - Baseline x509 templates.
  - Cloud-init configs and provisioning scripts.
  *(None of these files contain private keys or passwords).*
