#!/bin/sh

# Script Name: memory-usage-report-esxi.sh
# Description: Provides a basic ESXi host memory usage and optimization summary.
#
# Author: Ciro Iriarte <ciro.iriarte+software@gmail.com>
# Created: 2025-09-11
# Version: 1.2
#
# Changelog:
#   - 2025-09-11: v1.0 - Initial version.
#   - 2026-02-17: v1.1 - Renamed to memory-usage-report-esxi.sh.
#                        Added root check, prerequisite check, and help option.
#                        Moved extract_kpi() outside the VM loop.
#                        Fixed host memory percentage to use MiB precision.
#                        Fixed VM_MEM_GB variable reuse in printf.
#   - 2026-02-17: v1.2 - Added --output option for CSV and JSON formats.

# --- Configuration ---
SCRIPT_VERSION="1.2"
OUTPUT_FORMAT="table"

# --- Help ---
show_help() {
    echo "Usage: $0 [-h|--help] [-v|--version] [--output FORMAT]"
    echo ""
    echo "Version: $SCRIPT_VERSION"
    echo ""
    echo "Description:"
    echo " Reports ESXi host and per-VM memory usage including ballooning,"
    echo " swapping, compression, and shared memory metrics."
    echo " Must be run directly on the ESXi host (via SSH or local shell)."
    echo ""
    echo "Options:"
    echo " -h, --help        Display this help message"
    echo " -v, --version     Display version information"
    echo " --output FORMAT   Output format: table (default), csv, or json"
    echo "                   csv: VM table only (ID, name, GB columns)."
    echo "                   json: full report (host_summary, vms, totals)."
}

# --- Argument Parsing ---
while [ $# -gt 0 ]; do
    case "$1" in
        -v|--version)
            echo "$0 $SCRIPT_VERSION"
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --output)
            if [ -z "${2:-}" ]; then
                echo "Error: --output requires an argument (table, csv, or json)." >&2
                exit 1
            fi
            case "$2" in
                table|csv|json)
                    OUTPUT_FORMAT="$2"
                    ;;
                *)
                    echo "Error: Invalid output format '$2'. Choose from table, csv, or json." >&2
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

# --- Validation ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

for CMD in vsish vim-cmd awk grep sed; do
    if ! command -v "$CMD" > /dev/null 2>&1; then
        echo "Error: Required command '$CMD' not found." >&2
        exit 1
    fi
done

# --- Helper: escape backslashes and double quotes for JSON string values ---
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# --- Helper: extract a named numeric KPI from vm.summary quickStats ---
# Depends on $VM_SUMMARY being set in the caller's scope.
extract_kpi() {
    echo "$VM_SUMMARY" | grep -m1 "$1" | awk '{print $NF}' | sed 's/,//' | grep -E '^[0-9]+$' || echo 0
}

# --- Collect Host Memory Stats ---
MEM_STATS=$(vsish -e get /memory/comprehensive)

TOTAL_MEM_KB=$(echo "$MEM_STATS" | grep "Physical memory estimate" | awk -F':' '{print $2}' | awk '{print $1}')
FREE_MEM_KB=$(echo "$MEM_STATS" | grep "Free:" | awk -F':' '{print $2}' | awk '{print $1}')

TOTAL_MEM_MIB=$((TOTAL_MEM_KB / 1024))
FREE_MEM_MIB=$((FREE_MEM_KB / 1024))
HOST_MEM_USED_MIB=$((TOTAL_MEM_MIB - FREE_MEM_MIB))

TOTAL_MEM_GB=$((TOTAL_MEM_MIB / 1024))
HOST_MEM_USED_GB=$((HOST_MEM_USED_MIB / 1024))

if [ "$TOTAL_MEM_MIB" -gt 0 ]; then
    USAGE_PERCENT=$((HOST_MEM_USED_MIB * 100 / TOTAL_MEM_MIB))
else
    USAGE_PERCENT=0
fi

# --- Table-only: Report Header & Host Summary ---
if [ "$OUTPUT_FORMAT" = "table" ]; then
    echo "==================================="
    echo " ESXi Memory Usage Report"
    echo "==================================="
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
    echo ""
    echo "Total System Memory: ${TOTAL_MEM_GB} GB"
    echo "Used by Host: ${HOST_MEM_USED_GB} GB (${USAGE_PERCENT}%)"
    echo ""
fi

# --- JSON: Open document and host_summary ---
if [ "$OUTPUT_FORMAT" = "json" ]; then
    printf '{\n'
    printf '  "host_summary": {\n'
    printf '    "total_gb": %d,\n'     "$TOTAL_MEM_GB"
    printf '    "used_gb": %d,\n'      "$HOST_MEM_USED_GB"
    printf '    "usage_percent": %d\n' "$USAGE_PERCENT"
    printf '  },\n'
    printf '  "vms": [\n'
fi

# --- Collect VM IDs ---
VM_IDS=$(vim-cmd vmsvc/getallvms | awk 'NR>1 {print $1}')

# --- Table/CSV: Section Header ---
if [ "$OUTPUT_FORMAT" = "table" ]; then
    printf "%-5s %-43s %-8s %-8s %-8s %-10s %-8s %-8s %-10s %-10s %-10s %-10s\n" \
        "ID" "VM Name" "RAM(GB)" "Bloon" "Swap" "Compress" "Shared" "Guest" "Host" "Granted" "Private" "Overhead"
    echo "----------------------------------------------------------------------------------------------------------------------------------------------------------"
elif [ "$OUTPUT_FORMAT" = "csv" ]; then
    printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
        "ID" "VM Name" "RAM (GB)" "Balloon (GB)" "Swap (GB)" "Compress (GB)" \
        "Shared (GB)" "Guest (GB)" "Host (GB)" "Granted (GB)" "Private (GB)" "Overhead (GB)"
fi

# --- VM Loop ---
TOTAL_VM_MEM=0
TOTAL_BALLOON=0
TOTAL_SWAP=0
TOTAL_COMPRESS=0
TOTAL_SHARED=0
VM_JSON_COUNT=0

for VMID in $VM_IDS; do
    VM_SUMMARY=$(vim-cmd vmsvc/get.summary "$VMID")

    VM_NAME=$(echo "$VM_SUMMARY" | grep -m1 'name =' | awk -F'"' '{print $2}')
    VM_MEM_MB=$(echo "$VM_SUMMARY" | grep -m1 'memorySizeMB =' | awk -F'= ' '{print $2}' | sed 's/,//')
    VM_MEM_GB=$(( VM_MEM_MB / 1024 ))

    if [ -z "$VM_NAME" ]; then
        continue
    fi

    BALLOON_MB=$(extract_kpi "balloonedMemory")
    SWAP_MB=$(extract_kpi "swappedMemory")
    COMPRESS_MB=$(extract_kpi "compressedMemory")
    SHARED_MB=$(extract_kpi "sharedMemory")
    GUEST_MB=$(extract_kpi "guestMemoryUsage")
    HOST_MB=$(extract_kpi "hostMemoryUsage")
    GRANTED_MB=$(extract_kpi "grantedMemory")
    PRIVATE_MB=$(extract_kpi "privateMemory")
    OVERHEAD_MB=$(extract_kpi "consumedOverheadMemory")

    if [ "$OUTPUT_FORMAT" = "table" ]; then
        printf "%-5s %-43s %-8s %-8s %-8s %-10s %-8s %-8s %-10s %-10s %-10s %-10s\n" \
            "$VMID" "$VM_NAME" "$VM_MEM_GB" \
            "$(( BALLOON_MB / 1024 ))" "$(( SWAP_MB / 1024 ))" "$(( COMPRESS_MB / 1024 ))" \
            "$(( SHARED_MB / 1024 ))" "$(( GUEST_MB / 1024 ))" "$(( HOST_MB / 1024 ))" \
            "$(( GRANTED_MB / 1024 ))" "$(( PRIVATE_MB / 1024 ))" "$(( OVERHEAD_MB / 1024 ))"
    elif [ "$OUTPUT_FORMAT" = "csv" ]; then
        printf '"%s","%s",%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n' \
            "$(json_escape "$VMID")" "$(json_escape "$VM_NAME")" "$VM_MEM_GB" \
            "$(( BALLOON_MB / 1024 ))" "$(( SWAP_MB / 1024 ))" "$(( COMPRESS_MB / 1024 ))" \
            "$(( SHARED_MB / 1024 ))" "$(( GUEST_MB / 1024 ))" "$(( HOST_MB / 1024 ))" \
            "$(( GRANTED_MB / 1024 ))" "$(( PRIVATE_MB / 1024 ))" "$(( OVERHEAD_MB / 1024 ))"
    elif [ "$OUTPUT_FORMAT" = "json" ]; then
        [ "$VM_JSON_COUNT" -gt 0 ] && printf ',\n'
        printf '    {\n'
        printf '      "id": "%s",\n'         "$(json_escape "$VMID")"
        printf '      "name": "%s",\n'       "$(json_escape "$VM_NAME")"
        printf '      "ram_gb": %d,\n'       "$VM_MEM_GB"
        printf '      "balloon_gb": %d,\n'   "$(( BALLOON_MB / 1024 ))"
        printf '      "swap_gb": %d,\n'      "$(( SWAP_MB / 1024 ))"
        printf '      "compress_gb": %d,\n'  "$(( COMPRESS_MB / 1024 ))"
        printf '      "shared_gb": %d,\n'    "$(( SHARED_MB / 1024 ))"
        printf '      "guest_gb": %d,\n'     "$(( GUEST_MB / 1024 ))"
        printf '      "host_gb": %d,\n'      "$(( HOST_MB / 1024 ))"
        printf '      "granted_gb": %d,\n'   "$(( GRANTED_MB / 1024 ))"
        printf '      "private_gb": %d,\n'   "$(( PRIVATE_MB / 1024 ))"
        printf '      "overhead_gb": %d\n'   "$(( OVERHEAD_MB / 1024 ))"
        printf '    }'
        VM_JSON_COUNT=$((VM_JSON_COUNT + 1))
    fi

    TOTAL_VM_MEM=$((TOTAL_VM_MEM + VM_MEM_MB))
    TOTAL_BALLOON=$((TOTAL_BALLOON + BALLOON_MB))
    TOTAL_SWAP=$((TOTAL_SWAP + SWAP_MB))
    TOTAL_COMPRESS=$((TOTAL_COMPRESS + COMPRESS_MB))
    TOTAL_SHARED=$((TOTAL_SHARED + SHARED_MB))
done

# --- Totals / Footer ---
HOST_OVERHEAD_GB=$(( HOST_MEM_USED_GB - (TOTAL_VM_MEM / 1024) ))

if [ "$OUTPUT_FORMAT" = "table" ]; then
    echo "----------------------------------------------------------------------------------------------------------------------------------------------------------"
    echo "Total VM Memory Usage:              $(( TOTAL_VM_MEM / 1024 )) GB"
    echo "Total Ballooned Memory:             $(( TOTAL_BALLOON / 1024 )) GB"
    echo "Total Swapped Memory:               $(( TOTAL_SWAP / 1024 )) GB"
    echo "Total Compressed Memory:            $(( TOTAL_COMPRESS / 1024 )) GB"
    echo "Total Shared Memory:                $(( TOTAL_SHARED / 1024 )) GB"
    echo "Memory Used by Host (excl. VMs):    ${HOST_OVERHEAD_GB} GB"
elif [ "$OUTPUT_FORMAT" = "json" ]; then
    printf '\n  ],\n'
    printf '  "totals": {\n'
    printf '    "vm_mem_gb": %d,\n'       "$(( TOTAL_VM_MEM / 1024 ))"
    printf '    "balloon_gb": %d,\n'      "$(( TOTAL_BALLOON / 1024 ))"
    printf '    "swap_gb": %d,\n'         "$(( TOTAL_SWAP / 1024 ))"
    printf '    "compress_gb": %d,\n'     "$(( TOTAL_COMPRESS / 1024 ))"
    printf '    "shared_gb": %d,\n'       "$(( TOTAL_SHARED / 1024 ))"
    printf '    "host_overhead_gb": %d\n' "$HOST_OVERHEAD_GB"
    printf '  }\n'
    printf '}\n'
fi
