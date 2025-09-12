#!/bin/sh

# Script Name: esxi-memory-usage-report.sh
# Description: Provides a basic ESXi host memory usage and optimization summary.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Version: 1.0
#
# Changelog:
#   - 2025-09-11: v1.0 - Initial version.

echo "==================================="
echo " ESXi Memory Usage Report"
echo "==================================="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Get memory stats from vsish
MEM_STATS=$(vsish -e get /memory/comprehensive)

TOTAL_MEM_KB=$(echo "$MEM_STATS" | grep "Physical memory estimate" | awk -F':' '{print $2}' | awk '{print $1}')
FREE_MEM_KB=$(echo "$MEM_STATS" | grep "Free:" | awk -F':' '{print $2}' | awk '{print $1}')

TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))
FREE_MEM_GB=$((FREE_MEM_KB / 1024 / 1024))
HOST_MEM_USED_GB=$((TOTAL_MEM_GB - FREE_MEM_GB))

# Calculate usage percentage
if [ "$TOTAL_MEM_GB" -gt 0 ]; then
    USAGE_PERCENT=$((HOST_MEM_USED_GB * 100 / TOTAL_MEM_GB))
else
    USAGE_PERCENT=0
fi

echo "Total System Memory: ${TOTAL_MEM_GB} GB"
echo "Used by Host: ${HOST_MEM_USED_GB} GB (${USAGE_PERCENT}%)"
echo ""

# List all running VMs
VM_IDS=$(vim-cmd vmsvc/getallvms | awk 'NR>1 {print $1}')

# Header
printf "%-5s %-43s %-8s %-8s %-8s %-10s %-8s %-8s %-10s %-10s %-10s %-10s\n" \
  "ID" "VM Name" "RAM" "Balloon" "Swap" "Compress" "Shared" "Guest" "Host" "Granted" "Private" "Overhead"
echo "----------------------------------------------------------------------------------------------------------------------------------"


TOTAL_VM_MEM=0
TOTAL_BALLOON=0
TOTAL_SWAP=0
TOTAL_COMPRESS=0
TOTAL_SHARED=0

for VMID in $VM_IDS; do
    VM_SUMMARY=$(vim-cmd vmsvc/get.summary "$VMID")

    VM_NAME=$(echo "$VM_SUMMARY" | grep -m1 'name =' | awk -F'"' '{print $2}')
    VM_MEM_MB=$(echo "$VM_SUMMARY" | grep -m1 'memorySizeMB =' | awk -F'= ' '{print $2}' | sed 's/,//')
    VM_MEM_GB=$(( $VM_MEM_MB / 1024 ))

    # Skip if VM name is empty
    if [ -z "$VM_NAME" ]; then
        continue
    fi

    # Extract memory optimization metrics from quickStats
    extract_kpi() {
        echo "$VM_SUMMARY" | grep -m1 "$1" | awk '{print $NF}' | sed 's/,//' | grep -E '^[0-9]+$' || echo 0
    }

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
    "$VMID" "$VM_NAME" "$(( $VM_MEM_MB / 1024 ))" "$(( $BALLOON_MB / 1024 ))" "$(( $SWAP_MB / 1024 ))" "$(( $COMPRESS_MB / 1024 ))" "$(( $SHARED_MB / 1024 ))" \
    "$(( $GUEST_MB / 1024 ))" "$(( $HOST_MB / 1024 ))" "$(( $GRANTED_MB / 1024 ))" "$(( $PRIVATE_MB / 1024 ))" "$(( $OVERHEAD_MB / 1024 ))"


    TOTAL_VM_MEM=$((TOTAL_VM_MEM + VM_MEM_MB))
    TOTAL_BALLOON=$((TOTAL_BALLOON + BALLOON_MB))
    TOTAL_SWAP=$((TOTAL_SWAP + SWAP_MB))
    TOTAL_COMPRESS=$((TOTAL_COMPRESS + COMPRESS_MB))
    TOTAL_SHARED=$((TOTAL_SHARED + SHARED_MB))
done

echo "-----------------------------------------------------------------------------------------------------------------------------"
echo "Total VM Memory Usage: $(( ${TOTAL_VM_MEM} / 1024 )) GB"
echo "Total Ballooned Memory: $(( ${TOTAL_BALLOON} / 1024 )) GB"
echo "Total Swapped Memory: $(( ${TOTAL_SWAP} / 1024 )) GB"
echo "Total Compressed Memory: $(( ${TOTAL_COMPRESS} / 1024 )) GB"
echo "Total Shared Memory: $(( ${TOTAL_SHARED} / 1024 )) GB"
echo "Memory Used by Host (excluding VMs): $(( ${HOST_MEM_USED_GB} - (${TOTAL_VM_MEM} / 1024 ) )) GB"

