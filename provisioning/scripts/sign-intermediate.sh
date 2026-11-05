#!/usr/bin/env bash
set -euo pipefail

# Signs an Intermediate CA Certificate Signing Request (CSR) using the Root CA.
# Run on the Root CA host (VM or WSL2).

STEPPATH="${STEPPATH:-/etc/step-ca}"
ROOT_CERT="${STEPPATH}/certs/root_ca.crt"
ROOT_KEY="${STEPPATH}/secrets/root_ca_key"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <path-to-intermediate.csr> [validity-hours]"
  echo "Example: $0 /root/ceremonies/intermediate.csr 26280h"
  exit 1
fi

CSR_FILE="$1"
VALIDITY="${2:-26280h}" # Default 3 years (26280 hours)
OUTPUT_CERT="${CSR_FILE%.csr}.crt"

if [ ! -f "${ROOT_CERT}" ] || [ ! -f "${ROOT_KEY}" ]; then
  echo "ERROR: Root CA files not found at ${ROOT_CERT} and ${ROOT_KEY}"
  exit 1
fi

if [ ! -f "${CSR_FILE}" ]; then
  echo "ERROR: CSR file not found: ${CSR_FILE}"
  exit 1
fi

echo "Signing Intermediate CA CSR..."
echo "  CSR:      ${CSR_FILE}"
echo "  Validity: ${VALIDITY}"
echo "You will be prompted for the Root CA passphrase."
echo ""

step certificate sign "${CSR_FILE}" "${ROOT_CERT}" "${ROOT_KEY}" \
  --profile intermediate-ca \
  --not-after "${VALIDITY}" \
  --out "${OUTPUT_CERT}"

echo ""
echo "[OK] Signed Intermediate CA certificate created at: ${OUTPUT_CERT}"
echo ""
step certificate inspect "${OUTPUT_CERT}" --short
