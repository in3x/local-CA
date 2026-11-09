#!/usr/bin/env bash
set -euo pipefail

# Renders customized cloud-init user-data manifests for a specific site.
# Usage: ./admin/ca-manifest-render.sh [site-id]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SITE_CONF_DIR="${REPO_ROOT}/site-conf"
CLOUD_INIT_DIR="${REPO_ROOT}/provisioning/cloud-init"

# Load shared dev-bootstrap library (strictly require it; no fallback code)
DEV_BOOTSTRAP_LIB="${HOME}/.local/lib/dev-bootstrap"
if [[ ! -f "$DEV_BOOTSTRAP_LIB/lib-common.sh" ]]; then
  echo "[-] Error: Shared platform library not found at $DEV_BOOTSTRAP_LIB" >&2
  echo "    Please run the host bootstrap to install it:" >&2
  echo "      bash ~/Projects/zed-standards/admin/host-bootstrap.sh --lib-only" >&2
  exit 1
fi
source "$DEV_BOOTSTRAP_LIB/lib-common.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [site-id]"
  exit 0
fi

SITE_ID="$(resolve_site "${1:-}" "${SITE_CONF_DIR}")"
SITE_DIR="${SITE_CONF_DIR}/${SITE_ID}"
SITE_ENV="${SITE_DIR}/site.env"

if [ ! -f "${SITE_ENV}" ]; then
  echo "ERROR: Missing ${SITE_ENV}"
  exit 1
fi

# Source site variables
# shellcheck source=/dev/null
source "${SITE_ENV}"

OUTPUT_DIR="${SITE_DIR}/generated"
mkdir -p "${OUTPUT_DIR}"

INITIAL_TEMP_PASSWORD="${INITIAL_TEMP_PASSWORD:-kjX:bu4pM^y*VLL3ylyLr:T0}"
PASSPHRASE_WORDS="${PASSPHRASE_WORDS:-4}"
PASSPHRASE_DIGITS="${PASSPHRASE_DIGITS:-7}"
ORGANIZATION="${ORGANIZATION:-Paradigm Works}"
INTERMEDIATE_FQDN="${INTERMEDIATE_FQDN:-ica.dc.paradigm-works.com}"

echo "Rendering customized cloud-init manifests for site: ${SITE_ID}"
echo "  FQDN:            ${INTERMEDIATE_FQDN}"
echo "  Organization:    ${ORGANIZATION}"
echo "  Words / Digits:  ${PASSPHRASE_WORDS} words / ${PASSPHRASE_DIGITS} digits"
echo "  Target dir:      ${OUTPUT_DIR}"

# 1. Render root-ca user-data
ROOT_SRC="${CLOUD_INIT_DIR}/root-ca/user-data"
ROOT_OUT="${OUTPUT_DIR}/root-user-data.yaml"

sed \
  -e "s|^    stepadmin:.*|    stepadmin:${INITIAL_TEMP_PASSWORD}|g" \
  -e "s|PASSPHRASE_WORDS=\"\${PASSPHRASE_WORDS:-4}\"|PASSPHRASE_WORDS=\"\${PASSPHRASE_WORDS:-${PASSPHRASE_WORDS}}\"|g" \
  -e "s|PASSPHRASE_DIGITS=\"\${PASSPHRASE_DIGITS:-7}\"|PASSPHRASE_DIGITS=\"\${PASSPHRASE_DIGITS:-${PASSPHRASE_DIGITS}}\"|g" \
  -e "s|Paradigm Works Root CA|${ORGANIZATION} Root CA|g" \
  "${ROOT_SRC}" > "${ROOT_OUT}"

echo "[OK] Rendered: ${ROOT_OUT}"

# 2. Render intermediate-ca user-data
ICA_SRC="${CLOUD_INIT_DIR}/intermediate-ca/user-data"
ICA_OUT="${OUTPUT_DIR}/intermediate-user-data.yaml"

sed \
  -e "s|^    stepadmin:.*|    stepadmin:${INITIAL_TEMP_PASSWORD}|g" \
  -e "s|PASSPHRASE_WORDS=\"\${PASSPHRASE_WORDS:-4}\"|PASSPHRASE_WORDS=\"\${PASSPHRASE_WORDS:-${PASSPHRASE_WORDS}}\"|g" \
  -e "s|PASSPHRASE_DIGITS=\"\${PASSPHRASE_DIGITS:-7}\"|PASSPHRASE_DIGITS=\"\${PASSPHRASE_DIGITS:-${PASSPHRASE_DIGITS}}\"|g" \
  -e "s|ica\.dc\.paradigm-works\.com|${INTERMEDIATE_FQDN}|g" \
  -e "s|Paradigm Works Intermediate CA|${ORGANIZATION} Intermediate CA|g" \
  -e "s|\"organization\": \"Paradigm Works\"|\"organization\": \"${ORGANIZATION}\"|g" \
  "${ICA_SRC}" > "${ICA_OUT}"

echo "[OK] Rendered: ${ICA_OUT}"
echo ""
echo "These files are ready to paste directly into Xen Orchestra's 'Custom config' box."
