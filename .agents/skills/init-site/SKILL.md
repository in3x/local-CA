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

### 3. Generate Configuration Files
Read `conf/site.env.example` and `conf/inventory.yaml.example` as baselines.

1. Create `site-conf/<SITE_ID>/site.env` substituting:
   - `SITE_ID="<SITE_ID>"`
   - `ORGANIZATION="<ORGANIZATION>"`
   - `ROOT_CA_NAME="<ORGANIZATION> Root CA"`
   - `INTERMEDIATE_CA_NAME="<ORGANIZATION> Intermediate CA"`
   - `INTERMEDIATE_FQDN="<INTERMEDIATE_FQDN>"`
   - `COUNTRY="<COUNTRY>"`
   - Any static IP parameters specified by the user.

2. Create `site-conf/<SITE_ID>/inventory.yaml` initialized with the default template and empty `devices: []` list (or prepopulate any non-ACME devices the user mentioned).

### 4. Provide Next Steps
Inform the user:
- `site-conf/<SITE_ID>/` has been created.
- The directory is protected by `site-conf/.gitignore` and will never be committed to public Git.
- Next, they can declare non-ACME devices in `site-conf/<SITE_ID>/inventory.yaml` or proceed to building the Cloud-Init ISOs using `provisioning/scripts/build-cidata-iso.sh`.
