#!/usr/bin/env bash
set -euo pipefail

# Deploys a VM on XCP-ng via Xen Orchestra using xo-cli with Cloud-Init injection.
# Usage:
#   ./admin/ca-vm-deploy.sh [site-name] --list                         # Tests connection & lists templates, SRs, networks
#   ./admin/ca-vm-deploy.sh [site-name]                                # Deploys prototype 'test-console-auth'
#   ./admin/ca-vm-deploy.sh [site-name] <vm-name> [path-to-user-data]  # Deploys custom VM with specified user-data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SITE_CONF_DIR="${REPO_ROOT}/site-conf"
DEFAULT_PROTOTYPE_USERDATA="${REPO_ROOT}/prototypes/dynamic-console-login/user-data"

# Load shared dev-bootstrap library (strictly require it; no fallback code)
DEV_BOOTSTRAP_LIB="${HOME}/.local/lib/dev-bootstrap"
if [[ ! -f "$DEV_BOOTSTRAP_LIB/lib-common.sh" ]]; then
  echo "[-] Error: Shared platform library not found at $DEV_BOOTSTRAP_LIB" >&2
  echo "    Please run the host bootstrap to install it:" >&2
  echo "      bash ~/Projects/zed-standards/admin/host-bootstrap.sh --lib-only" >&2
  exit 1
fi
source "$DEV_BOOTSTRAP_LIB/lib-common.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "========================================================================"
  echo " Xen Orchestra VM Deployer (xo-cli)"
  echo "========================================================================"
  echo "Usage:"
  echo "  $0 [site-name] --list                          # Discover templates, SRs & networks"
  echo "  $0 [site-name]                                 # Deploy prototype 'test-console-auth'"
  echo "  $0 [site-name] <vm-name> [path-to-user-data]   # Deploy custom VM"
  echo "========================================================================"
  exit 0
fi

# Verify prerequisites
if ! command -v xo-cli &>/dev/null; then
  echo "[-] Error: 'xo-cli' is required. Please install it with:" >&2
  echo "      npm install -g xo-cli" >&2
  exit 1
fi

# Deterministic site selection (CLI argument or interactive menu)
ACTION=""
SITE_ARG=""
if [[ "${1:-}" == "--list" || "${1:-}" == "--test" ]]; then
  ACTION="--list"
  SITE_ARG=""
else
  SITE_ARG="${1:-}"
  ACTION="${2:-}"
fi

SITE_NAME="$(resolve_site "${SITE_ARG}" "${SITE_CONF_DIR}")"
SITE_DIR="${SITE_CONF_DIR}/${SITE_NAME}"

# Check for site-specific xo.env
XO_ENV="${SITE_DIR}/xo.env"
if [ ! -f "${XO_ENV}" ]; then
  echo "ERROR: Missing Xen Orchestra configuration for site '${SITE_NAME}':"
  echo "  Expected file: ${XO_ENV}"
  echo ""
  echo "To configure, copy the template and edit your XO URL and token:"
  echo "  cp conf/xo.env.example ${XO_ENV}"
  echo "  (Generate token in XO web UI: Settings > Users > [Your User] > API Tokens)"
  exit 1
fi

# Source site-specific xo.env
# shellcheck source=/dev/null
source "${XO_ENV}"

XO_URL="${XO_URL:-}"
XO_TOKEN="${XO_TOKEN:-}"
XO_TEMPLATE="${XO_TEMPLATE:-}"
XO_SR="${XO_SR:-}"
XO_NETWORK="${XO_NETWORK:-}"
XO_VCPUS="${XO_VCPUS:-1}"
XO_MEMORY_MB="${XO_MEMORY_MB:-1024}"

# Helper to build xo-cli URL with credentials
build_xo_url() {
  local url="${1%/}"
  local token="$2"
  if [[ "$url" =~ ^(https?://)(.*)$ ]]; then
    local proto="${BASH_REMATCH[1]}"
    local host="${BASH_REMATCH[2]}"
    if [[ "$host" == *"@"* ]]; then
      echo "${proto}${host}"
    else
      echo "${proto}${token}@${host}"
    fi
  else
    echo "https://${token}@${url}"
  fi
}

xo_exec() {
  if [[ -n "${XO_TOKEN}" && "${XO_TOKEN}" != "your-api-token-here" && -n "${XO_URL}" ]]; then
    local full_url
    full_url="$(build_xo_url "${XO_URL}" "${XO_TOKEN}")"
    xo-cli --allowUnauthorized --url "${full_url}" "$@"
  else
    xo-cli --allowUnauthorized "$@"
  fi
}

# Helper to resolve template name to template ID
resolve_template_id() {
  local tpl="$1"
  if [[ "$tpl" =~ ^[a-f0-9-]+$ ]]; then
    echo "$tpl"
    return 0
  fi
  local resolved
  resolved=$(xo_exec list-objects --name_label --id type=VM-template | \
    python3 -c "import sys, json; tpl='$tpl'; [print(o['id']) for o in json.load(sys.stdin) if o.get('name_label') == tpl][:1]" 2>/dev/null || echo "")
  if [[ -n "$resolved" ]]; then
    echo "$resolved"
  else
    echo "$tpl"
  fi
}

# Handle --list / --test mode
if [ "${ACTION}" = "--list" ] || [ "${ACTION}" = "--test" ]; then
  echo "Connecting to Xen Orchestra for site '${SITE_NAME}'..."
  echo ""
  echo "=== Cloud & VM Templates ==="
  xo_exec list-objects --name_label --id type=VM-template | \
    python3 -c "import sys, json; [print(f' - {o.get(\"name_label\", \"unnamed\")} (ID: {o.get(\"id\", \"\")})') for o in json.load(sys.stdin)]" 2>/dev/null || \
    xo_exec list-objects --name_label --id type=VM-template
  echo ""
  echo "=== Storage Repositories (SRs) ==="
  xo_exec list-objects --name_label --id type=SR | \
    python3 -c "import sys, json; [print(f' - {o.get(\"name_label\", \"unnamed\")} (ID: {o.get(\"id\", \"\")})') for o in json.load(sys.stdin)]" 2>/dev/null || \
    xo_exec list-objects --name_label --id type=SR
  echo ""
  echo "=== Networks ==="
  xo_exec list-objects --name_label --id type=network | \
    python3 -c "import sys, json; [print(f' - {o.get(\"name_label\", \"unnamed\")} (ID: {o.get(\"id\", \"\")})') for o in json.load(sys.stdin)]" 2>/dev/null || \
    xo_exec list-objects --name_label --id type=network
  echo ""
  echo "=== Pools ==="
  xo_exec list-objects --name_label --id type=pool | \
    python3 -c "import sys, json; [print(f' - {o.get(\"name_label\", \"unnamed\")} (ID: {o.get(\"id\", \"\")})') for o in json.load(sys.stdin)]" 2>/dev/null || \
    xo_exec list-objects --name_label --id type=pool
  echo ""
  echo "To set defaults for this site, edit: ${XO_ENV}"
  exit 0
fi

# Resolve deployment arguments (Default to prototype)
VM_NAME="${ACTION:-test-console-auth}"
USERDATA_PATH="${3:-${DEFAULT_PROTOTYPE_USERDATA}}"
VCPUS="${4:-${XO_VCPUS}}"
MEMORY_MB="${5:-${XO_MEMORY_MB}}"
MEMORY_BYTES=$((MEMORY_MB * 1024 * 1024))

if [ ! -f "${USERDATA_PATH}" ]; then
  echo "ERROR: User-data file not found: ${USERDATA_PATH}"
  exit 1
fi

if [ -z "${XO_TEMPLATE}" ]; then
  echo "ERROR: XO_TEMPLATE is not set in ${XO_ENV}."
  echo "Run '$0 ${SITE_NAME} --list' to see available template names and set XO_TEMPLATE."
  exit 1
fi

echo "========================================================================"
echo " Deploying VM to XCP-ng via Xen Orchestra (xo-cli)"
echo " Site Profile:  ${SITE_NAME} (${XO_ENV})"
echo " Xen Orchestra: ${XO_URL:-default}"
echo " VM Name:       ${VM_NAME}"
echo " Template:      ${XO_TEMPLATE}"
echo " vCPUs:         ${VCPUS}"
echo " Memory:        ${MEMORY_MB} MB"
echo " User-Data:     ${USERDATA_PATH}"
echo "========================================================================"

TEMPLATE_ID="$(resolve_template_id "${XO_TEMPLATE}")"
echo "Resolved template ID: ${TEMPLATE_ID}"

CLOUD_CONFIG="$(cat "${USERDATA_PATH}")"

echo "Sending VM creation request to Xen Orchestra via xo-cli..."
DEPLOY_ARGS=(
  "template=${TEMPLATE_ID}"
  "name_label=${VM_NAME}"
  "cloudConfig=${CLOUD_CONFIG}"
  "bootAfterCreate=true"
)
[[ -n "${VCPUS}" ]] && DEPLOY_ARGS+=("vCPUs=${VCPUS}")
[[ -n "${MEMORY_BYTES}" ]] && DEPLOY_ARGS+=("memory=${MEMORY_BYTES}")
[[ -n "${XO_SR}" ]] && DEPLOY_ARGS+=("SR=${XO_SR}")
[[ -n "${XO_NETWORK}" ]] && DEPLOY_ARGS+=("network=${XO_NETWORK}")

DEPLOY_OUTPUT="$(xo_exec vm.create "${DEPLOY_ARGS[@]}")"

if [ $? -eq 0 ] && [ -n "${DEPLOY_OUTPUT}" ]; then
  echo ""
  echo "========================================================================"
  echo " [OK] VM '${VM_NAME}' successfully deployed via xo-cli!"
  echo " Result: ${DEPLOY_OUTPUT}"
  echo " Status: Booting..."
  echo ""
  echo " Next steps:"
  echo " 1. Open Xen Orchestra web UI and switch to '${VM_NAME}' > Console tab."
  echo " 2. Wait ~20-30s for the initial temporary password banner to appear."
  echo " 3. Log in as 'stepadmin' and test the permanent passphrase ceremony."
  echo "========================================================================"
else
  echo ""
  echo "ERROR: Failed to create VM via xo-cli."
  echo "Output from xo-cli:"
  echo "${DEPLOY_OUTPUT}"
  exit 1
fi
