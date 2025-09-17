#!/bin/bash

# Script Name: quick-benchmark-cpu.sh
#
# A script to quickly benchmark CPU performance using the Phoronix Test Suite (PTS).
#
# Description: This script is designed to be a simple, easy-to-use tool for running a
# 		standardized CPU benchmark. It automatically installs PTS on supported systems
# 		(Ubuntu, Rocky Linux, openSUSE) if it is not present.
#
# 		It autodetects the system's CPU topology (sockets, cores, threads) and scales
# 		the test accordingly. It also provides an option to manually specify the number
# 		of threads to use.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Version: 1.0
#
# Changelog:
#   - 2025-09-17: v0.1 - First draft.
#
#
# Usage:
#   ./quick-benchmark-cpu.sh [OPTIONS]
#
# OPTIONS:
#   -t, --threads <N>      Manually specify the number of threads to use (default: all available).
#   -u, --upload           Upload the benchmark results to OpenBenchmarking.org.
#   -i, --result-id <identifier> Set the 'Test Identifier' for the upload (e.g., 'XCloud-cpuN-20250917')."
#   -n, --result-name <name>     Set the 'Saved Test Name' for the upload (e.g., 'CPU type N on X Cloud provider')."
#   -h, --help             Display this help message and exit.
#
# EXAMPLES:
#   # Run a benchmark using all available CPU threads.
#   ./quick-benchmark-cpu.sh
#
#   # Run a benchmark using only 4 threads.
#   ./quick-benchmark-cpu.sh -t 4
#
#   # Run a benchmark and upload the results with a custom name and description.
#   ./quick-benchmark-cpu.sh --upload --result-id "XCloud-cpuN-20250917" --result-name "CPU type N on X Cloud provider"
#
# DEPENDENCIES:
#   - lscpu (from util-linux)
#   - wget or curl (for PTS installation)
#

set -e
set -o pipefail

# === Configuration ===
# The Phoronix Test Suite test to run.
# 'build-linux-kernel' is a good real-world, multi-threaded benchmark.
REQUIRED_TESTS=("pts/build-linux-kernel")
# === End Configuration ===

# === Helper Functions ===

# Function to display help message
usage() {
  grep '^#' "$0" | cut -c3-
  exit 0
}

# Function to install Phoronix Test Suite on supported distributions
install_packages() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            rocky|rhel|centos)
                echo "Detected Rocky Linux or RHEL-based system"
                sudo dnf install -y epel-release
                sudo dnf install -y phoronix-test-suite
		sudo dnf install -y xfsprogs util-linux gcc gcc-c++ make autoconf bison flex openssl-devel mesa-demos
                ;;
            ubuntu|debian)
                echo "Detected Ubuntu or Debian-based system"
                sudo apt-get update
                # util-linux provides wipefs
                sudo apt-get install -y phoronix-test-suite xfsprogs util-linux build-essential autoconf bison flex libssl-dev mesa-utils || {
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

  if ! command -v phoronix-test-suite &> /dev/null; then
    echo "Installation failed. Please try installing Phoronix Test Suite manually."
    exit 1
  fi
  echo "Phoronix Test Suite installed successfully."
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
    sudo zypper install -y phoronix-test-suite
    sudo zypper install -y xfsprogs util-linux gcc gcc-c++ ${gcc_extra} make autoconf bison flex libopenssl-devel Mesa-demo-x libelf-devel
    if [ "$VERSION_ID" == "15.6" ]
    then
    	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100
	sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100
    fi
}

# === Main Script ===

# Default values
UPLOAD_RESULTS=0
MANUAL_THREADS=0
UPLOAD_ID="quick-benchmark-cpu-$(date +%Y-%m-%d-%H%M%S)"
UPLOAD_NAME="Automated CPU benchmark run with quick-benchmark-cpu.sh"


# === Argument Parsing ===
UPLOAD_RESULTS=0
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--threads)
          MANUAL_THREADS="$2"
          shift 2
          ;;
        -u|--upload)
          UPLOAD_RESULTS=1
          shift
          ;;
        -n|--result-name)
	  UPLOAD_NAME="$2"
	  shift
	  ;;
        -i|--result-id)
	  UPLOAD_ID="$2"
	  shift
	  ;;
        -h|--help)
	  usage;
	  exit 0
	  ;;
        *)
	  echo "Unknown parameter passed: $1"
	  usage
	  exit 1
	  ;;
    esac
    shift
done

# === Check for PTS and install if it's missing ===
if ! command -v phoronix-test-suite &> /dev/null; then
  install_packages
fi

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

# Autodetect CPU resources
echo "--- Detecting CPU Resources ---"
CPU_INFO=$(lscpu)
SOCKETS=$(echo "$CPU_INFO" | grep -i "^socket(s):" | awk '{print $2}')
CORES_PER_SOCKET=$(echo "$CPU_INFO" | grep -i "^core(s) per socket:" | awk '{print $4}')
THREADS_PER_CORE=$(echo "$CPU_INFO" | grep -i "^thread(s) per core:" | awk '{print $4}')
TOTAL_THREADS=$((SOCKETS * CORES_PER_SOCKET * THREADS_PER_CORE))

echo "Sockets:          $SOCKETS"
echo "Cores per socket: $CORES_PER_SOCKET"
echo "Threads per core: $THREADS_PER_CORE"
echo "Total threads:    $TOTAL_THREADS"
echo "--------------------------------"

# Determine the number of threads to use
if [[ "$MANUAL_THREADS" -gt 0 ]]; then
  if [[ "$MANUAL_THREADS" -le "$TOTAL_THREADS" ]]; then
    THREADS_TO_USE="$MANUAL_THREADS"
    echo "Using manually specified thread count: $THREADS_TO_USE"
  else
    echo "Error: The specified number of threads ($MANUAL_THREADS) is greater than the available threads ($TOTAL_THREADS)."
    exit 1
  fi
else
  THREADS_TO_USE="$TOTAL_THREADS"
  echo "Using all available threads: $THREADS_TO_USE"
fi

# Set up PTS environment variables for automated runs
export FORCE_TIMES_TO_RUN=1
export PTS_CONCURRENT_TEST_RUNS="$THREADS_TO_USE"

# Set up PTS environment variables for result uploading
if [[ "$UPLOAD_RESULTS" -eq 1 ]]; then
  export UPLOAD_RESULTS="TRUE"
  export TEST_RESULTS_NAME="$UPLOAD_ID"
  export TEST_RESULTS_DESCRIPTION="$UPLOAD_NAME"
  echo "Results will be uploaded with the following details:"
  echo "  Name: $TEST_RESULTS_NAME"
  echo "  Description: $TEST_RESULTS_DESCRIPTION"
fi

# === Run Tests ===
for TEST_NAME in "${REQUIRED_TESTS[@]}"; do
	echo -e "\n=== Starting CPU Benchmark ==="
	echo "Test profile: $TEST_NAME"
	phoronix-test-suite batch-run "$TEST_NAME" -s "$UPLOAD_ID"
done

echo -e "\n=== Benchmark Complete ==="
