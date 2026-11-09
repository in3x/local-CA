#!/usr/bin/env bash
set -euo pipefail

# Load shared dev-bootstrap library
DEV_BOOTSTRAP_LIB="${HOME}/.local/lib/dev-bootstrap"
if [[ ! -f "$DEV_BOOTSTRAP_LIB/lib-site.sh" ]]; then
  echo "[-] Error: Shared platform library not found at $DEV_BOOTSTRAP_LIB" >&2
  echo "    Please run the host bootstrap to install it:" >&2
  echo "      bash ~/Projects/zed-standards/admin/host-bootstrap.sh --lib-only" >&2
  exit 1
fi
source "$DEV_BOOTSTRAP_LIB/lib-site.sh"

# Deploys a VM on XCP-ng via the Xen Orchestra REST API with Cloud-Init injection.
# Usage:
#   ./deploy-xo-vm.sh <site-name> --list                           # Tests connection & lists templates, SRs, networks
#   ./deploy-xo-vm.sh <site-name>                                  # Deploys prototype 'test-console-auth'
#   ./deploy-xo-vm.sh <site-name> <vm-name> [path-to-user-data]    # Deploys custom VM with specified user-data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SITE_CONF_DIR="${REPO_ROOT}/site-conf"
DEFAULT_PROTOTYPE_USERDATA="${REPO_ROOT}/prototypes/dynamic-console-login/user-data"

list_sites() {
  echo "Available sites in site-conf/:"
  local found=0
  for dir in "${SITE_CONF_DIR}"/*/; do
    if [ -d "${dir}" ]; then
      local name
      name=$(basename "${dir}")
      if [ -f "${dir}/xo.env" ]; then
        echo "  - ${name} (xo.env configured)"
      else
        echo "  - ${name} (missing xo.env - copy from conf/xo.env.example)"
      fi
      found=1
    fi
  done
  if [ "${found}" -eq 0 ]; then
    echo "  (no sites found - create one with: ./admin/ca-site-new.sh <site-id>)"
  fi
}

# 1. Require <site-name> as first argument
SITE_NAME="${1:-}"

if [ -z "${SITE_NAME}" ] || [ "${SITE_NAME}" = "--help" ] || [ "${SITE_NAME}" = "-h" ]; then
  echo "========================================================================"
  echo " Xen Orchestra VM Deployer"
  echo "========================================================================"
  echo "Usage:"
  echo "  $0 <site-name> --list                          # Discover templates, SRs & networks"
  echo "  $0 <site-name>                                 # Deploy prototype 'test-console-auth'"
  echo "  $0 <site-name> <vm-name> [path-to-user-data]   # Deploy custom VM"
  echo ""
  list_sites
  echo "========================================================================"
  exit 1
fi

SITE_DIR="${SITE_CONF_DIR}/${SITE_NAME}"

if [ ! -d "${SITE_DIR}" ]; then
  echo "ERROR: Site '${SITE_NAME}' not found at: ${SITE_DIR}"
  echo ""
  list_sites
  exit 1
fi

# 2. Check for site-specific xo.env
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

# Verify prerequisites
if ! command -v curl &>/dev/null; then
  echo "ERROR: 'curl' is required. Please install it."
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: 'jq' is required for JSON processing. Please install it."
  exit 1
fi

if [ -z "${XO_URL}" ] || [ -z "${XO_TOKEN}" ] || [ "${XO_TOKEN}" = "your-api-token-here" ]; then
  echo "ERROR: XO_URL or XO_TOKEN is not configured in ${XO_ENV}."
  echo "Please edit ${XO_ENV} with your actual Xen Orchestra URL and API token."
  exit 1
fi

# Normalize XO_URL and XO_TOKEN (strip whitespace, newlines, and trailing slash)
XO_URL=$(echo "${XO_URL}" | tr -d '\r\n ' | sed 's|/*$||')
XO_TOKEN=$(echo "${XO_TOKEN}" | tr -d '\r\n ')

# Helper for curl requests with self-signed cert support (-k)
xo_curl() {
  local method="$1"
  local endpoint="$2"
  shift 2
  curl -k -s -X "${method}" \
    -H "Cookie: authenticationToken=${XO_TOKEN}" \
    -H "Content-Type: application/json" \
    "${XO_URL}/rest/v0/${endpoint}" "$@"
}

# Helper for JSON-RPC 2.0 requests to /api/
xo_rpc() {
  local method="$1"
  local params_json="$2"
  local payload
  payload=$(jq -n --arg method "${method}" --argjson params "${params_json}" \
    '{jsonrpc: "2.0", method: $method, params: $params, id: 1}')

  curl -k -s -X POST \
    -H "Cookie: authenticationToken=${XO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${XO_URL}/api/"
}

# Helper to safely query and display XO collections
safe_fetch_collection() {
  local endpoint="$1"
  local label="$2"
  local resp
  resp=$(xo_curl GET "${endpoint}" 2>/dev/null || echo "")
  
  if echo "${resp}" | jq -e 'type == "array"' &>/dev/null; then
    echo "=== ${label} ==="
    local count
    count=$(echo "${resp}" | jq 'length')
    if [ "${count}" -eq 0 ]; then
      echo "  (none found)"
      echo ""
      return
    fi

    local is_string_array
    is_string_array=$(echo "${resp}" | jq -r '.[0] | if type == "string" then "true" else "false" end')
    if [ "${is_string_array}" = "true" ]; then
      for item in $(echo "${resp}" | jq -r '.[]' | head -n 35); do
        local rel_path="${item#/rest/v0/}"
        local obj
        obj=$(xo_curl GET "${rel_path}" 2>/dev/null || echo "")
        if echo "${obj}" | jq -e 'type == "object"' &>/dev/null; then
          local name id extra is_tpl
          name=$(echo "${obj}" | jq -r '.name_label // .name // "unnamed"')
          id=$(echo "${obj}" | jq -r '.id // .uuid // ""')
          extra=$(echo "${obj}" | jq -r 'if .type then " [" + .type + "]" else "" end')
          is_tpl=$(echo "${obj}" | jq -r '.is_a_template // false')
          echo " - ${name}${extra} (ID: ${id})"
        else
          echo " - ${item}"
        fi
      done
    else
      echo "${resp}" | jq -r '.[] | " - " + (.name_label // .name // .id // "item") + " (ID: " + (.id // "") + ")"'
    fi
    echo ""
  fi
}

# Helper to query templates
safe_fetch_templates() {
  echo "=== Cloud & VM Templates ==="
  local resp
  resp=$(xo_curl GET "vm-templates" 2>/dev/null || echo "")
  if ! echo "${resp}" | jq -e 'type == "array" and length > 0' &>/dev/null; then
    resp=$(xo_curl GET "vms" 2>/dev/null || echo "")
  fi

  if echo "${resp}" | jq -e 'type == "array"' &>/dev/null; then
    local count=0
    for item in $(echo "${resp}" | jq -r '.[]' | head -n 60); do
      local rel_path="${item#/rest/v0/}"
      local obj
      obj=$(xo_curl GET "${rel_path}" 2>/dev/null || echo "")
      if echo "${obj}" | jq -e 'type == "object"' &>/dev/null; then
        local is_tpl name id
        is_tpl=$(echo "${obj}" | jq -r '.is_a_template // false')
        name=$(echo "${obj}" | jq -r '.name_label // .name // ""')
        id=$(echo "${obj}" | jq -r '.id // .uuid // ""')
        if [ "${is_tpl}" = "true" ] || [[ "${name}" =~ (cloud|ubuntu|debian|template|Noble|Bookworm|CentOS|Alpine) ]]; then
          echo " - ${name} (ID: ${id})"
          count=$((count + 1))
        fi
      fi
    done
    if [ "${count}" -eq 0 ]; then
      echo "  (none filtered by template flags; listing all available VM/template objects):"
      for item in $(echo "${resp}" | jq -r '.[]' | head -n 10); do
        local rel_path="${item#/rest/v0/}"
        local obj
        obj=$(xo_curl GET "${rel_path}" 2>/dev/null || echo "")
        local name id
        name=$(echo "${obj}" | jq -r '.name_label // "unnamed"')
        id=$(echo "${obj}" | jq -r '.id // ""')
        echo " - ${name} (ID: ${id})"
      done
    fi
  else
    echo "  (unable to query templates)"
  fi
  echo ""
}

# 3. Handle --list / --test mode
ACTION="${2:-}"

if [ "${ACTION}" = "--list" ] || [ "${ACTION}" = "--test" ]; then
  echo "Connecting to Xen Orchestra for site '${SITE_NAME}' at: ${XO_URL} (ignoring self-signed certs)..."
  
  # Check connection by querying pool or API root
  INDEX=$(xo_curl GET "" 2>/dev/null || echo "")
  if [ -n "${INDEX}" ]; then
    echo "[OK] Connected and authenticated successfully!"
    echo ""
  fi

  safe_fetch_collection "pools" "Pools"
  safe_fetch_templates
  safe_fetch_collection "srs" "Storage Repositories (SRs)"
  safe_fetch_collection "networks" "Networks"

  echo "To set defaults for this site, edit: ${XO_ENV}"
  exit 0
fi

# 4. Resolve deployment arguments (Default to prototype)
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
echo " Deploying VM to XCP-ng via Xen Orchestra"
echo " Site Profile:  ${SITE_NAME} (${XO_ENV})"
echo " Xen Orchestra: ${XO_URL}"
echo " VM Name:       ${VM_NAME}"
echo " Template:      ${XO_TEMPLATE}"
echo " vCPUs:         ${VCPUS}"
echo " Memory:        ${MEMORY_MB} MB"
echo " User-Data:     ${USERDATA_PATH}"
echo "========================================================================"

# Resolve template ID if a name was provided
TEMPLATE_ID="${XO_TEMPLATE}"
if [[ ! "${TEMPLATE_ID}" =~ ^[a-f0-9-]+$ ]] && [[ ! "${TEMPLATE_ID}" =~ ^[a-f0-9-]+-[a-f0-9-]+$ ]]; then
  echo "Resolving template ID for '${XO_TEMPLATE}'..."
  VM_LIST=$(xo_curl GET "vms" 2>/dev/null || echo "")
  RESOLVED_ID=""
  if echo "${VM_LIST}" | jq -e 'type == "array"' &>/dev/null; then
    for item in $(echo "${VM_LIST}" | jq -r '.[]' | head -n 60); do
      rel_path="${item#/rest/v0/}"
      obj=$(xo_curl GET "${rel_path}" 2>/dev/null || echo "")
      name=$(echo "${obj}" | jq -r '.name_label // ""')
      if [ "${name}" = "${XO_TEMPLATE}" ]; then
        RESOLVED_ID=$(echo "${obj}" | jq -r '.id // .uuid // ""')
        break
      fi
    done
  fi
  if [ -n "${RESOLVED_ID}" ]; then
    echo "[OK] Resolved to template ID: ${RESOLVED_ID}"
    TEMPLATE_ID="${RESOLVED_ID}"
  fi
fi

CLOUD_CONFIG=$(cat "${USERDATA_PATH}")

# Construct JSON payload for JSON-RPC vm.create
PAYLOAD=$(jq -n \
  --arg name_label "${VM_NAME}" \
  --arg template "${TEMPLATE_ID}" \
  --arg sr "${XO_SR}" \
  --arg network "${XO_NETWORK}" \
  --argjson vcpus "${VCPUS}" \
  --argjson memory "${MEMORY_BYTES}" \
  --arg cloud_config "${CLOUD_CONFIG}" \
  '{
    name_label: $name_label,
    template: $template,
    vCPUs: $vcpus,
    memory: $memory,
    cloudConfig: $cloud_config,
    bootAfterCreate: true
  }
  + (if $sr != "" then {SR: $sr} else {} end)
  + (if $network != "" then {network: $network} else {} end)
')

echo "Sending VM creation request to Xen Orchestra..."
RESPONSE=$(xo_curl POST "vms" -d "${PAYLOAD}")

# If REST returned a redirect or error, try JSON-RPC
if echo "${RESPONSE}" | grep -qi "redirecting\|Cannot POST"; then
  echo "Trying alternative endpoint (JSON-RPC vm.create)..."
  RPC_RESP=$(xo_rpc "vm.create" "${PAYLOAD}")
  if echo "${RPC_RESP}" | jq -e '.result != null' &>/dev/null; then
    RESPONSE="${RPC_RESP}"
  fi
fi

if echo "${RESPONSE}" | jq -e '.id or .status == "success" or .result != null' &>/dev/null; then
  VM_ID=$(echo "${RESPONSE}" | jq -r '.id // .result // "created"')
  echo ""
  echo "========================================================================"
  echo " [OK] VM '${VM_NAME}' successfully deployed!"
  echo " VM ID:  ${VM_ID}"
  echo " Status: Booting..."
  echo ""
  echo " Next steps:"
  echo " 1. Open Xen Orchestra web UI and switch to '${VM_NAME}' > Console tab."
  echo " 2. Wait ~20-30s for the initial temporary password banner to appear."
  echo " 3. Log in as 'stepadmin' and test the permanent passphrase ceremony."
  echo "========================================================================"
else
  echo ""
  echo "ERROR: Failed to create VM via Xen Orchestra API."
  echo "Response from XO:"
  echo "${RESPONSE}" | jq . 2>/dev/null || echo "${RESPONSE}"
  exit 1
fi
