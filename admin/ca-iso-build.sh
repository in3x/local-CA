#!/usr/bin/env bash
set -euo pipefail

# Generates a NoCloud cidata ISO for testing or XCP-ng deployment.
# Usage: ./build-cidata-iso.sh <root-ca | intermediate-ca> [output-path]

TARGET="${1:-}"
OUTPUT_PATH="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT_DIR="${SCRIPT_DIR}/../provisioning/cloud-init"

if [ -z "${TARGET}" ] || [ ! -d "${CLOUD_INIT_DIR}/${TARGET}" ]; then
  echo "Usage: $0 <root-ca|intermediate-ca> [output.iso]"
  echo "Available targets:"
  ls -1 "${CLOUD_INIT_DIR}"
  exit 1
fi

SOURCE_DIR="${CLOUD_INIT_DIR}/${TARGET}"
if [ -z "${OUTPUT_PATH}" ]; then
  OUTPUT_PATH="${SCRIPT_DIR}/../build/${TARGET}-cidata.iso"
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

echo "Building NoCloud ISO for target: ${TARGET}"
echo "Source: ${SOURCE_DIR}"
echo "Output: ${OUTPUT_PATH}"

# Load shared dev-bootstrap library for ISO building
DEV_BOOTSTRAP_LIB="${HOME}/.local/lib/dev-bootstrap"
if [[ ! -f "$DEV_BOOTSTRAP_LIB/lib-cidata.sh" ]]; then
  echo "[-] Error: Shared platform library not found at $DEV_BOOTSTRAP_LIB" >&2
  echo "    Please run the host bootstrap to install it:" >&2
  echo "      bash ~/Projects/zed-standards/admin/host-bootstrap.sh --lib-only" >&2
  exit 1
fi
source "$DEV_BOOTSTRAP_LIB/lib-cidata.sh"

build_nocloud_iso "${SOURCE_DIR}/user-data" "${SOURCE_DIR}/meta-data" "${OUTPUT_PATH}"

echo "[OK] ISO created: ${OUTPUT_PATH}"
echo "Attach this ISO as a CD-ROM labeled 'cidata' to your VM before first boot."
