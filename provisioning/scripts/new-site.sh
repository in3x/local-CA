#!/usr/bin/env bash
set -euo pipefail

# Scaffolds a new site configuration directory from the conf/ templates,
# generates a unique initial temporary bootstrap password with proof-of-capture ceremony,
# and renders customized cloud-init manifests for Xen Orchestra / hypervisor deployment.
# Usage: ./new-site.sh <site-id> [domain] [organization]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONF_DIR="${REPO_ROOT}/conf"
SITE_CONF_DIR="${REPO_ROOT}/site-conf"
WORD_LIST="${REPO_ROOT}/provisioning/wordlists/eff-large-words.txt"

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

# 1. Generate unique initial temporary bootstrap password with 4 words + 7 chunked digits
PASSPHRASE_WORDS=4
PASSPHRASE_DIGITS=7

if [ -f "${WORD_LIST}" ] && command -v shuf &>/dev/null; then
  WORDS=$(shuf -n "${PASSPHRASE_WORDS}" "${WORD_LIST}" | tr '\n' '-' | sed 's/-$//')
  RAW_DIGITS=$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c "${PASSPHRASE_DIGITS}")
  FORMATTED_DIGITS="${RAW_DIGITS:0:3}-${RAW_DIGITS:3:4}"
  INIT_TEMP_PW="${WORDS}-${FORMATTED_DIGITS}"
else
  INIT_TEMP_PW=$(LC_ALL=C tr -dc 'A-Za-z0-9!#$%*+,-.:=?@^_' </dev/urandom | head -c 26)
fi

# 2. Interactive Proof-of-Capture Ceremony
while true; do
  echo ""
  echo "========================================================================"
  echo " SITE SETUP: INITIAL TEMPORARY BOOTSTRAP PASSWORD CEREMONY"
  echo "========================================================================"
  echo ""
  echo " A unique initial temporary password has been generated for site '${SITE_ID}':"
  echo ""
  echo "   -->   ${INIT_TEMP_PW}   <--"
  echo ""
  echo " INSTRUCTIONS:"
  echo " 1. Copy and store this password in an encrypted vault or password manager."
  echo "    (You will need it to log in the very first time as 'stepadmin'.)"
  echo " 2. Type 'captured' or 'got it' when you have safely saved it."
  echo "========================================================================"
  echo ""
  read -r -p "Confirmation: " confirm_input

  shopt -s nocasematch
  if [[ "${confirm_input}" == "captured" || "${confirm_input}" == "got it" ]]; then
    shopt -u nocasematch
    echo ""
    echo "Proof of capture required:"
    echo "Please re-type or paste the initial temporary password to verify:"
    read -r -s -p "Verify Password: " verify_input
    echo ""

    if [ "${verify_input}" == "${INIT_TEMP_PW}" ]; then
      echo ""
      echo "[OK] Initial temporary password verified."
      break
    else
      echo ""
      echo "ERROR: Password does not match! Press Enter to try again."
      read -r
    fi
  else
    shopt -u nocasematch
    echo ""
    echo "You must enter 'captured' or 'got it' to proceed. Press Enter to retry."
    read -r
  fi
done

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
"${SCRIPT_DIR}/render-cloud-init.sh" "${SITE_ID}"

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
