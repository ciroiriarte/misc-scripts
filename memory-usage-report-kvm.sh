#!/usr/bin/env bash

# Script Name: memory-usage-report-kvm.sh
# Description: Provides a comprehensive KVM host memory usage and optimization summary.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Created: 2025-09-11
# Version: 2.4
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
#   - 2026-02-17: v2.4 - Added --output option for CSV and JSON formats.

# --- Configuration ---
VERSION="2.4"
BASELINE_FILE="/var/log/mem_baseline.txt"
OUTPUT_FORMAT="table"

# --- Functions ---

show_help() {
    echo "Usage: $0 [-h|--help] [-v|--version] [--output FORMAT]"
    echo ""
    echo "Version: $VERSION"
    echo ""
    echo "Description:"
    echo " Provides a comprehensive KVM host memory usage and optimization summary."
    echo " Reports host memory, per-VM allocation, guest swap activity, KSM savings,"
    echo " hugepages, overcommit settings, and optional baseline comparison."
    echo ""
    echo "Options:"
    echo " -h, --help        Display this help message"
    echo " -v, --version     Display version information"
    echo " --output FORMAT   Output format: table (default), csv, or json"
    echo "                   csv: VM table only (VM name + MiB columns)."
    echo "                   json: full report (host_summary, vms, ksm, host_config)."
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

json_escape() {
    local STR="$1"
    STR="${STR//\\/\\\\}"
    STR="${STR//\"/\\\"}"
    printf '%s' "$STR"
}

# --- Argument Parsing ---
OPTIONS=$(getopt -o hv --long help,version,output: -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    echo "Failed to parse options." >&2
    exit 1
fi

eval set -- "$OPTIONS"

while true; do
    case "$1" in
        -v|--version)
            echo "$0 $VERSION"
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --output)
            case "$2" in
                table|csv|json)
                    OUTPUT_FORMAT="$2"
                    ;;
                *)
                    echo "Invalid output format: '$2'. Choose from table, csv, or json." >&2
                    exit 1
                    ;;
            esac
            shift 2
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

# --- Prerequisite Checks ---
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root." >&2
   exit 1
fi
check_dependencies

# --- Table-only: Initial Header ---
if [[ "$OUTPUT_FORMAT" == "table" ]]; then
    echo "==================================="
    echo " KVM Memory Usage Report"
    echo "==================================="
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
    echo ""
fi

# --- Collect Host-level Memory Stats ---
host_mem_total_mib=$(free -m | awk '/^Mem:/{print $2}')
host_mem_available_mib=$(free -m | awk '/^Mem:/{print $7}')
vm_mem_max_total_mib=0
vm_mem_current_total_mib=0

# Loop 1: aggregate VM totals for summary
while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
        max_mib=$(virsh dominfo "$vm_name" | awk '/Max memory:/ {printf "%d\n", $3/1024}')
        vm_mem_max_total_mib=$((vm_mem_max_total_mib + ${max_mib:-0}))

        current_kib=$(virsh dommemstat "$vm_name" | awk '$1=="actual" {print $2}')
        if [[ -n "$current_kib" ]]; then
            vm_mem_current_total_mib=$((vm_mem_current_total_mib + current_kib / 1024))
        fi
    fi
done < <(virsh list --state-running --name)

# --- Host Summary / Section Headers ---
if [[ "$OUTPUT_FORMAT" == "table" ]]; then
    print_header "Host & VM Memory Summary"
    printf "%-28s : %'d MiB\n" "Host Total Memory"           "$host_mem_total_mib"
    printf "%-28s : %'d MiB\n" "Total VM Max Allocation"     "$vm_mem_max_total_mib"
    printf "%-28s : %'d MiB\n" "Total VM Current Allocation" "$vm_mem_current_total_mib"
    printf "%-28s : %'d MiB\n" "Host Available Memory"       "$host_mem_available_mib"
    print_header "VM Memory & Swap Details"
    printf "%-20s %15s %15s %15s %15s %12s %12s\n" \
        "VM Name" "Max Alloc" "Current Alloc" "Guest Used" "Guest Free" "Swap In" "Swap Out"
    printf "%-20s %15s %15s %15s %15s %12s %12s\n" \
        "" "(MiB)" "(MiB)" "(MiB)" "(MiB)" "(MiB)" "(MiB)"
    echo "----------------------------------------------------------------------------------------------------------------------------"
elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    printf '"%s","%s","%s","%s","%s","%s","%s"\n' \
        "VM Name" "Max Alloc (MiB)" "Current Alloc (MiB)" \
        "Guest Used (MiB)" "Guest Free (MiB)" "Swap In (MiB)" "Swap Out (MiB)"
elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
    printf '{\n'
    printf '  "host_summary": {\n'
    printf '    "total_mib": %d,\n'              "$host_mem_total_mib"
    printf '    "vm_max_total_mib": %d,\n'        "$vm_mem_max_total_mib"
    printf '    "vm_current_total_mib": %d,\n'    "$vm_mem_current_total_mib"
    printf '    "available_mib": %d\n'            "$host_mem_available_mib"
    printf '  },\n'
    printf '  "vms": [\n'
fi

# --- Loop 2: Per-VM Detail Rows ---
vm_json_count=0
while read -r vm_name; do
    if [[ -n "$vm_name" ]]; then
        stats=$(virsh dommemstat "$vm_name")
        max_alloc_mib=$(virsh dominfo "$vm_name" | awk '/Max memory:/ {printf "%d\n", $3/1024}')

        current_alloc_kib=$(echo "$stats" | awk '$1=="actual"   {print $2}')
        guest_free_kib=$(echo    "$stats" | awk '$1=="unused"   {print $2}')
        swap_in_kib=$(echo       "$stats" | awk '$1=="swap_in"  {print $2}')
        swap_out_kib=$(echo      "$stats" | awk '$1=="swap_out" {print $2}')

        current_alloc_mib=$(( ${current_alloc_kib:-0} / 1024 ))
        guest_free_mib=$(( ${guest_free_kib:-0} / 1024 ))
        guest_used_mib=$(( current_alloc_mib - guest_free_mib ))
        swap_in_mib=$(( ${swap_in_kib:-0} / 1024 ))
        swap_out_mib=$(( ${swap_out_kib:-0} / 1024 ))

        if [[ "$OUTPUT_FORMAT" == "table" ]]; then
            printf "%-20s %'15.0f %'15.0f %'15.0f %'15.0f %'12.0f %'12.0f\n" \
                "$vm_name" "$max_alloc_mib" "$current_alloc_mib" \
                "$guest_used_mib" "$guest_free_mib" "$swap_in_mib" "$swap_out_mib"
        elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
            printf '"%s",%d,%d,%d,%d,%d,%d\n' \
                "$(json_escape "$vm_name")" "$max_alloc_mib" "$current_alloc_mib" \
                "$guest_used_mib" "$guest_free_mib" "$swap_in_mib" "$swap_out_mib"
        elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
            [[ $vm_json_count -gt 0 ]] && printf ',\n'
            printf '    {\n'
            printf '      "name": "%s",\n'            "$(json_escape "$vm_name")"
            printf '      "max_alloc_mib": %d,\n'     "$max_alloc_mib"
            printf '      "current_alloc_mib": %d,\n' "$current_alloc_mib"
            printf '      "guest_used_mib": %d,\n'    "$guest_used_mib"
            printf '      "guest_free_mib": %d,\n'    "$guest_free_mib"
            printf '      "swap_in_mib": %d,\n'       "$swap_in_mib"
            printf '      "swap_out_mib": %d\n'       "$swap_out_mib"
            printf '    }'
            ((vm_json_count++))
        fi
    fi
done < <(virsh list --state-running --name)

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    printf '\n  ],\n'
fi

# --- KSM Section ---
ksm_active=false
ksm_pages_saved=0
ksm_memory_saved_mib="0"

if [[ "$OUTPUT_FORMAT" == "table" ]]; then
    print_header "KSM Memory Savings"
fi

if [[ -f /sys/kernel/mm/ksm/run ]]; then
    ksm_run=$(cat /sys/kernel/mm/ksm/run)
    if [[ "$ksm_run" -eq 1 ]]; then
        ksm_active=true
        pages_sharing=$(cat /sys/kernel/mm/ksm/pages_sharing)
        pages_shared=$(cat /sys/kernel/mm/ksm/pages_shared)
        ksm_pages_saved=$((pages_sharing - pages_shared))
        page_size=$(getconf PAGESIZE)
        ksm_memory_saved_mib=$(echo "scale=2; $ksm_pages_saved * $page_size / 1024 / 1024" | bc)
        if [[ "$OUTPUT_FORMAT" == "table" ]]; then
            echo "Status: KSM is Active"
            printf "%-25s : %'d\n"    "Pages saved"            "$ksm_pages_saved"
            printf "%-25s : %s MiB\n" "Estimated memory saved" "$ksm_memory_saved_mib"
        fi
    else
        if [[ "$OUTPUT_FORMAT" == "table" ]]; then
            echo "Status: KSM is Inactive (/sys/kernel/mm/ksm/run is 0)"
        fi
    fi
else
    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        echo "Status: KSM not supported or enabled by the kernel."
    fi
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    printf '  "ksm": {\n'
    printf '    "active": %s,\n'              "$ksm_active"
    printf '    "pages_saved": %d,\n'          "$ksm_pages_saved"
    printf '    "estimated_saved_mib": "%s"\n' "$ksm_memory_saved_mib"
    printf '  },\n'
fi

# --- Host Configuration ---
hugepages_total=$(grep '^HugePages_Total:' /proc/meminfo | awk '{print $2}')
hugepages_free=$(grep   '^HugePages_Free:'  /proc/meminfo | awk '{print $2}')
hugepages_size_kb=$(grep '^Hugepagesize:'   /proc/meminfo | awk '{print $2}')
overcommit_memory=$(sysctl -n vm.overcommit_memory)
overcommit_ratio=$(sysctl  -n vm.overcommit_ratio)

if [[ "$OUTPUT_FORMAT" == "table" ]]; then
    print_header "Host Configuration"
    echo "Host Memory Usage:"
    free -h | grep -E '^Mem'
    echo -e "\nHost Swap Usage:"
    free -h | grep -E '^Swap'
    echo -e "\nHugepages Usage:"
    grep HugePages /proc/meminfo
    echo -e "\nOvercommit Settings:"
    echo "vm.overcommit_memory: $overcommit_memory"
    echo "vm.overcommit_ratio: $overcommit_ratio"
elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
    printf '  "host_config": {\n'
    printf '    "hugepages_total": %d,\n'   "${hugepages_total:-0}"
    printf '    "hugepages_free": %d,\n'    "${hugepages_free:-0}"
    printf '    "hugepages_size_kb": %d,\n' "${hugepages_size_kb:-0}"
    printf '    "overcommit_memory": %d,\n' "${overcommit_memory:-0}"
    printf '    "overcommit_ratio": %d\n'   "${overcommit_ratio:-50}"
    printf '  }\n'
    printf '}\n'
fi

# --- Baseline Comparison (table only) ---
if [[ "$OUTPUT_FORMAT" == "table" ]]; then
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
fi
