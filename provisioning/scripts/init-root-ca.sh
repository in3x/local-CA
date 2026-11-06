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

PASSPHRASE_WORDS="${PASSPHRASE_WORDS:-4}"
PASSPHRASE_DIGITS="${PASSPHRASE_DIGITS:-7}"
WORD_LIST="${WORD_LIST:-/usr/local/share/dict/eff-words.txt}"

[ "${PASSPHRASE_WORDS}" -lt 4 ] 2>/dev/null && PASSPHRASE_WORDS=4
[ "${PASSPHRASE_DIGITS}" -lt 4 ] 2>/dev/null && PASSPHRASE_DIGITS=4

if [ ! -f "${WORD_LIST}" ] && [ -f "${SCRIPT_DIR:-.}/../wordlists/eff-large-words.txt" ]; then
  WORD_LIST="${SCRIPT_DIR:-.}/../wordlists/eff-large-words.txt"
fi

if [ -f "${WORD_LIST}" ] && command -v shuf &>/dev/null; then
  WORDS=$(shuf -n "${PASSPHRASE_WORDS}" "${WORD_LIST}" | tr '\n' '-' | sed 's/-$//')
  RAW_DIGITS=$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c "${PASSPHRASE_DIGITS}")
  if [ "${PASSPHRASE_DIGITS}" -eq 7 ]; then
    FORMATTED_DIGITS="${RAW_DIGITS:0:3}-${RAW_DIGITS:3:4}"
  else
    FORMATTED_DIGITS="${RAW_DIGITS}"
  fi
  SUGGESTED_PW="${WORDS}-${FORMATTED_DIGITS}"
else
  SUGGESTED_PW=$(LC_ALL=C tr -dc 'A-Za-z0-9!#$%*+,-.:=?@^_' </dev/urandom | head -c 26)
fi

while true; do
  echo ""
  echo "========================================================================"
  echo " ROOT CA PRIVATE KEY PASSPHRASE CEREMONY"
  echo "========================================================================"
  echo ""
  echo " A cryptographically secure Master Root Passphrase has been generated:"
  echo ""
  echo "   -->   ${SUGGESTED_PW}   <--"
  echo ""
  echo " INSTRUCTIONS:"
  echo " 1. Copy and store this passphrase in an encrypted vault or password manager."
  echo " 2. (Optional) Write an emergency physical paper copy for cold safe storage."
  echo " 3. Type 'captured' or 'got it' when you have safely saved it."
  echo "========================================================================"
  echo ""
  read -r -p "Confirmation: " confirm_input

  shopt -s nocasematch
  if [[ "${confirm_input}" == "captured" || "${confirm_input}" == "got it" ]]; then
    shopt -u nocasematch
    echo ""
    echo "Proof of capture required:"
    echo "Please re-type or paste the Master Root Passphrase to verify:"
    read -r -s -p "Verify Passphrase: " verify_input
    echo ""

    if [ "${verify_input}" == "${SUGGESTED_PW}" ]; then
      echo ""
      echo "[OK] Master Root Passphrase verified. Creating Root CA..."
      break
    else
      echo ""
      echo "ERROR: Passphrase does not match! Press Enter to try again."
      read -r
    fi
  else
    shopt -u nocasematch
    echo ""
    echo "You must enter 'captured' or 'got it' to proceed. Press Enter to retry."
    read -r
  fi
done

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
