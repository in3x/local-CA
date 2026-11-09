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
  PASSPHRASE_WORDS="${PASSPHRASE_WORDS:-4}"
  PASSPHRASE_DIGITS="${PASSPHRASE_DIGITS:-7}"
  WORD_LIST="${WORD_LIST:-/usr/local/share/dict/eff-words.txt}"

  [ "${PASSPHRASE_WORDS}" -lt 4 ] 2>/dev/null && PASSPHRASE_WORDS=4
  [ "${PASSPHRASE_DIGITS}" -lt 4 ] 2>/dev/null && PASSPHRASE_DIGITS=4

  if [ -f "${WORD_LIST}" ] && command -v shuf &>/dev/null; then
    WORDS=$(shuf -n "${PASSPHRASE_WORDS}" "${WORD_LIST}" | tr '\n' '-' | sed 's/-$//')
    RAW_DIGITS=$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c "${PASSPHRASE_DIGITS}")
    if [ "${PASSPHRASE_DIGITS}" -eq 7 ]; then
      FORMATTED_DIGITS="${RAW_DIGITS:0:3}-${RAW_DIGITS:3:4}"
    else
      FORMATTED_DIGITS="${RAW_DIGITS}"
    fi
    DAEMON_PW="${WORDS}-${FORMATTED_DIGITS}"
  else
    DAEMON_PW=$(LC_ALL=C tr -dc 'A-Za-z0-9!#$%*+,-.:=?@^_' </dev/urandom | head -c 26)
  fi

  while true; do
    echo ""
    echo "========================================================================"
    echo " INTERMEDIATE CA DAEMON PASSWORD CEREMONY"
    echo "========================================================================"
    echo ""
    echo " An Intermediate CA private key password has been generated:"
    echo ""
    echo "   -->   ${DAEMON_PW}   <--"
    echo ""
    echo " INSTRUCTIONS:"
    echo " 1. Copy and store this password in an encrypted vault or password manager."
    echo " 2. Type 'captured' or 'got it' when safely preserved."
    echo "========================================================================"
    echo ""
    read -r -p "Confirmation: " confirm_input

    shopt -s nocasematch
    if [[ "${confirm_input}" == "captured" || "${confirm_input}" == "got it" ]]; then
      shopt -u nocasematch
      echo ""
      echo "Proof of capture required:"
      echo "Please re-type or paste the daemon password to verify:"
      read -r -s -p "Verify Password: " verify_input
      echo ""

      if [ "${verify_input}" == "${DAEMON_PW}" ]; then
        echo ""
        echo "[OK] Password verified. Writing daemon credential file..."
        echo -n "${DAEMON_PW}" > "${PASSWORD_FILE}"
        chmod 0600 "${PASSWORD_FILE}"
        if id "step" &>/dev/null; then
          chown step:step "${PASSWORD_FILE}"
        fi
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
