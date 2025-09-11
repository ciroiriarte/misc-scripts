#!/usr/bin/env bash

# Script Name: kvm-memory-optimization-report.sh
# Description: Provides a comprehensive KVM host memory usage and optimization summary.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Version: 2.2
#
# Changelog:
#   - 2025-09-11: v2.2 - Corrected misleading "Balloon" column to be accurate and more descriptive.
#   - 2025-09-11: v2.1 - Added host and per-VM guest swap monitoring.
#   - 2025-09-11: v2.0 - Added summary, improved KSM/VM reporting, prerequisite checks, and formatting.
#   - 2025-09-11: v1.0 - Initial version.

# --- Configuration ---
BASELINE_FILE="/var/log/mem_baseline.txt"

# --- Functions ---

# Function to print a formatted header
print_header() {
    echo ""
    echo "--- $1 ---"
}

# Function to check for required commands
check_dependencies() {
    for cmd in virsh bc getconf awk grep sysctl; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Command not found: $cmd. Please install it." >&2
            exit 1
        fi
    done
}

# --- Main Script ---

# 1. Prerequisite Checks
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root." >&2
   exit 1
fi
check_dependencies

# 2. Initial Header
echo "==================================="
echo " KVM Memory Optimization Report"
echo "==================================="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# 3. Overall Summary
print_header "Host & VM Memory Summary"
host_mem_total_mib=$(free -m | awk '/^Mem:/{print $2}')
vm_mem_max_total_mib=0
vm_mem_current_total_mib=0

# Loop through running VMs to aggregate memory stats
while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
        max_mib=$(virsh dominfo "$vm_name" | awk '/Max memory:/{print $3/1024}')
        vm_mem_max_total_mib=$((vm_mem_max_total_mib + max_mib))
        
        current_kib=$(virsh dommemstat "$vm_name" | awk '/actual/{print $2}')
        if [[ -n "$current_kib" ]]; then
            vm_mem_current_total_mib=$((vm_mem_current_total_mib + current_kib / 1024))
        fi
    fi
done < <(virsh list --state-running --name)

host_mem_available_mib=$(free -m | awk '/^Mem:/{print $7}')

printf "%-28s : %'d MiB\n" "Host Total Memory" "$host_mem_total_mib"
printf "%-28s : %'d MiB\n" "Total VM Max Allocation" "$vm_mem_max_total_mib"
printf "%-28s : %'d MiB\n" "Total VM Current Allocation" "$vm_mem_current_total_mib"
printf "%-28s : %'d MiB\n" "Host Available Memory" "$host_mem_available_mib"

# 4. Detailed VM Memory Usage & Guest Swap Activity
print_header "VM Memory & Swap Details"
printf "%-20s %15s %15s %15s %15s %12s %12s\n" "VM Name" "Max Alloc" "Current Alloc" "Guest Used" "Guest Free" "Swap In" "Swap Out"
printf "%-20s %15s %15s %15s %15s %12s %12s\n" "" "(MiB)" "(MiB)" "(MiB)" "(MiB)" "(MiB)" "(MiB)"
echo "----------------------------------------------------------------------------------------------------------------------------"
while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
        stats=$(virsh dommemstat "$vm_name")
        max_alloc_mib=$(virsh dominfo "$vm_name" | awk '/Max memory:/{print $3/1024}')
        
        current_alloc_kib=$(echo "$stats" | awk '/actual/{print $2}')
        guest_free_kib=$(echo "$stats" | awk '/unused/{print $2}')
        swap_in_kib=$(echo "$stats" | awk '/swap_in/{print $2}')
        swap_out_kib=$(echo "$stats" | awk '/swap_out/{print $2}')

        # Perform calculations, defaulting to 0 if a value is missing
        current_alloc_mib=$(( ${current_alloc_kib:-0} / 1024 ))
        guest_free_mib=$(( ${guest_free_kib:-0} / 1024 ))
        guest_used_mib=$(( current_alloc_mib - guest_free_mib ))
        swap_in_mib=$(( ${swap_in_kib:-0} / 1024 ))
        swap_out_mib=$(( ${swap_out_kib:-0} / 1024 ))
        
        printf "%-20s %'15.0f %'15.0f %'15.0f %'15.0f %'12.0f %'12.0f\n" \
            "$vm_name" "$max_alloc_mib" "$current_alloc_mib" "$guest_used_mib" "$guest_free_mib" "$swap_in_mib" "$swap_out_mib"
    fi
done < <(virsh list --state-running --name)

# 5. KSM (Kernel Same-page Merging) Savings
print_header "KSM Memory Savings"
if [[ -f /sys/kernel/mm/ksm/run ]]; then
    ksm_run=$(cat /sys/kernel/mm/ksm/run)
    if [[ "$ksm_run" -eq 1 ]]; then
        echo "Status: KSM is Active"
        pages_sharing=$(cat /sys/kernel/mm/ksm/pages_sharing)
        pages_shared=$(cat /sys/kernel/mm/ksm/pages_shared)
        pages_saved=$((pages_sharing - pages_shared))
        page_size=$(getconf PAGESIZE)
        
        memory_saved_mib=$(echo "scale=2; $pages_saved * $page_size / 1024 / 1024" | bc)
        
        printf "%-25s : %'d\n" "Pages saved" "$pages_saved"
        printf "%-25s : %s MiB\n" "Estimated memory saved" "$memory_saved_mib"
    else
        echo "Status: KSM is Inactive (/sys/kernel/mm/ksm/run is 0)"
    fi
else
    echo "Status: KSM not supported or enabled by the kernel."
fi

# 6. Host-level Details
print_header "Host Configuration"
echo "Host Memory Usage:"
free -h

echo -e "\nHost Swap Usage:"
free -h | grep -E '^Swap'

echo -e "\nHugepages Usage:"
grep HugePages /proc/meminfo

echo -e "\nOvercommit Settings:"
echo "vm.overcommit_memory: $(sysctl -n vm.overcommit_memory)"
echo "vm.overcommit_ratio: $(sysctl -n vm.overcommit_ratio)"

# 7. Baseline Comparison (optional)
if [ -f "$BASELINE_FILE" ]; then
    print_header "Comparing with Baseline"
    echo "Baseline recorded on: $(head -n 1 "$BASELINE_FILE")"
    echo ""
    echo "Current Host Memory (MiB):"
    free -m | grep Mem
    echo "Baseline Host Memory (MiB):"
    grep Mem "$BASELINE_FILE"
else
    print_header "Baseline Comparison"
    echo "No baseline found. To create one, run:"
    echo "  (echo \"# Recorded on: \$(date)\"; free -m) > $BASELINE_FILE"
fi

echo ""
echo "==================== End of Report ===================="
