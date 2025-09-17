#!/bin/bash

# Script Name: quick-benchmark-storage.sh
# Description: This script performs destructive I/O benchmarks on specified storage devices.
#                 It will COMPLETELY WIPE ALL DATA on the disks defined in the DISKS array.
#                 After testing, it will clean up by unmounting and wiping filesystem signatures.
#
# This version is validated to work on Rocky Linux, openSUSE, and Debian/Ubuntu.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Version: 1.4
#
# Changelog:
#   - 2025-09-17: v1.4 - Fix python dependency for openSUSE
#                      - avoid assuming group name equals username
#   - 2025-09-17: v1.3 - Fix dependency for iozone on openSUSE
#   - 2025-09-17: v1.2 - Match GCC for quick-benchmark-cpu for openSUSE 15.6
#   - 2025-09-17: v1.1 - Use latest PTS for Debian/Ubuntu
#   - 2025-09-17: v1.0 - Improve documentation.
#                      - Fix test working directory.
#                      - Add release disk function.
#                      - Add option to upload results.
#   - 2025-09-16: v0.1 - First draft.

set -e
set -o pipefail

# === Configuration ===
# WARNING: ALL DATA ON THESE DISKS WILL BE PERMANENTLY ERASED.
DISKS=(
    "/dev/vdb;NVMe_Replica3"
    "/dev/vdc;NVMe_EC32"
    "/dev/vdd;HDD_Replica3"
    "/dev/vde;HDD_EC32"
)
REQUIRED_TESTS=("iozone" "fio" "postmark" "compilebench")
TESTUSER=$(whoami)

# === Function to Display Usage ===
usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --upload                 Flag to enable uploading results to openbenchmarking.org."
    echo "  --result-name <name>     Set the 'Saved Test Name' for the upload (e.g., 'My Server NVMe vs HDD')."
    echo "  --result-id <identifier> Set the 'Test Identifier' for the upload (e.g., 'Q3-2025-Storage-Test')."
    echo "  --help                   Display this help message."
    echo
    echo "Example: $0 --upload --result-name \"Production Server Test\" --result-id \"Prod-Config-V1\""
}

# === Argument Parsing ===
UPLOAD_RESULTS=0
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --upload) UPLOAD_RESULTS=1 ;;
        --result-name) UPLOAD_NAME="$2"; shift ;;
        --result-id) UPLOAD_ID="$2"; shift ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# Check if upload is requested but details are missing
if [[ "$UPLOAD_RESULTS" -eq 1 ]] && ([[ -z "$UPLOAD_NAME" ]] || [[ -z "$UPLOAD_ID" ]]); then
    echo "Error: When using --upload, both --result-name and --result-id must be provided."
    usage
    exit 1
fi

# === OS Detection and Package Installation ===
install_packages() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            rocky|rhel|centos)
                echo "Detected Rocky Linux or RHEL-based system"
                sudo dnf install -y epel-release
                sudo dnf install -y phoronix-test-suite xfsprogs util-linux
                ;;
            ubuntu|debian)
                echo "Detected Ubuntu or Debian-based system"
                sudo apt-get update
                # util-linux provides wipefs
                sudo apt-get install -y phoronix-test-suite xfsprogs util-linux || {
                    echo "Phoronix Test Suite not found in repo, attempting fallback install..."
                    wget -O /tmp/phoronix.deb https://phoronix-test-suite.com/releases/repo/pts.debian/files/phoronix-test-suite_10.8.4_all.deb
                    sudo dpkg -i /tmp/phoronix.deb
                    sudo apt-get install -f -y # Install dependencies
                }
                ;;
            opensuse*|suse)
                echo "Detected openSUSE system"
                setup_opensuse_repo
                ;;
            *)
                echo "Unsupported OS: $ID"
                exit 1
                ;;
        esac
    else
        echo "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
}

# === openSUSE Repository Setup ===
setup_opensuse_repo() {
    local repo_url
    case "$VERSION_ID" in
        *Tumbleweed*)
            echo "Adding benchmark repo for Tumbleweed..."
            repo_url="https://download.opensuse.org/repositories/benchmark/openSUSE_Tumbleweed"
            ;;
        *Slowroll*)
            echo "Adding benchmark repo for Slowroll..."
            repo_url="https://download.opensuse.org/repositories/benchmark/openSUSE_Slowroll"
            ;;
        "15.6")
            echo "Adding benchmark repo for Leap 15.6..."
            repo_url="https://download.opensuse.org/repositories/benchmark/15.6/"
            gcc_extra="gcc12 gcc12-c++"
            ;;
        *)
            echo "Unsupported openSUSE version: $VERSION_ID"
            exit 1
            ;;
    esac
    sudo zypper ar -f -p 90 "$repo_url" benchmark
    sudo zypper --gpg-auto-import-keys refresh
    sudo zypper install -y phoronix-test-suite xfsprogs util-linux gcc gcc-c++ ${gcc_extra} make autoconf bison flex libopenssl-devel Mesa-demo-x libelf-devel libaio-devel python
    if [ "$VERSION_ID" == "15.6" ]
    then
    	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100
	    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100
    fi
}

# --- SCRIPT EXECUTION STARTS HERE ---

echo "Starting storage benchmark script..."

install_packages

# === Configure Phoronix Test Suite for Batch Mode ===
echo "Setting up Phoronix Test Suite in batch mode..."
phoronix-test-suite batch-setup <<EOF
Y
Y
N
N
N
EOF

# === Install Required Phoronix Tests ===
for test_name in "${REQUIRED_TESTS[@]}"; do
    echo "Installing test: $test_name"
    phoronix-test-suite install "$test_name"
done

# === Prepare Disks ===
prepare_disk() {
    local disk_entry=$1
    local device
    local label
    device=$(echo "$disk_entry" | cut -d';' -f1)
    label=$(echo "$disk_entry" | cut -d';' -f2)
    local mount_point="/mnt/${label}"

    echo "--- Preparing $device as $label ---"
    echo "WARNING: All data on $device will be erased."

    sudo umount "$device" 2>/dev/null || true # Ignore error if not mounted
    sudo mkfs.xfs -f -L "$label" "$device"
    sudo mkdir -p "$mount_point"
    sudo mount LABEL="$label" "$mount_point"
    sudo chown "$TESTUSER:" "$mount_point"
    echo "Disk $device mounted at $mount_point and ready for testing."
}

for disk in "${DISKS[@]}"; do
    prepare_disk "$disk"
done

# === Run Tests on Each Disk ===
RESULT_NAMES=()

run_tests_on_disk() {
    local disk_entry=$1
    local label
    label=$(echo "$disk_entry" | cut -d';' -f2)
    local mount_point="/mnt/${label}"

    for test_name in "${REQUIRED_TESTS[@]}"; do
        echo "--- Running $test_name on $label ($mount_point) ---"
        
        # *** CRITICAL FIX ***
        # Set PTS_TEST_DIR_OVERRIDE to force the test to run on the target disk.
        export PTS_TEST_DIR_OVERRIDE="$mount_point"
        
        phoronix-test-suite batch-run "$test_name"
        
        # Unset the variable to avoid side effects
        unset PTS_TEST_DIR_OVERRIDE

        # Find and rename the result directory for clarity
        local result_dir
        result_dir=$(ls -td ~/.phoronix-test-suite/test-results/* | head -n 1)
        
        if [ -d "$result_dir" ]; then
            local result_name="${label}_${test_name}_result"
            mv "$result_dir" "$HOME/.phoronix-test-suite/test-results/$result_name"
            RESULT_NAMES+=("$result_name")
            echo "Result for $test_name on $label saved as: $result_name"
        else
            echo "Warning: No result directory found for $test_name on $label"
        fi
    done
}

for disk in "${DISKS[@]}"; do
    run_tests_on_disk "$disk"
done

# === Upload Results if Requested ===
if [[ "$UPLOAD_RESULTS" -eq 1 ]]; then
    echo "--- Starting result upload to OpenBenchmarking.org ---"
    export PTS_UPLOAD_NAME="$UPLOAD_NAME"
    export PTS_UPLOAD_IDENTIFIER="$UPLOAD_ID"
    
    for result in "${RESULT_NAMES[@]}"; do
        echo "Uploading result: $result"
        phoronix-test-suite upload-result "$result"
    done
    
    unset PTS_UPLOAD_NAME
    unset PTS_UPLOAD_IDENTIFIER
    echo "All uploads complete."
fi

# === Compare Results Locally ===
echo "--- Generating local result comparisons ---"
for test_name in "${REQUIRED_TESTS[@]}"; do
    echo "========================================"
    echo "    Comparison for $test_name"
    echo "========================================"
    
    # Build a list of results for the current test
    results_to_compare=()
    for r_name in "${RESULT_NAMES[@]}"; do
        if [[ "$r_name" == *_${test_name}_result ]]; then
            results_to_compare+=("$r_name")
        fi
    done

    if [ ${#results_to_compare[@]} -gt 0 ]; then
        phoronix-test-suite compare-results "${results_to_compare[@]}"
    else
        echo "No results found to compare for $test_name."
    fi
done

# === Release and Clean Up Disks ===
release_disk() {
    local disk_entry=$1
    local device
    local label
    device=$(echo "$disk_entry" | cut -d';' -f1)
    label=$(echo "$disk_entry" | cut -d';' -f2)
    local mount_point="/mnt/${label}"

    echo "--- Releasing disk $device ($label) ---"

    # Unmount the filesystem if it's mounted
    if mountpoint -q "$mount_point"; then
        echo "Unmounting $mount_point..."
        sudo umount "$mount_point"
    fi

    # Remove the mount point directory
    if [ -d "$mount_point" ]; then
        echo "Removing mount point directory $mount_point..."
        sudo rmdir "$mount_point"
    fi

    # Wipe filesystem signatures from the device to clean it
    echo "Wiping filesystem signatures from $device..."
    sudo wipefs --all --force "$device"

    echo "Disk $device has been cleaned and released."
}

echo "--- Cleaning up test disks ---"
for disk in "${DISKS[@]}"; do
    release_disk "$disk"
done

echo "--- Benchmark script finished ---"
