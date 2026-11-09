#!/usr/bin/env bash
set -euo pipefail

# Standalone Root CA Initialization Script
# Can be run directly on a dedicated Root CA VM, or inside WSL2 / local workstation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load shared dev-bootstrap library
DEV_BOOTSTRAP_LIB="${HOME}/.local/lib/dev-bootstrap"
if [[ ! -f "$DEV_BOOTSTRAP_LIB/lib-secret.sh" ]]; then
  echo "[-] Error: Shared platform library not found at $DEV_BOOTSTRAP_LIB" >&2
  echo "    Please run the host bootstrap to install it:" >&2
  echo "      bash ~/Projects/zed-standards/admin/host-bootstrap.sh --lib-only" >&2
  exit 1
fi
source "$DEV_BOOTSTRAP_LIB/lib-secret.sh"

STEPPATH="${STEPPATH:-/etc/step-ca}"
CERTS_DIR="${STEPPATH}/certs"
SECRETS_DIR="${STEPPATH}/secrets"

echo "========================================================="
echo " Offline Root CA Initialization"
echo " Target directory: ${STEPPATH}"
echo "========================================================="

mkdir -p "${CERTS_DIR}" "${SECRETS_DIR}"
chmod 0700 "${STEPPATH}" "${SECRETS_DIR}"

if [ -f "${CERTS_DIR}/root_ca.crt" ]; then
  echo "ERROR: Root CA already exists at ${CERTS_DIR}/root_ca.crt"
  exit 1
fi

WORD_LIST="${WORD_LIST:-${REPO_ROOT}/provisioning/wordlists/eff-large-words.txt}"
SUGGESTED_PW="$(generate_diceware_passphrase "${PASSPHRASE_WORDS:-4}" "${PASSPHRASE_DIGITS:-7}" "${WORD_LIST}")"
proof_of_capture_ceremony "${SUGGESTED_PW}" "Master Root Passphrase"

TEMP_PW_FILE=$(mktemp)
echo -n "${SUGGESTED_PW}" > "${TEMP_PW_FILE}"
chmod 0600 "${TEMP_PW_FILE}"

step certificate create "Paradigm Works Root CA" \
  "${CERTS_DIR}/root_ca.crt" \
  "${SECRETS_DIR}/root_ca_key" \
  --profile root-ca \
  --kty EC \
  --curve P-256 \
  --not-after 175200h \
  --password-file "${TEMP_PW_FILE}"

shred -u "${TEMP_PW_FILE}" 2>/dev/null || rm -f "${TEMP_PW_FILE}"

chmod 0644 "${CERTS_DIR}/root_ca.crt"
chmod 0600 "${SECRETS_DIR}/root_ca_key"

echo ""
echo "[OK] Root CA successfully generated:"
echo " Certificate: ${CERTS_DIR}/root_ca.crt"
echo " Private Key: ${SECRETS_DIR}/root_ca_key"
echo ""
step certificate inspect "${CERTS_DIR}/root_ca.crt" --short
