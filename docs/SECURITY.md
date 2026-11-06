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
  - Generated as a 4- or 5-word XKCD/Diceware passphrase with numeric suffix.
  - Stored inside an encrypted vault or password manager.
  - An emergency physical paper copy stored in a secure physical location (safe or lockbox) alongside any cold storage media.
* **Usage:** Entered interactively at the console terminal only during signing ceremonies.

### 3.2 Intermediate CA Daemon Password
* **Operational Constraint:** Because `step-ca` runs as an unattended background service under `systemd`, it must be able to read its intermediate key decryption password on boot.
* **Storage Location:**
  - Placed at `/etc/step-ca/password.txt` on the Intermediate VM.
  - Strict POSIX file permissions: `chmod 0600`, owned by `step:step` (the unprivileged system user running `step-ca`).
  - Archived in an encrypted vault or password manager for disaster recovery reference.
* **Isolation:** The intermediate password file decrypts **only** the intermediate key. It has zero cryptographic relationship with the root CA.

### 3.3 Passphrase Model, Cognitive Chunking & Security Ceremonies
Administrative logins and cryptographic key generation across both VMs employ an XKCD-style / Diceware passphrase model with cognitive chunking:

* **Wordlist Source:** EFF Large Wordlist (7,776 words, $6^5$ combinations), pre-installed offline at `/usr/local/share/dict/eff-words.txt`. The list is curated for clarity, distinctness, and absence of confusing homophones or ambiguous terms.
* **Cognitive Chunking (Miller's Law):**
  - Human working memory processes information most reliably in small groups ("chunks") of 3 to 4 items.
  - While raw 7-digit strings (e.g. `2347731`) cause cognitive fatigue and transcription errors, chunking the digits in local telephone format (`234-7731`) compresses 7 discrete digits into two familiar phonetic blocks ("two-thirty-four, seventy-seven thirty-one").
  - Combined with 4 dictionary words, the full passphrase has a natural spoken cadence:
    ```
    recycling-overpay-duress-proved-371-3197
    ```
* **Configuration Parameters:**
  - `PASSPHRASE_WORDS`: Number of random words from the EFF Large List (minimum 4, default: `4`).
  - `PASSPHRASE_DIGITS`: Number of trailing random digits (minimum 4, default: `7`). When set to 7, digits automatically format as `XXX-XXXX`.
* **Entropy Analysis:**
  - **4 Words + 7 Chunked Digits (Default):**
    - Word space: $7,776^4 \approx 3.65 \times 10^{15} \approx 51.70\text{ bits}$
    - 7-digit suffix ($10^7 = 10,000,000$ combinations): $\approx 23.25\text{ bits}$
    - Total Entropy: $\approx \mathbf{74.95\text{ bits}}$ ($\approx 3.65 \times 10^{22}$ combinations).
    - Achieves cold-storage grade security equivalent to a 13-character random alphanumeric string, while remaining natural to read, memorize, and transcribe without errors.
  - **4 Words + 4 Digits (Compact):**
    - Word space: $7,776^4 \approx 51.70\text{ bits}$
    - 4-digit suffix ($10^4 = 10,000$ combinations): $\approx 13.29\text{ bits}$
    - Total Entropy: $\approx \mathbf{64.99\text{ bits}}$ ($\approx 3.65 \times 10^{19}$ combinations).
  - **5 Words + 7 Chunked Digits (High-Paranoia Option):**
    - Total Entropy: $\approx \mathbf{87.84\text{ bits}}$ ($\approx 2.84 \times 10^{26}$ combinations).
* **Proof-of-Capture Enforcement:**
  - Used for both initial VM login (`/etc/profile.d/99-first-login-ceremony.sh`), Root CA key generation (`init-root-ca.sh`), and Intermediate CA daemon password generation (`request-intermediate.sh`).
  - Requires the administrator to type `captured` or `got it` after storing the phrase in their password manager.
  - Requires re-typing/pasting the exact passphrase to verify capture before proceeding.
* **Console Resilience:**
  - Eliminates character ambiguity common in hypervisor remote consoles (such as `1`, `l`, `I`, `|`, `0`, `O`, `8`, `B`, and keyboard layout mapping shifts for symbols like `~`, `@`, `#`).
  - Safe and error-resistant for emergency physical paper backup in a secure vault.
* **Enforced Uniform Randomness:**
  - Humans are strictly prevented from choosing weak or predictable words.
  - Scripts draw entropy from `/dev/urandom` and `shuf` to guarantee an unskewed cryptographic distribution.

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
