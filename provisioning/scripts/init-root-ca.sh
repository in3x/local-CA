#!/usr/bin/env bash
set -euo pipefail

# Standalone Root CA Initialization Script
# Can be run directly on a dedicated Root CA VM, or inside WSL2 / local workstation.

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

echo "Creating Root CA certificate and private key..."
echo "You will be prompted to enter a strong passphrase."
echo "CRITICAL: Store this passphrase in an encrypted vault (e.g. Standard Notes)."
echo ""

step certificate create "Paradigm Works Root CA" \
  "${CERTS_DIR}/root_ca.crt" \
  "${SECRETS_DIR}/root_ca_key" \
  --profile root-ca \
  --kty EC \
  --curve P-256 \
  --not-after 175200h

chmod 0644 "${CERTS_DIR}/root_ca.crt"
chmod 0600 "${SECRETS_DIR}/root_ca_key"

echo ""
echo "[OK] Root CA successfully generated:"
echo " Certificate: ${CERTS_DIR}/root_ca.crt"
echo " Private Key: ${SECRETS_DIR}/root_ca_key"
echo ""
step certificate inspect "${CERTS_DIR}/root_ca.crt" --short
