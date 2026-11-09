#!/usr/bin/env bash
set -euo pipefail

# Generates a NoCloud cidata ISO for testing or XCP-ng deployment.
# Usage: ./admin/ca-iso-build.sh [root-ca | intermediate-ca] [output-path]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT_DIR="${SCRIPT_DIR}/../provisioning/cloud-init"

# Load shared dev-bootstrap library (strictly require it; no fallback code)
DEV_BOOTSTRAP_LIB="${HOME}/.local/lib/dev-bootstrap"
if [[ ! -f "$DEV_BOOTSTRAP_LIB/lib-common.sh" ]]; then
  echo "[-] Error: Shared platform library not found at $DEV_BOOTSTRAP_LIB" >&2
  echo "    Please run the host bootstrap to install it:" >&2
  echo "      bash ~/Projects/zed-standards/admin/host-bootstrap.sh --lib-only" >&2
  exit 1
fi
source "$DEV_BOOTSTRAP_LIB/lib-common.sh"

TARGET="${1:-}"
OUTPUT_PATH="${2:-}"

if [[ "${TARGET}" == "-h" || "${TARGET}" == "--help" ]]; then
  echo "Usage: $0 [root-ca|intermediate-ca] [output.iso]"
  exit 0
fi

if [[ -z "${TARGET}" ]]; then
  echo "Select target CA to build NoCloud ISO for:"
  echo "  1) root-ca"
  echo "  2) intermediate-ca"
  read -rp "Selection [1-2]: " choice
  case "$choice" in
    1) TARGET="root-ca" ;;
    2) TARGET="intermediate-ca" ;;
    *)
      echo "[-] Invalid selection." >&2
      exit 1
      ;;
  esac
fi

if [ ! -d "${CLOUD_INIT_DIR}/${TARGET}" ]; then
  echo "[-] Error: Target directory '${CLOUD_INIT_DIR}/${TARGET}' not found." >&2
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

build_nocloud_iso "${SOURCE_DIR}/user-data" "${SOURCE_DIR}/meta-data" "${OUTPUT_PATH}"

echo "[OK] ISO created: ${OUTPUT_PATH}"
echo "Attach this ISO as a CD-ROM labeled 'cidata' to your VM before first boot."
