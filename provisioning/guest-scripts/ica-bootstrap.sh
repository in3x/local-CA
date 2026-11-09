#!/usr/bin/env bash
set -euo pipefail

# Assembles the Step-CA configuration, configures provisioners, and starts the service.
# Run on the Intermediate CA host after receiving intermediate_ca.crt and root_ca.crt.

STEPPATH="${STEPPATH:-/etc/step-ca}"
CONFIG_DIR="${STEPPATH}/config"
CERTS_DIR="${STEPPATH}/certs"
SECRETS_DIR="${STEPPATH}/secrets"
TEMPLATES_DIR="${STEPPATH}/templates"
CEREMONY_DIR="${CEREMONY_DIR:-/root/ceremonies}"

echo "========================================================="
echo " Bootstrapping Intermediate CA (ica.dc.paradigm-works.com)"
echo "========================================================="

# 1. Verify certificates
if [ ! -f "${CEREMONY_DIR}/intermediate_ca.crt" ] || [ ! -f "${CEREMONY_DIR}/root_ca.crt" ]; then
  echo "ERROR: Missing ${CEREMONY_DIR}/intermediate_ca.crt or ${CEREMONY_DIR}/root_ca.crt"
  echo "Transfer both files from the Root CA to ${CEREMONY_DIR} before running this script."
  exit 1
fi

mkdir -p "${CONFIG_DIR}" "${CERTS_DIR}" "${SECRETS_DIR}" "${TEMPLATES_DIR}" /var/lib/step-ca/db /var/lib/step-ca/pool
cp "${CEREMONY_DIR}/intermediate_ca.crt" "${CERTS_DIR}/intermediate_ca.crt"
cp "${CEREMONY_DIR}/root_ca.crt" "${CERTS_DIR}/root_ca.crt"

# 2. Check intermediate key and password
if [ ! -f "${SECRETS_DIR}/intermediate_ca_key" ] || [ ! -f "${SECRETS_DIR}/password.txt" ]; then
  echo "ERROR: Missing ${SECRETS_DIR}/intermediate_ca_key or password.txt"
  exit 1
fi

# 3. Verify root fingerprint
ROOT_FINGERPRINT=$(step certificate fingerprint "${CERTS_DIR}/root_ca.crt")
echo "Root CA Fingerprint: ${ROOT_FINGERPRINT}"

# 4. Generate Admin JWK provisioner key if missing
if [ ! -f "${SECRETS_DIR}/admin_jwk_key" ]; then
  echo "Generating Admin JWK provisioner key..."
  step crypto jwk create "${SECRETS_DIR}/admin_jwk_pub.json" "${SECRETS_DIR}/admin_jwk_key" \
    --kty EC \
    --curve P-256 \
    --use sig \
    --password-file "${SECRETS_DIR}/password.txt"
  chmod 0600 "${SECRETS_DIR}/admin_jwk_key" "${SECRETS_DIR}/admin_jwk_pub.json"
fi

# 5. Assemble ca.json
ADMIN_JWK=$(cat "${SECRETS_DIR}/admin_jwk_pub.json")

cat <<EOF > "${CONFIG_DIR}/ca.json"
{
  "root": "${CERTS_DIR}/root_ca.crt",
  "federate": [],
  "crt": "${CERTS_DIR}/intermediate_ca.crt",
  "key": "${SECRETS_DIR}/intermediate_ca_key",
  "address": ":443",
  "dnsNames": [
    "ica.dc.paradigm-works.com"
  ],
  "logger": {
    "format": "text"
  },
  "db": {
    "type": "bbolt",
    "dataSource": "/var/lib/step-ca/db"
  },
  "authority": {
    "provisioners": [
      {
        "type": "ACME",
        "name": "acme",
        "claims": {
          "minTLSCertDuration": "1h",
          "maxTLSCertDuration": "24h",
          "defaultTLSCertDuration": "24h"
        },
        "options": {
          "x509": {
            "templateFile": "${TEMPLATES_DIR}/x509-leaf.tpl"
          }
        }
      },
      {
        "type": "JWK",
        "name": "admin",
        "key": ${ADMIN_JWK},
        "encryptedKey": $(cat "${SECRETS_DIR}/admin_jwk_key"),
        "claims": {
          "minTLSCertDuration": "1h",
          "maxTLSCertDuration": "8760h",
          "defaultTLSCertDuration": "8760h"
        },
        "options": {
          "x509": {
            "templateFile": "${TEMPLATES_DIR}/x509-leaf.tpl"
          }
        }
      }
    ]
  },
  "tls": {
    "cipherSuites": [
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305"
    ],
    "minVersion": 1.2,
    "maxVersion": 1.3
  }
}
EOF

# 6. Apply permissions
if id "step" &>/dev/null; then
  chown -R step:step "${STEPPATH}" /var/lib/step-ca
fi
chmod 0750 "${STEPPATH}" "${CONFIG_DIR}" "${CERTS_DIR}" "${SECRETS_DIR}" "${TEMPLATES_DIR}"
chmod 0644 "${CERTS_DIR}"/*.crt "${CONFIG_DIR}/ca.json"
chmod 0600 "${SECRETS_DIR}"/*

# 7. Start systemd service
if command -v systemctl &>/dev/null; then
  systemctl daemon-reload
  systemctl enable step-ca
  systemctl restart step-ca
  echo ""
  echo "[OK] step-ca service started."
  systemctl status step-ca --no-pager
fi

echo ""
echo "Bootstrap complete."
echo "Intermediate CA is listening on port 443."
echo "ACME Directory: https://ica.dc.paradigm-works.com/acme/acme/directory"
