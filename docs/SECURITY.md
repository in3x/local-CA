# Security Model & Threat Mitigation

## 1. Threat Model

The primary security objectives of this architecture are:
1. **Prevent Root CA Key Compromise:** Ensure the offline root key cannot be accessed via network attacks, unauthorized VM snapshots, or lateral movement from compromised intermediate services.
2. **Contain Intermediate CA Compromise:** Ensure that an attacker gaining root access on the online Intermediate CA cannot pivot to the root trust anchor, and can only forge short-lived (24h) leaf certificates until the Intermediate CA is revoked/rebuilt.
3. **Prevent Private Key Cross-Contamination:** Ensure neither VM contains disk remnants, history entries, or swap memory containing keys belonging to the other tier.

---

## 2. Key Hierarchy & Cryptographic Standards

* **Root CA:**
  * Algorithm: `ECDSA` with curve `P-256` (or `Ed25519`).
  * Self-signed trust anchor.
  * Encrypted at rest using a high-entropy passphrase.
* **Intermediate CA:**
  * Algorithm: `ECDSA` with curve `P-256`.
  * Signed by Root CA as a basic constraint `cA: TRUE`, `pathlen: 0` (cannot mint subordinate CAs).
  * Encrypted at rest using a dedicated local daemon password.
* **Leaf Certificates (ACME & Static):**
  * Algorithm: `ECDSA` `P-256` or `RSA 2048/4096` based on client CSR.
  * Basic constraint: `cA: FALSE`.

---

## 3. Passphrase Management Policy

### 3.1 Root CA Passphrase
* **Strict Prohibition:** Never write or store the Root CA passphrase on disk in plaintext or automated script variables.
* **Storage Location:** 
  - Generated as a 24+ character high-entropy passphrase or Diceware passphrase.
  - Stored inside an encrypted vault (e.g., encrypted page in **Standard Notes**).
  - An emergency physical paper copy stored in a secure physical location (safe or lockbox) alongside any cold storage media.
* **Usage:** Entered interactively at the console terminal only during signing ceremonies.

### 3.2 Intermediate CA Daemon Password
* **Operational Constraint:** Because `step-ca` runs as an unattended background service under `systemd`, it must be able to read its intermediate key decryption password on boot.
* **Storage Location:**
  - Placed at `/etc/step-ca/password.txt` on the Intermediate VM.
  - Strict POSIX file permissions: `chmod 0600`, owned by `step:step` (the unprivileged system user running `step-ca`).
  - Archived in encrypted Standard Notes for disaster recovery reference.
* **Isolation:** The intermediate password file decrypts **only** the intermediate key. It has zero cryptographic relationship with the root CA.

---

## 4. Key Isolation & Transport Security

### 4.1 Air-Gap / Isolation Policy for Root CA
1. **Network Disconnection:** When the Root CA VM is not in active use, its virtual network interface must be detached or assigned to a non-routed dummy network.
2. **Power State:** The VM must remain in `halted` / `shut off` state during normal network operations.
3. **No Ingress Access:** No SSH or remote administrative services run on the Root CA. Interaction occurs strictly over hypervisor VNC/serial console.

### 4.2 CSR & Certificate Exchange: Magic Wormhole
When minting or renewing the Intermediate CA:
* Transferring the CSR and signed certificates using **Magic Wormhole**:
  - Employs SPAKE2 (Password Authenticated Key Exchange) over a short-lived random numeric code (e.g., `4-orbiting-jupiter`).
  - Channel is fully encrypted end-to-end using symmetric keys derived from P-256 elliptic-curve Diffie-Hellman.
  - Relays see only encrypted ciphertext; MITM is prevented by the human-verified short code.
  - Leaves no persistent network endpoints or stored keys on the Root CA.

---

## 5. Trust Distribution

* **Root CA Public Certificate (`root_ca.crt`):**
  - Distributed to client trust stores (workstation OS root stores, web browsers, mobile profiles).
  - Injected into new Linux VMs at build time via `cloud-init` user-data:
    ```yaml
    ca_certs:
      trusted:
        - |
          -----BEGIN CERTIFICATE-----
          <ROOT CA PEM CONTENT>
          -----END CERTIFICATE-----
    ```
* **Intermediate CA Public Chain:**
  - Distributed automatically during TLS handshakes via ACME and leaf bundles (`cert.pem` + `intermediate_ca.crt`).
  - Clients do **not** need the intermediate CA pre-installed in their root trust stores.

---

## 6. Compromise & Revocation Response

If the Intermediate CA host is compromised:
1. Immediately power down and destroy the `ica.dc.paradigm-works.com` VM.
2. Boot the Root CA VM.
3. Generate a new Intermediate key pair and CSR on a fresh VM.
4. Sign the new CSR with Root CA.
5. Boot the new Intermediate CA.
6. Trigger forced renewal on critical services.
7. Any rogue certificates issued by the compromised Intermediate CA expire automatically within 24 hours (ACME) or must be blacklisted in application-level pin configurations.

---

## 7. Patching & Guest Agent Security

* **Root CA (Frozen Appliance):**
  - Receives no automatic updates. Because the VM is air-gapped and powered off, guest vulnerability exposure is non-existent.
  - Retaining a frozen environment avoids unexpected breakage of crypto toolchains or bootloaders.
* **Intermediate CA (Automated Security Updates):**
  - Exposed to internal network traffic (ports 80 and 443).
  - Managed by `unattended-upgrades` to automatically install critical OS and security fixes without manual intervention.
* **Hypervisor Integration (`xe-guest-utilities`):**
  - Installed strictly from the distribution's verified APT repository.
  - Eliminates the need to mount untrusted guest tools ISOs or compile out-of-tree kernel modules.
