#!/usr/bin/env bash
set -euo pipefail

# Scaffolds a new site configuration directory from the conf/ templates,
# generates a unique initial temporary bootstrap password with proof-of-capture ceremony,
# and renders customized cloud-init manifests for Xen Orchestra / hypervisor deployment.
# Usage: ./new-site.sh <site-id> [domain] [organization]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONF_DIR="${REPO_ROOT}/conf"
SITE_CONF_DIR="${REPO_ROOT}/site-conf"
WORD_LIST="${REPO_ROOT}/provisioning/wordlists/eff-large-words.txt"

# Load shared dev-bootstrap library
DEV_BOOTSTRAP_LIB="${HOME}/.local/lib/dev-bootstrap"
if [[ ! -f "$DEV_BOOTSTRAP_LIB/lib-secret.sh" ]]; then
  echo "[-] Error: Shared platform library not found at $DEV_BOOTSTRAP_LIB" >&2
  echo "    Please run the host bootstrap to install it:" >&2
  echo "      bash ~/Projects/zed-standards/admin/host-bootstrap.sh --lib-only" >&2
  exit 1
fi
source "$DEV_BOOTSTRAP_LIB/lib-secret.sh"

SITE_ID="${1:-}"
DOMAIN="${2:-}"
ORG="${3:-}"

if [ -z "${SITE_ID}" ]; then
  echo "========================================================="
  echo " New Site Configuration Scaffolding"
  echo "========================================================="
  echo "Usage: $0 <site-id> [domain] [organization]"
  echo ""
  echo "Examples:"
  echo "  $0 lab-dc"
  echo "  $0 lab-dc lab.example.com \"Lab Network\""
  echo ""
  exit 1
fi

TARGET_DIR="${SITE_CONF_DIR}/${SITE_ID}"

if [ -d "${TARGET_DIR}" ]; then
  echo "ERROR: Site directory already exists at: ${TARGET_DIR}"
  echo "Choose a different site ID or edit the existing files directly."
  exit 1
fi

echo "========================================================="
echo " Scaffolding Site Profile: ${SITE_ID}"
echo "========================================================="

# 1. Generate unique initial temporary bootstrap password & run ceremony
INIT_TEMP_PW="$(generate_diceware_passphrase 4 7 "${WORD_LIST}")"
proof_of_capture_ceremony "${INIT_TEMP_PW}" "Site '${SITE_ID}' Initial Temporary Password"

mkdir -p "${TARGET_DIR}/generated"

# 3. Create site.env from template
if [ -f "${CONF_DIR}/site.env.example" ]; then
  cp "${CONF_DIR}/site.env.example" "${TARGET_DIR}/site.env"
  
  sed -i "s/^SITE_ID=.*/SITE_ID=\"${SITE_ID}\"/" "${TARGET_DIR}/site.env"
  sed -i "s|^INITIAL_TEMP_PASSWORD=.*|INITIAL_TEMP_PASSWORD=\"${INIT_TEMP_PW}\"|" "${TARGET_DIR}/site.env"
  
  if [ -n "${DOMAIN}" ]; then
    sed -i "s/^INTERMEDIATE_FQDN=.*/INTERMEDIATE_FQDN=\"ica.${DOMAIN}\"/" "${TARGET_DIR}/site.env"
  fi
  
  if [ -n "${ORG}" ]; then
    sed -i "s/^ORGANIZATION=.*/ORGANIZATION=\"${ORG}\"/" "${TARGET_DIR}/site.env"
    sed -i "s/^ROOT_CA_NAME=.*/ROOT_CA_NAME=\"${ORG} Root CA\"/" "${TARGET_DIR}/site.env"
    sed -i "s/^INTERMEDIATE_CA_NAME=.*/INTERMEDIATE_CA_NAME=\"${ORG} Intermediate CA\"/" "${TARGET_DIR}/site.env"
  fi
  
  echo "[OK] Initialized: ${TARGET_DIR}/site.env"
else
  echo "WARNING: ${CONF_DIR}/site.env.example not found."
fi

# 4. Copy inventory.yaml template
if [ -f "${CONF_DIR}/inventory.yaml.example" ]; then
  cp "${CONF_DIR}/inventory.yaml.example" "${TARGET_DIR}/inventory.yaml"
  echo "[OK] Initialized: ${TARGET_DIR}/inventory.yaml"
fi

# 5. Render customized cloud-init manifests for this site
"${SCRIPT_DIR}/ca-manifest-render.sh" "${SITE_ID}"

# 6. Source final site.env to display summary
# shellcheck source=/dev/null
source "${TARGET_DIR}/site.env"

echo ""
echo "========================================================================"
echo " Site '${SITE_ID}' Scaffolding Complete!"
echo " Location: site-conf/${SITE_ID}/"
echo "========================================================================"
echo ""
echo " CRITICAL PARAMETERS TO VERIFY:"
echo " 1. INTERMEDIATE FQDN: ${INTERMEDIATE_FQDN}"
echo "    -> MUST be configured in your local DNS to point to Intermediate CA VM!"
echo " 2. ORGANIZATION:      ${ORGANIZATION}"
echo " 3. INITIAL PASSWORD:  ${INIT_TEMP_PW}"
echo "    -> Single-use bootstrap credential for 'stepadmin'."
echo " 4. PASSPHRASE POLICY: ${PASSPHRASE_WORDS} words + ${PASSPHRASE_DIGITS} digits (~75 bits entropy)"
echo ""
echo " READY-TO-PASTE CLOUD-INIT MANIFESTS:"
echo " - Root CA:         site-conf/${SITE_ID}/generated/root-user-data.yaml"
echo " - Intermediate CA: site-conf/${SITE_ID}/generated/intermediate-user-data.yaml"
echo ""
echo " Paste these directly into Xen Orchestra's 'Custom config' box."
echo " Note: site-conf/ is git-ignored, keeping your private hostnames safe."
echo "========================================================================"
