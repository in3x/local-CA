---
name: init-site
description: Guides the user through creating a customized site configuration for local-CA. Collects site parameters (site ID, organization, domain, intermediate FQDN) and populates site-conf/<site-id>/site.env and inventory.yaml from the conf/ templates.
---

# Initializing a New Site Configuration

Use this skill when the user wants to configure a new site, cluster, or environment (e.g., "set up a new site", "configure my lab", "create site-conf for X").

## Workflow

### 1. Collect Site Parameters
Ask the user for the following parameters if they haven't already provided them:

1. **Site ID (`SITE_ID`):** A short alphanumeric identifier for the site or datacenter (e.g., `pw-dc`, `lab-home`, `prod-east`).
2. **Organization Name (`ORGANIZATION`):** The legal or operational entity name for certificates (e.g., `Paradigm Works`).
3. **Internal Domain (`DOMAIN`):** The internal domain zone (e.g., `dc.paradigm-works.com`).
4. **Intermediate CA FQDN (`INTERMEDIATE_FQDN`):** The hostname for the Intermediate CA (default: `ica.<DOMAIN>`).
5. **Country Code (`COUNTRY`):** Two-letter ISO country code (default: `US`).
6. **Network Mode:** Whether the Intermediate CA will use a static IP (request IP, gateway, DNS) or a DHCP reservation (default: DHCP reservation).

### 2. Check for Existing Site
Check if `site-conf/<SITE_ID>` already exists in the project:
- If it exists, warn the user and confirm whether they want to update it or choose a new ID.
- Do not overwrite without confirmation.

### 3. Initial Temporary Password Ceremony
Before writing the configuration, generate a unique, cryptographically random initial bootstrap password using 4 random words from `provisioning/wordlists/eff-large-words.txt` and a 7-digit chunked number (`XXX-XXXX`):
- Display the generated password clearly:
  ```text
  ========================================================================
   SITE SETUP: INITIAL TEMPORARY BOOTSTRAP PASSWORD CEREMONY
  ========================================================================
   A unique initial temporary password has been generated for site '<SITE_ID>':

     -->   <generated-passphrase-here>   <--

   INSTRUCTIONS:
   1. Copy and store this password in an encrypted vault or password manager.
      (You will need it to log in the very first time as 'stepadmin'.)
   2. Reply with 'captured' or 'got it' when you have safely saved it.
  ========================================================================
  ```
- Require the user to reply with `captured` or `got it`.
- Ask the user to re-type or paste the passphrase to verify proof of capture.
- Only proceed to file generation once the user proves they captured the passphrase.

### 4. Generate Configuration Files & Render Manifests
Read `conf/site.env.example` and `conf/inventory.yaml.example` as baselines.

1. Create `site-conf/<SITE_ID>/site.env` substituting:
   - `SITE_ID="<SITE_ID>"`
   - `INITIAL_TEMP_PASSWORD="<generated-passphrase>"`
   - `ORGANIZATION="<ORGANIZATION>"`
   - `ROOT_CA_NAME="<ORGANIZATION> Root CA"`
   - `INTERMEDIATE_CA_NAME="<ORGANIZATION> Intermediate CA"`
   - `INTERMEDIATE_FQDN="<INTERMEDIATE_FQDN>"`
   - `COUNTRY="<COUNTRY>"`
   - `PASSPHRASE_WORDS="4"`
   - `PASSPHRASE_DIGITS="7"`
   - Any static IP parameters specified by the user.

2. Create `site-conf/<SITE_ID>/inventory.yaml` initialized with the default template and empty `devices: []` list (or prepopulate any non-ACME devices the user mentioned).

3. Run `./provisioning/scripts/render-cloud-init.sh <SITE_ID>` to generate:
   - `site-conf/<SITE_ID>/generated/root-user-data.yaml`
   - `site-conf/<SITE_ID>/generated/intermediate-user-data.yaml`

### 5. Provide Next Steps & Critical Parameter Alerts
Inform the user:
- `site-conf/<SITE_ID>/` has been created and customized.
- Highlight the **Critical Parameters to Verify**:
  1. `INTERMEDIATE_FQDN`: Must be pointed to the Intermediate CA IP in local DNS.
  2. `INITIAL_TEMP_PASSWORD`: Single-use bootstrap password for `stepadmin`.
- Point them to the rendered manifests in `site-conf/<SITE_ID>/generated/` ready to paste into Xen Orchestra's "Custom config" box.
- Remind them that `site-conf/` is git-ignored, ensuring private hostnames and credentials stay local.
