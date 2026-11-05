#!/usr/bin/env bash
set -euo pipefail

# Scaffolds a new site configuration directory from the conf/ templates.
# Usage: ./new-site.sh <site-id> [domain] [organization]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONF_DIR="${REPO_ROOT}/conf"
SITE_CONF_DIR="${REPO_ROOT}/site-conf"

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

echo "Creating new site configuration for: ${SITE_ID}"
echo "Target directory: ${TARGET_DIR}"

mkdir -p "${TARGET_DIR}/generated"

# 1. Copy site.env template
if [ -f "${CONF_DIR}/site.env.example" ]; then
  cp "${CONF_DIR}/site.env.example" "${TARGET_DIR}/site.env"
  
  # Perform substitutions if arguments were provided
  sed -i "s/^SITE_ID=.*/SITE_ID=\"${SITE_ID}\"/" "${TARGET_DIR}/site.env"
  
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

# 2. Copy inventory.yaml template
if [ -f "${CONF_DIR}/inventory.yaml.example" ]; then
  cp "${CONF_DIR}/inventory.yaml.example" "${TARGET_DIR}/inventory.yaml"
  echo "[OK] Initialized: ${TARGET_DIR}/inventory.yaml"
else
  echo "WARNING: ${CONF_DIR}/inventory.yaml.example not found."
fi

echo ""
echo "========================================================="
echo " Site '${SITE_ID}' scaffolded successfully!"
echo " Location: site-conf/${SITE_ID}/"
echo ""
echo " Next steps:"
echo " 1. Edit site-conf/${SITE_ID}/site.env to verify domain and attributes."
echo " 2. Edit site-conf/${SITE_ID}/inventory.yaml to declare non-ACME devices."
echo " 3. Note: site-conf/ is git-ignored, so your settings stay private."
echo "========================================================="
