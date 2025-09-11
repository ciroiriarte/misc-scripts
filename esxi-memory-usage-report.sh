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


# Convert bytes to MB
TOTAL_MEM_BYTES=$(esxcli hardware memory get | awk '/Physical Memory:/ {print $3}')
FREE_MEM_BYTES=$(esxcli hardware memory get | awk '/Free Memory:/ {print $3}')
TOTAL_MEM_MB=$((TOTAL_MEM_BYTES / 1024 / 1024))
FREE_MEM_MB=$((FREE_MEM_BYTES / 1024 / 1024))
HOST_MEM_USED_MB=$((TOTAL_MEM_MB - FREE_MEM_MB))

echo "Total System Memory: ${TOTAL_MEM_MB} MB"
echo "Used by Host: ${HOST_MEM_USED_MB} MB"
echo ""

# List all running VMs
VM_IDS=$(vim-cmd vmsvc/getallvms | awk 'NR>1 {print $1}')

printf "%-5s %-30s %-10s %-10s %-10s %-10s %-10s\n" "ID" "VM Name" "RAM(MB)" "Balloon(MB)" "Swap(MB)" "Compress(MB)" "Shared(MB)"
echo "-----------------------------------------------------------------------------------------------"

TOTAL_VM_MEM=0
TOTAL_BALLOON=0
TOTAL_SWAP=0
TOTAL_COMPRESS=0
TOTAL_SHARED=0

for VMID in $VM_IDS; do
    VM_SUMMARY=$(vim-cmd vmsvc/get.summary "$VMID")

    VM_NAME=$(echo "$VM_SUMMARY" | grep -m1 'name =' | awk -F'"' '{print $2}')
    VM_MEM_MB=$(echo "$VM_SUMMARY" | grep -m1 'memorySizeMB =' | awk -F'= ' '{print $2}' | sed 's/,//')

    # Skip if VM name is empty
    if [ -z "$VM_NAME" ]; then
        continue
    fi

    # Get VM world ID
    VM_WORLD_ID=$(esxcli vm process list | grep -A 1 "VM Name: $VM_NAME" | grep "World ID" | awk '{print $3}')

    # Initialize metrics
    BALLOON_MB=0
    SWAP_MB=0
    COMPRESS_MB=0
    SHARED_MB=0

    if [ -n "$VM_WORLD_ID" ]; then
        MEM_STATS=$(vsish -e get /vm/$VM_WORLD_ID/memstats 2>/dev/null | grep -E 'balloonedPages|swappedPages|compressedPages|sharedPages')

        BALLOON_PAGES=$(echo "$MEM_STATS" | grep balloonedPages | awk '{print $2}')
        SWAP_PAGES=$(echo "$MEM_STATS" | grep swappedPages | awk '{print $2}')
        COMPRESS_PAGES=$(echo "$MEM_STATS" | grep compressedPages | awk '{print $2}')
        SHARED_PAGES=$(echo "$MEM_STATS" | grep sharedPages | awk '{print $2}')

        BALLOON_MB=$((BALLOON_PAGES * 4 / 1024))
        SWAP_MB=$((SWAP_PAGES * 4 / 1024))
        COMPRESS_MB=$((COMPRESS_PAGES * 4 / 1024))
        SHARED_MB=$((SHARED_PAGES * 4 / 1024))
    fi

    printf "%-5s %-30s %-10s %-10s %-10s %-10s %-10s\n" "$VMID" "$VM_NAME" "$VM_MEM_MB" "$BALLOON_MB" "$SWAP_MB" "$COMPRESS_MB" "$SHARED_MB"

    TOTAL_VM_MEM=$((TOTAL_VM_MEM + VM_MEM_MB))
    TOTAL_BALLOON=$((TOTAL_BALLOON + BALLOON_MB))
    TOTAL_SWAP=$((TOTAL_SWAP + SWAP_MB))
    TOTAL_COMPRESS=$((TOTAL_COMPRESS + COMPRESS_MB))
    TOTAL_SHARED=$((TOTAL_SHARED + SHARED_MB))
done

echo "-----------------------------------------------------------------------------------------------"
echo "Total VM Memory Usage: ${TOTAL_VM_MEM} MB"
echo "Total Ballooned Memory: ${TOTAL_BALLOON} MB"
echo "Total Swapped Memory: ${TOTAL_SWAP} MB"
echo "Total Compressed Memory: ${TOTAL_COMPRESS} MB"
echo "Total Shared Memory: ${TOTAL_SHARED} MB"
echo "Memory Used by Host (excluding VMs): $((HOST_MEM_USED_MB - TOTAL_VM_MEM)) MB"
