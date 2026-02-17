#!/bin/sh

# Script Name: memory-usage-report-esxi.sh
# Description: Provides a basic ESXi host memory usage and optimization summary.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Created: 2025-09-11
# Version: 1.1
#
# Changelog:
#   - 2025-09-11: v1.0 - Initial version.
#   - 2026-02-17: v1.1 - Renamed to memory-usage-report-esxi.sh.
#                        Added root check, prerequisite check, and help option.
#                        Moved extract_kpi() outside the VM loop.
#                        Fixed host memory percentage to use MiB precision.
#                        Fixed VM_MEM_GB variable reuse in printf.

# --- Help ---
show_help() {
    echo "Usage: $0 [-h|--help]"
    echo ""
    echo "Description:"
    echo " Reports ESXi host and per-VM memory usage including ballooning,"
    echo " swapping, compression, and shared memory metrics."
    echo " Must be run directly on the ESXi host (via SSH or local shell)."
    echo ""
    echo "Options:"
    echo " -h, --help    Display this help message"
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

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

# --- Helper: extract a named numeric KPI from vm.summary quickStats ---
# Depends on $VM_SUMMARY being set in the caller's scope.
extract_kpi() {
    echo "$VM_SUMMARY" | grep -m1 "$1" | awk '{print $NF}' | sed 's/,//' | grep -E '^[0-9]+$' || echo 0
}

# --- Report Header ---
echo "==================================="
echo " ESXi Memory Usage Report"
echo "==================================="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# --- Host Memory Summary ---
MEM_STATS=$(vsish -e get /memory/comprehensive)

TOTAL_MEM_KB=$(echo "$MEM_STATS" | grep "Physical memory estimate" | awk -F':' '{print $2}' | awk '{print $1}')
FREE_MEM_KB=$(echo "$MEM_STATS" | grep "Free:" | awk -F':' '{print $2}' | awk '{print $1}')

TOTAL_MEM_MIB=$((TOTAL_MEM_KB / 1024))
FREE_MEM_MIB=$((FREE_MEM_KB / 1024))
HOST_MEM_USED_MIB=$((TOTAL_MEM_MIB - FREE_MEM_MIB))

# Display in GB but compute percentage from MiB for sub-GB accuracy
TOTAL_MEM_GB=$((TOTAL_MEM_MIB / 1024))
HOST_MEM_USED_GB=$((HOST_MEM_USED_MIB / 1024))

if [ "$TOTAL_MEM_MIB" -gt 0 ]; then
    USAGE_PERCENT=$((HOST_MEM_USED_MIB * 100 / TOTAL_MEM_MIB))
else
    USAGE_PERCENT=0
fi

echo "Total System Memory: ${TOTAL_MEM_GB} GB"
echo "Used by Host: ${HOST_MEM_USED_GB} GB (${USAGE_PERCENT}%)"
echo ""

# --- Per-VM Memory Table ---
VM_IDS=$(vim-cmd vmsvc/getallvms | awk 'NR>1 {print $1}')

printf "%-5s %-43s %-8s %-8s %-8s %-10s %-8s %-8s %-10s %-10s %-10s %-10s\n" \
  "ID" "VM Name" "RAM(GB)" "Bloon" "Swap" "Compress" "Shared" "Guest" "Host" "Granted" "Private" "Overhead"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------"

TOTAL_VM_MEM=0
TOTAL_BALLOON=0
TOTAL_SWAP=0
TOTAL_COMPRESS=0
TOTAL_SHARED=0

for VMID in $VM_IDS; do
    VM_SUMMARY=$(vim-cmd vmsvc/get.summary "$VMID")

    VM_NAME=$(echo "$VM_SUMMARY" | grep -m1 'name =' | awk -F'"' '{print $2}')
    VM_MEM_MB=$(echo "$VM_SUMMARY" | grep -m1 'memorySizeMB =' | awk -F'= ' '{print $2}' | sed 's/,//')
    VM_MEM_GB=$(( VM_MEM_MB / 1024 ))

    # Skip if VM name is empty
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

    printf "%-5s %-43s %-8s %-8s %-8s %-10s %-8s %-8s %-10s %-10s %-10s %-10s\n" \
        "$VMID" "$VM_NAME" "$VM_MEM_GB" \
        "$(( BALLOON_MB / 1024 ))" "$(( SWAP_MB / 1024 ))" "$(( COMPRESS_MB / 1024 ))" \
        "$(( SHARED_MB / 1024 ))" "$(( GUEST_MB / 1024 ))" "$(( HOST_MB / 1024 ))" \
        "$(( GRANTED_MB / 1024 ))" "$(( PRIVATE_MB / 1024 ))" "$(( OVERHEAD_MB / 1024 ))"

    TOTAL_VM_MEM=$((TOTAL_VM_MEM + VM_MEM_MB))
    TOTAL_BALLOON=$((TOTAL_BALLOON + BALLOON_MB))
    TOTAL_SWAP=$((TOTAL_SWAP + SWAP_MB))
    TOTAL_COMPRESS=$((TOTAL_COMPRESS + COMPRESS_MB))
    TOTAL_SHARED=$((TOTAL_SHARED + SHARED_MB))
done

echo "----------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "Total VM Memory Usage:              $(( TOTAL_VM_MEM / 1024 )) GB"
echo "Total Ballooned Memory:             $(( TOTAL_BALLOON / 1024 )) GB"
echo "Total Swapped Memory:               $(( TOTAL_SWAP / 1024 )) GB"
echo "Total Compressed Memory:            $(( TOTAL_COMPRESS / 1024 )) GB"
echo "Total Shared Memory:                $(( TOTAL_SHARED / 1024 )) GB"
echo "Memory Used by Host (excl. VMs):    $(( HOST_MEM_USED_GB - (TOTAL_VM_MEM / 1024) )) GB"
