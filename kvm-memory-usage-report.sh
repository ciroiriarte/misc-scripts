#!/usr/bin/env bash

# Script Name: kvm-memory-optimization-report.sh
# Description: Provides a comprehensive KVM host memory usage and optimization summary.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Version: 2.0
#
# Changelog:
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
vm_mem_allocated_total_mib=0
vm_mem_actual_total_mib=0

# Loop through running VMs to aggregate memory stats
while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
        allocated_mib=$(virsh dominfo "$vm_name" | awk '/Max memory:/{print $3/1024}')
        vm_mem_allocated_total_mib=$((vm_mem_allocated_total_mib + allocated_mib))
        
        actual_kib=$(virsh dommemstat "$vm_name" | awk '/actual/{print $2}')
        if [[ -n "$actual_kib" ]]; then
            vm_mem_actual_total_mib=$((vm_mem_actual_total_mib + actual_kib / 1024))
        fi
    fi
done < <(virsh list --state-running --name)

host_mem_free_mib=$(free -m | awk '/^Mem:/{print $4}')
host_mem_available_mib=$(free -m | awk '/^Mem:/{print $7}')

printf "%-25s : %'d MiB\n" "Host Total Memory" "$host_mem_total_mib"
printf "%-25s : %'d MiB\n" "Total VM Allocated" "$vm_mem_allocated_total_mib"
printf "%-25s : %'d MiB\n" "Total VM Actual Usage" "$vm_mem_actual_total_mib"
printf "%-25s : %'d MiB\n" "Host Available Memory" "$host_mem_available_mib"

# 4. Detailed VM Memory Usage
print_header "Running VM Memory Details"
printf "%-20s %15s %15s %15s\n" "VM Name" "Allocated (MiB)" "Actual Use (MiB)" "Balloon (MiB)"
echo "---------------------------------------------------------------------"
while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
        allocated_mib=$(virsh dominfo "$vm_name" | awk '/Max memory:/{print $3/1024}')
        actual_kib=$(virsh dommemstat "$vm_name" | awk '/actual/{print $2}')
        unused_kib=$(virsh dommemstat "$vm_name" | awk '/unused/{print $2}')
        
        actual_mib=$((actual_kib / 1024))
        balloon_mib=$(( (allocated_mib * 1024 - unused_kib) / 1024 ))

        printf "%-20s %'15d %'15d %'15d\n" "$vm_name" "$allocated_mib" "$actual_mib" "$balloon_mib"
    fi
done < <(virsh list --state-running --name)

# 5. KSM (Kernel Same-page Merging) Savings
print_header "KSM Memory Savings"
ksm_run=$(cat /sys/kernel/mm/ksm/run)
if [[ "$ksm_run" -eq 1 ]]; then
    echo "Status: KSM is Active"
    pages_sharing=$(cat /sys/kernel/mm/ksm/pages_sharing)
    pages_shared=$(cat /sys/kernel/mm/ksm/pages_shared)
    pages_saved=$((pages_sharing - pages_shared))
    page_size=$(getconf PAGESIZE)
    
    memory_saved_mib=$(echo "$pages_saved * $page_size / 1024 / 1024" | bc -l)
    
    printf "%-25s : %'d\n" "Pages saved" "$pages_saved"
    printf "%-25s : %.2f MiB\n" "Estimated memory saved" "$memory_saved_mib"
else
    echo "Status: KSM is Inactive (/sys/kernel/mm/ksm/run is 0)"
fi

# 6. Host-level Details
print_header "Host Configuration"
echo "Host Memory Usage:"
free -h

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
