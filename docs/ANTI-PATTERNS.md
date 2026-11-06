# Architecture & Security Anti-Patterns

This document records architectural, operational, and cryptographic choices that were evaluated and **explicitly rejected**, along with the reasons and failure modes that led to their rejection.

---

## Anti-Pattern 1: Cloning the Root CA VM to Create the Intermediate CA

### The Rejected Proposal
Creating the Root CA VM, configuring it, running initial certificates, and then cloning the VM disk to serve as the Intermediate CA VM.

### Why It Was Rejected
1. **Private Key Contamination (Catastrophic Security Risk):**
   - The Root CA private key (`root_ca_key`) would exist on the cloned disk image of the online Intermediate CA.
   - Deleting the file inside the guest OS merely removes the inode reference. The raw key bytes remain intact in unallocated blocks, swap space, file system journal logs, and any hypervisor snapshot differentials.
   - Any remote code execution (RCE) vulnerability or local privilege escalation on the online Intermediate CA allows an attacker to dump unallocated disk space or `/dev/mem` and recover the Root CA private key, compromising the entire network's trust root permanently.
2. **OS Identity Collisions:**
   - Cloning duplicates `/etc/machine-id`, systemd D-Bus machine IDs, OpenSSH host keys, network interface MAC rules (`/etc/udev/rules.d/70-persistent-net.rules`), and Step-CA local database UUIDs.
   - Fixing these collisions requires invasive sanitization scripts that frequently miss residual state.

### The Approved Alternative
Both Root and Intermediate VMs are deployed as **independent, pristine instances** from a generic, unconfigured OS base template. The Intermediate generates its own private key locally; only a Certificate Signing Request (CSR) travels between the two tiers.

---

## Anti-Pattern 2: Storing the Root CA Passphrase in Disk Files

### The Rejected Proposal
Creating a `root-password.txt` file inside the Root CA VM or embedding the passphrase in an initialization shell script for fully automated unassisted re-signing.

### Why It Was Rejected
- An offline Root CA provides security only if the signing operation requires conscious human intervention (ceremony).
- Storing the passphrase on disk means anyone with temporary hypervisor access, backup access, or physical drive access can mount the VDI/qcow2 image offline and sign fraudulent intermediate certificates without knowledge of any credentials.

### The Approved Alternative
The Root CA passphrase must never touch persistent storage. It is stored in an encrypted vault or password manager and entered interactively by an administrator at the console during signing operations.

---

## Anti-Pattern 3: Issuing Long-Lived ACME Certificates (90 Days / 1 Year)

### The Rejected Proposal
Configuring the Step-CA ACME provisioner with standard Let's Encrypt-style 90-day lifespans or 1-year lifespans to minimize renewal traffic.

### Why It Was Rejected
- Smallstep community edition does not maintain automated OCSP responders, and maintaining CRL distribution points across internal, segregated, and IoT subnets is notoriously error-prone.
- When an ACME service host is compromised, a 90-day certificate remains valid and usable by an adversary for up to 3 months without any feasible mechanism for local clients to verify revocation.

### The Approved Alternative
ACME certificates are strictly capped at **24 hours**. Clients (Traefik, Caddy, Certbot, etc.) renew automatically every 8–12 hours. If a key is compromised, the maximum attack window is 24 hours without requiring any revocation infrastructure.

---

## Anti-Pattern 4: Rebuilding Intermediate CAs by Restoring Full Hypervisor VM Backups

### The Rejected Proposal
Taking daily snapshots of the Intermediate CA VM and restoring that snapshot in the event of an OS failure, corruption, or hypervisor migration.

### Why It Was Rejected
- Restoring an old Intermediate CA snapshot risks restoring stale `bbolt` database states, creating serial number reuse or clock-skew anomalies with previously issued ACME certificates.
- It discourages testing disaster recovery and encourages configuration drift inside the VM over time.

### The Approved Alternative
Treat the Intermediate CA as **stateless and disposable infrastructure**. The declarative definitions (inventory YAML, templates, cloud-init) are version-controlled in Git. A new Intermediate CA VM can be minted from scratch in minutes, and client devices automatically adapt on their next renewal cycle.

---

## Anti-Pattern 5: Keeping Root CA Connected to a Production VLAN

### The Rejected Proposal
Leaving the Root CA VM running continuously with a network interface, protected only by local Linux firewall rules (`iptables` / `nftables`).

### Why It Was Rejected
- Zero-day vulnerabilities in the hypervisor network stack, Linux kernel IP stack, or background system services (systemd, NTP, DHCP clients) expose the root node to the network.
- Lateral movement during a network-wide incident could reach the Root CA while administrators are unaware.

### The Approved Alternative
The Root CA VM has **no persistent virtual network interface attached** (or remains in a detached `dummy` bridge) and is kept in a **powered-down state** 99.9% of the time.

---

## Anti-Pattern 6: Managing or Rotating a Persistent Default Bootstrap Password

### The Rejected Proposal
Creating a persistent "site default password" rotation policy or vault entry to maintain a reusable default bootstrap password in case an Intermediate CA VM ever needs to be rebuilt or regenerated.

### Why It Was Rejected
- **Transitory Lifecycle:** The bootstrap temporary password exists for only a single brief window: the few seconds between the VM's first boot and the administrator's initial login.
- **Immediate Invalidation:** The first-login security ceremony forcibly overrides the temporary password with a newly generated, verified permanent passphrase before granting shell access.
- **Natural Roll on Rebuild:** When an Intermediate CA VM is destroyed and rebuilt from scratch, a brand-new unique temporary bootstrap password and fresh certificate signing keys are minted dynamically. There is zero operational need or security benefit in maintaining, tracking, or rotating a persistent default password.

### The Approved Alternative
Generate a unique, single-use bootstrap password dynamically per site configuration at scaffold time, enforce the "capture and echo back" verification ceremony during site setup, and allow it to be permanently rolled on first boot.
