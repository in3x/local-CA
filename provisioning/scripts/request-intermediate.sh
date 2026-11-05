#!/usr/bin/env bash
set -euo pipefail

# Generates the Intermediate CA private key and CSR on the Intermediate CA host.

STEPPATH="${STEPPATH:-/etc/step-ca}"
SECRETS_DIR="${STEPPATH}/secrets"
CEREMONY_DIR="${CEREMONY_DIR:-/root/ceremonies}"

mkdir -p "${SECRETS_DIR}" "${CEREMONY_DIR}"
chmod 0700 "${SECRETS_DIR}" "${CEREMONY_DIR}"

PASSWORD_FILE="${SECRETS_DIR}/password.txt"
KEY_FILE="${SECRETS_DIR}/intermediate_ca_key"
CSR_FILE="${CEREMONY_DIR}/intermediate.csr"

echo "========================================================="
echo " Generating Intermediate CA Key and CSR"
echo " Host: ica.dc.paradigm-works.com"
echo "========================================================="

if [ -f "${KEY_FILE}" ]; then
  echo "WARNING: Key file ${KEY_FILE} already exists."
  read -r -p "Overwrite existing key and CSR? (y/N): " confirm
  if [[ "${confirm}" != [yY] ]]; then
    echo "Aborted."
    exit 0
  fi
fi

if [ ! -f "${PASSWORD_FILE}" ]; then
  echo "Generating random daemon password for Intermediate CA..."
  openssl rand -base64 32 | tr -d '\n' > "${PASSWORD_FILE}"
  chmod 0600 "${PASSWORD_FILE}"
  if id "step" &>/dev/null; then
    chown step:step "${PASSWORD_FILE}"
  fi
  echo "[OK] Generated ${PASSWORD_FILE}"
  echo "IMPORTANT: Record this password in your encrypted password manager."
fi

echo "Creating Intermediate CA CSR and private key..."
step certificate create "Paradigm Works Intermediate CA" \
  "${CSR_FILE}" \
  "${KEY_FILE}" \
  --csr \
  --password-file "${PASSWORD_FILE}" \
  --kty EC \
  --curve P-256

chmod 0600 "${KEY_FILE}"
if id "step" &>/dev/null; then
  chown step:step "${KEY_FILE}"
fi

echo ""
echo "[OK] Intermediate CSR generated at: ${CSR_FILE}"
echo "Next step: Transfer ${CSR_FILE} to the Root CA for signing."
echo "Suggested transfer: wormhole send ${CSR_FILE}"
