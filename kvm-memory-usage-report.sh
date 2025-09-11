#!/bin/bash

# Script Name: kvm-memory-usage-report.sh
# Description: This script provides a KVM host memory usage summary.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Created: 2025-09-11
#
# Requirements:
#   - Must be run as root
#   - Requires: virsh
#
# Change Log:
#   - 2025-09-11: Initial version

echo "=== Memory Optimization Report ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Host memory usage
echo "--- Host Memory Usage ---"
free -h
echo ""

# VM memory usage
echo "--- VM Memory Usage ---"
virsh list --name | while read vm; do
    if [ -n "$vm" ]; then
        echo "VM: $vm"
        virsh dommemstat "$vm" | awk '{print $1 ": " $2/1024 " MB"}'
        echo ""
    fi
done

# Hugepages usage
echo "--- Hugepages Usage ---"
grep HugePages /proc/meminfo
echo ""

# Ballooning status
echo "--- Ballooning Status ---"
virsh list --name | while read vm; do
    if [ -n "$vm" ]; then
        echo "VM: $vm"
        virsh dominfo "$vm" | grep -i balloon
        echo ""
    fi
done

# Overcommit settings
echo "--- Overcommit Settings ---"
echo "vm.overcommit_memory: $(sysctl -n vm.overcommit_memory)"
echo "vm.overcommit_ratio: $(sysctl -n vm.overcommit_ratio)"
echo ""

# KSM memory savings
echo "--- KSM Memory Savings ---"
pages_sharing=$(cat /sys/kernel/mm/ksm/pages_sharing)
pages_shared=$(cat /sys/kernel/mm/ksm/pages_shared)
pages_saved=$((pages_sharing - pages_shared))
memory_saved_gb=$(echo "$pages_saved * 4096 / 1024 / 1024 / 1024" | bc -l)
printf "Pages saved: %'d\n" "$pages_saved"
printf "Estimated memory saved via KSM: %.2f GB\n" "$memory_saved_gb"
echo ""

# Optional: Compare with baseline
BASELINE="/var/log/mem_baseline.txt"
if [ -f "$BASELINE" ]; then
    echo "--- Comparing with Baseline ---"
    echo "Baseline recorded on: $(head -n 1 $BASELINE)"
    echo ""
    echo "Current vs Baseline:"
    echo "Current Host Memory:"
    free -m | grep Mem
    echo "Baseline Host Memory:"
    grep Mem $BASELINE
    echo ""
else
    echo "No baseline found. You can create one with:"
    echo "  (echo \"$(date)\"; free -m) > $BASELINE"
fi

echo "=== End of Report ==="
