#!/bin/bash

# === Configuration ===
TESTUSER=$(whoami)

# === List of Disks (device;label) ===
DISKS=(
    "/dev/vdb;NVMe_Replica3"
    "/dev/vdc;NVMe_EC32"
    "/dev/vdd;HDD_Replica3"
    "/dev/vde;HDD_EC32"
)

# === Detect OS and Install Packages ===
install_packages() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            rocky|rhel|centos)
                echo "Detected Rocky Linux or RHEL-based system"
                sudo dnf install -y epel-release
                sudo dnf install -y phoronix-test-suite xfsprogs
                ;;
            ubuntu|debian)
                echo "Detected Ubuntu or Debian-based system"
                sudo apt update
                sudo apt install -y phoronix-test-suite xfsprogs || {
                    echo "Installing Phoronix Test Suite from .deb package..."
                    wget https://phoronix-test-suite.com/releases/repo/pts.debian/files/phoronix-test-suite_10.8.3_all.deb
                    sudo dpkg -i phoronix-test-suite_10.8.3_all.deb
                    sudo apt-get install -f
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
    case "$VERSION_ID" in
        *Tumbleweed*)
            echo "Adding benchmark repo for Tumbleweed..."
            sudo zypper ar -f https://download.opensuse.org/repositories/benchmark/openSUSE_Tumbleweed benchmark
            ;;
        *Slowroll*)
            echo "Adding benchmark repo for Slowroll..."
            sudo zypper ar -f https://download.opensuse.org/repositories/benchmark/openSUSE_Slowroll benchmark
            ;;
        "15.6")
            echo "Adding benchmark repo for Leap 15.6..."
            sudo zypper ar -f https://download.opensuse.org/repositories/benchmark/15.6/ benchmark
            ;;
        *)
            echo "Unknown openSUSE version: $VERSION_ID"
            exit 1
            ;;
    esac
    sudo zypper refresh
    sudo zypper install -y phoronix-test-suite xfsprogs
}

install_packages

# === Configure Batch Mode ===
phoronix-test-suite batch-setup <<EOF
Y
Y
N
N
N
EOF

# === Install Required Phoronix Tests ===
REQUIRED_TESTS=("iozone" "fio" "postmark" "compilebench")

for test in "${REQUIRED_TESTS[@]}"; do
    echo "Installing test: $test"
    phoronix-test-suite install $test
done

# === Prepare Disks ===
prepare_disk() {
    local disk_entry=$1
    local device=$(echo $disk_entry | cut -d';' -f1)
    local label=$(echo $disk_entry | cut -d';' -f2)
    local mount_point="/mnt/${label}"

    echo "Preparing $device as $label..."

    sudo umount $device 2>/dev/null
    sudo mkfs.xfs -f -L $label $device
    sudo mkdir -p $mount_point
    sudo mount LABEL=$label $mount_point
    sudo chown $TESTUSER:$TESTUSER $mount_point
}

for disk in "${DISKS[@]}"; do
    prepare_disk "$disk"
done

# === Run Tests on Each Disk ===
RESULT_NAMES=()

run_tests_on_disk() {
    local disk_entry=$1
    local label=$(echo $disk_entry | cut -d';' -f2)
    local mount_point="/mnt/${label}"

    for test in "${REQUIRED_TESTS[@]}"; do
        echo "Running $test on $label..."
        phoronix-test-suite batch-run $test

        local result_dir=$(ls -td ~/.phoronix-test-suite/test-results/*${test}* 2>/dev/null | head -n 1)
        if [ -d "$result_dir" ]; then
            local result_name="${label}_${test}_result"
            mv "$result_dir" ~/.phoronix-test-suite/test-results/$result_name
            RESULT_NAMES+=("$result_name")
        else
            echo "Warning: No result found for $test on $label"
        fi
    done
}

for disk in "${DISKS[@]}"; do
    run_tests_on_disk "$disk"
done

# === Compare Results Per Test ===
echo "Comparing results..."
for test in "${REQUIRED_TESTS[@]}"; do
    echo "=== Comparison for $test ==="
    phoronix-test-suite compare-results $(ls ~/.phoronix-test-suite/test-results | grep "_${test}_result" | tr '\n' ' ')
done
