#!/usr/bin/env bash

# Script Name: memory-usage-report-kvm.sh
# Description: Provides a comprehensive KVM host memory usage and optimization summary.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Created: 2025-09-11
# Version: 2.3
#
# Changelog:
#   - 2025-09-11: v2.2 - Corrected misleading "Balloon" column to be accurate and more descriptive.
#   - 2025-09-11: v2.1 - Added host and per-VM guest swap monitoring.
#   - 2025-09-11: v2.0 - Added summary, improved KSM/VM reporting, prerequisite checks, and formatting.
#   - 2025-09-11: v1.0 - Initial version.
#   - 2026-02-17: v2.3 - Renamed to memory-usage-report-kvm.sh.
#                        Added help option.
#                        Fixed awk dommemstat field matching to use exact field names.
#                        Fixed potential float output from awk in max_mib calculation.
#                        Fixed duplicate swap display in Host Configuration section.

# --- Configuration ---
BASELINE_FILE="/var/log/mem_baseline.txt"

# --- Functions ---

show_help() {
    echo "Usage: $0 [-h|--help]"
    echo ""
    echo "Description:"
    echo " Provides a comprehensive KVM host memory usage and optimization summary."
    echo " Reports host memory, per-VM allocation, guest swap activity, KSM savings,"
    echo " hugepages, overcommit settings, and optional baseline comparison."
    echo ""
    echo "Options:"
    echo " -h, --help    Display this help message"
}

print_header() {
    echo ""
    echo "--- $1 ---"
}

check_dependencies() {
    for cmd in virsh bc getconf free awk grep sysctl; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Command not found: $cmd. Please install it." >&2
            exit 1
        fi
    done
}

# --- Argument Parsing ---
OPTIONS=$(getopt -o h --long help -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    echo "Failed to parse options." >&2
    exit 1
fi

eval set -- "$OPTIONS"

while true; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unexpected option: $1" >&2
            exit 1
            ;;
    esac
done

# --- Main Script ---

# 1. Prerequisite Checks
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root." >&2
   exit 1
fi
check_dependencies

# 2. Initial Header
echo "==================================="
echo " KVM Memory Usage Report"
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
        # Use printf "%d" in awk to ensure integer output (avoids float arithmetic errors)
        max_mib=$(virsh dominfo "$vm_name" | awk '/Max memory:/ {printf "%d\n", $3/1024}')
        vm_mem_max_total_mib=$((vm_mem_max_total_mib + ${max_mib:-0}))

        current_kib=$(virsh dommemstat "$vm_name" | awk '$1=="actual" {print $2}')
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
        max_alloc_mib=$(virsh dominfo "$vm_name" | awk '/Max memory:/ {printf "%d\n", $3/1024}')

        current_alloc_kib=$(echo "$stats" | awk '$1=="actual"   {print $2}')
        guest_free_kib=$(echo    "$stats" | awk '$1=="unused"   {print $2}')
        swap_in_kib=$(echo       "$stats" | awk '$1=="swap_in"  {print $2}')
        swap_out_kib=$(echo      "$stats" | awk '$1=="swap_out" {print $2}')

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
free -h | grep -E '^Mem'

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
