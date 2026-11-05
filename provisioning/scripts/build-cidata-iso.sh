#!/usr/bin/env bash
set -euo pipefail

# Generates a NoCloud cidata ISO for testing or XCP-ng deployment.
# Usage: ./build-cidata-iso.sh <root-ca | intermediate-ca> [output-path]

TARGET="${1:-}"
OUTPUT_PATH="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT_DIR="${SCRIPT_DIR}/../cloud-init"

if [ -z "${TARGET}" ] || [ ! -d "${CLOUD_INIT_DIR}/${TARGET}" ]; then
  echo "Usage: $0 <root-ca|intermediate-ca> [output.iso]"
  echo "Available targets:"
  ls -1 "${CLOUD_INIT_DIR}"
  exit 1
fi

SOURCE_DIR="${CLOUD_INIT_DIR}/${TARGET}"
if [ -z "${OUTPUT_PATH}" ]; then
  OUTPUT_PATH="${SCRIPT_DIR}/../../build/${TARGET}-cidata.iso"
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

echo "Building NoCloud ISO for target: ${TARGET}"
echo "Source: ${SOURCE_DIR}"
echo "Output: ${OUTPUT_PATH}"

# Check for ISO generator tool
if command -v genisoimage &>/dev/null; then
  ISO_CMD="genisoimage -output ${OUTPUT_PATH} -volid cidata -rational-rock -translation-table"
elif command -v mkisofs &>/dev/null; then
  ISO_CMD="mkisofs -output ${OUTPUT_PATH} -volid cidata -rational-rock -translation-table"
elif command -v xorrisofs &>/dev/null; then
  ISO_CMD="xorrisofs -output ${OUTPUT_PATH} -volid cidata -rational-rock"
else
  echo "ERROR: Neither genisoimage, mkisofs, nor xorriso is installed."
  echo "Install with: apt-get install -y genisoimage"
  exit 1
fi

${ISO_CMD} -J "${SOURCE_DIR}/user-data" "${SOURCE_DIR}/meta-data"

echo "[OK] ISO created: ${OUTPUT_PATH}"
echo "Attach this ISO as a CD-ROM labeled 'cidata' to your VM before first boot."
