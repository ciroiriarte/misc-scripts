
#!/usr/bin/env bash

# Script Name: openstack-domain-resource-summary.sh
# Description: Accurate summary of OpenStack resources per domain with per-project breakdown.
# Requirements:
#   - openstack CLI configured (admin or domain admin scope)
#   - jq installed
#
# Usage:
#   ./openstack_domain_resource_summary.sh <domain_name>
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Version: 0.1
#
# Changelog:
#   - 2025-12-24: v0.1 - initial release
#
set -euo pipefail

DOMAIN_NAME="${1:-}"
if [[ -z "$DOMAIN_NAME" ]]; then
  echo "Usage: $0 <domain_name>"
  exit 1
fi

# Check dependencies
command -v openstack >/dev/null 2>&1 || { echo "ERROR: 'openstack' CLI not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: 'jq' not found"; exit 1; }

echo "Fetching projects for domain: $DOMAIN_NAME ..."
# Get projects (ID, Name)
PROJECTS_JSON=$(openstack project list --domain "$DOMAIN_NAME" -f json)
PROJECT_COUNT=$(echo "$PROJECTS_JSON" | jq 'length')
if [[ "$PROJECT_COUNT" -eq 0 ]]; then
  echo "No projects found in domain $DOMAIN_NAME"
  exit 0
fi

# Flavor cache (map flavor_id -> {vcpus, ram})
declare -A FLAVOR_VCPUS
declare -A FLAVOR_RAM

get_flavor_info() {
  local flavor_id="$1"
  if [[ -z "${FLAVOR_VCPUS[$flavor_id]:-}" ]]; then
    # Query flavor details and cache
    local fjson
    fjson=$(openstack flavor show "$flavor_id" -f json 2>/dev/null || true)
    if [[ -z "$fjson" ]]; then
      # If flavor show fails (deleted flavor), try by name or set zeros
      FLAVOR_VCPUS["$flavor_id"]=0
      FLAVOR_RAM["$flavor_id"]=0
      return
    fi
    local vcpus ram
    vcpus=$(echo "$fjson" | jq '.vcpus // 0')
    ram=$(echo "$fjson" | jq '.ram // 0') # MB
    # Cache values
    FLAVOR_VCPUS["$flavor_id"]="$vcpus"
    FLAVOR_RAM["$flavor_id"]="$ram"
  fi
}

sum_project_compute() {
  local project_id="$1"
  # List server IDs *in that project*
  local servers_json server_ids
  servers_json=$(openstack server list --project "$project_id" -f json)
  local instance_count
  instance_count=$(echo "$servers_json" | jq 'length')
  local total_vcpus=0
  local total_ram=0

  if [[ "$instance_count" -gt 0 ]]; then
    # Extract IDs
    server_ids=($(echo "$servers_json" | jq -r '.[].ID'))
    for sid in "${server_ids[@]}"; do
      # Get server details to read flavor (ID; not the display string)
      local sjson flavor_id
      sjson=$(openstack server show "$sid" -f json)
      # Flavor may be shown as ID or Name depending on cloud; try both fields.
      # Many clouds expose "flavor" and "flavor_id" keys; normalize:
      flavor_id=$(echo "$sjson" | jq -r '.flavor | .id? // .ID? // .id // .FlavorID? // empty')
      if [[ -z "$flavor_id" || "$flavor_id" == "null" ]]; then
        # Fallback: Nova sometimes returns flavor name only; try "flavor.original_name"
        flavor_id=$(echo "$sjson" | jq -r '.flavor | .original_name? // empty')
      fi

      if [[ -z "$flavor_id" || "$flavor_id" == "null" ]]; then
        # As a last resort, attempt to parse the flavor name and query by name
        flavor_id=$(echo "$sjson" | jq -r '.Flavor? // .flavor? // empty')
      fi

      if [[ -z "$flavor_id" || "$flavor_id" == "null" ]]; then
        # Could not determine flavor, skip adding resources for this VM
        continue
      fi

      # Query flavor info and cache (works for both ID or name)
      get_flavor_info "$flavor_id"

      local vcpus="${FLAVOR_VCPUS[$flavor_id]:-0}"
      local ram="${FLAVOR_RAM[$flavor_id]:-0}"
      total_vcpus=$((total_vcpus + vcpus))
      total_ram=$((total_ram + ram))
    done
  fi

  echo "${instance_count},${total_vcpus},${total_ram}"
}

sum_project_volumes() {
  local project_id="$1"
  local vjson
  vjson=$(openstack volume list --project "$project_id" -f json)
  local vcount vsum
  vcount=$(echo "$vjson" | jq 'length')
  # Size in GB
  vsum=$(echo "$vjson" | jq '[.[].Size] | add // 0')
  echo "${vcount},${vsum}"
}

echo ""
echo "Breakdown per project:"
echo "------------------------------------------------------------"
printf "%-30s %-10s %-10s %-10s %-10s %-12s\n" "Project" "Instances" "vCPUs" "RAM(MB)" "Volumes" "VolSize(GB)"
echo "------------------------------------------------------------"

TOTAL_INSTANCES=0
TOTAL_VCPUS=0
TOTAL_RAM=0
TOTAL_VOLUMES=0
TOTAL_VOLUME_SIZE=0

# Iterate projects
mapfile -t PROJECT_IDS < <(echo "$PROJECTS_JSON" | jq -r '.[].ID')
mapfile -t PROJECT_NAMES < <(echo "$PROJECTS_JSON" | jq -r '.[].Name')

for idx in "${!PROJECT_IDS[@]}"; do
  PROJECT_ID="${PROJECT_IDS[$idx]}"
  PROJECT_NAME="${PROJECT_NAMES[$idx]}"

  IFS=',' read -r INSTANCES VCPUS RAM <<< "$(sum_project_compute "$PROJECT_ID")"
  IFS=',' read -r VOLS VSIZE <<< "$(sum_project_volumes "$PROJECT_ID")"

  printf "%-30s %-10s %-10s %-10s %-10s %-12s\n" "$PROJECT_NAME" "$INSTANCES" "$VCPUS" "$RAM" "$VOLS" "$VSIZE"

  TOTAL_INSTANCES=$((TOTAL_INSTANCES + INSTANCES))
  TOTAL_VCPUS=$((TOTAL_VCPUS + VCPUS))
  TOTAL_RAM=$((TOTAL_RAM + RAM))
  TOTAL_VOLUMES=$((TOTAL_VOLUMES + VOLS))
  TOTAL_VOLUME_SIZE=$((TOTAL_VOLUME_SIZE + VSIZE))
done

echo "------------------------------------------------------------"
echo "Domain Totals:"
printf "%-30s %-10s %-10s %-10s %-10s %-12s\n" "TOTAL" "$TOTAL_INSTANCES" "$TOTAL_VCPUS" "$TOTAL_RAM" "$TOTAL_VOLUMES" "$TOTAL_VOLUME_SIZE"
echo "============================================================"
