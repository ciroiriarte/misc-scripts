# Misc Sysadmin & Infrastructure Scripts

A collection of Bash scripts to simplify repetitive sysadmin and infrastructure operations.

[![Release](https://img.shields.io/github/v/release/ciroiriarte/misc-scripts)](https://github.com/ciroiriarte/misc-scripts/releases/latest)
[![License: GPL v3](https://img.shields.io/github/license/ciroiriarte/misc-scripts)](LICENSE)
[![Shell](https://img.shields.io/badge/language-Bash-green)](https://www.gnu.org/software/bash/)

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Getting Started](#-getting-started)
- [Scripts](#-scripts)
  - [memory-usage-report-kvm.sh](#-memory-usage-report-kvmsh)
  - [memory-usage-report-esxi.sh](#-memory-usage-report-esxish)
  - [memory-usage-report-openstack.sh](#-memory-usage-report-openstacksh)
  - [os-import-cloud-images.sh](#-os-import-cloud-imagessh)
  - [create-ssl-csr.sh](#-create-ssl-csrsh)
  - [guacamole-reset-user-otp.sh](#-guacamole-reset-user-otpsh)
- [Documentation](#-documentation)
- [Related Projects](#-related-projects)
- [Contributing](#-contributing)
- [License](#-license)
- [Author](#-author)

---

## 🔍 Overview

| Script | Version | Created | Updated |
|---|---|---|---|
| `memory-usage-report-kvm.sh` | ![v2.4](https://img.shields.io/badge/version-2.4-blue) | 2025-09-11 | 2026-02-27 |
| `memory-usage-report-esxi.sh` | ![v1.2](https://img.shields.io/badge/version-1.2-blue) | 2025-09-11 | 2026-02-27 |
| `memory-usage-report-openstack.sh` | ![v0.2](https://img.shields.io/badge/version-0.2-orange) | 2025-12-24 | 2026-02-27 |
| `os-import-cloud-images.sh` | ![v1.0](https://img.shields.io/badge/version-1.0-blue) | 2026-03-12 | 2026-03-12 |
| `create-ssl-csr.sh` | ![v1.1](https://img.shields.io/badge/version-1.1-blue) | 2025-06-06 | 2026-02-27 |
| `guacamole-reset-user-otp.sh` | ![v1.0](https://img.shields.io/badge/version-1.0-blue) | 2021-11-02 | 2026-02-27 |

All scripts support `--version` / `-v` and `--help` / `-h` flags.

---

## 🚀 Getting Started

### Prerequisites

- Bash (modern version with associative array support)
- Script-specific dependencies are listed in each script section below

### Installation

Clone the repository:

```bash
git clone https://github.com/ciroiriarte/misc-scripts.git
cd misc-scripts
```

Scripts are standalone and can be run directly or copied to a directory in your `PATH`:

```bash
chmod +x <script-name>.sh
cp <script-name>.sh /usr/local/bin/
```

---

## 📜 Scripts

### 🔍 `memory-usage-report-kvm.sh`

Provides a comprehensive KVM host memory usage and optimization summary. It reports:

- Host total, available, and used memory
- Per-VM memory allocation (max, current, guest used, guest free)
- Per-VM guest swap activity (swap in/out)
- KSM (Kernel Same-page Merging) savings
- Host-level configuration (hugepages, overcommit settings)
- Optional baseline comparison for tracking memory changes over time

Supports **table** (default), **CSV**, and **JSON** output formats.

#### ⚙️ Requirements

- Must be run as **root**
- Required tools:
  - `virsh` (libvirt)
  - `bc`, `getconf`, `free`, `sysctl`
  - `awk`, `grep`

#### 💡 Recommendations

- Run on a KVM host with libvirt installed and VMs running for meaningful output.
- Create a memory baseline for future comparisons:
  ```bash
  (echo "# Recorded on: $(date)"; free -m) > /var/log/mem_baseline.txt
  ```

#### 🚀 Usage

```bash
# Run the report (table format)
sudo ./memory-usage-report-kvm.sh

# CSV output (VM table)
sudo ./memory-usage-report-kvm.sh --output csv

# JSON output (full report)
sudo ./memory-usage-report-kvm.sh --output json

# Display version
sudo ./memory-usage-report-kvm.sh --version
```

---

### 🔍 `memory-usage-report-esxi.sh`

Reports memory usage and optimization metrics for ESXi hosts and virtual machines. It uses native ESXi tools to extract host memory, per-VM allocation, and advanced metrics like ballooning, swapping, compression, and shared memory.

Supports **table** (default), **CSV**, and **JSON** output formats.

#### ⚙️ Requirements

- Must be run directly on the **ESXi host** (via SSH or shell)
- Required tools:
  - `vsish`
  - `vim-cmd`
  - `awk`, `grep`, `sed`

#### 💡 Recommendations

- Ensure SSH access is enabled on the ESXi host.
- Review ballooning and swap metrics to identify memory pressure on VMs.

#### 🚀 Usage

```bash
# Run the report from the ESXi shell
./memory-usage-report-esxi.sh

# CSV output (VM table)
./memory-usage-report-esxi.sh --output csv

# JSON output (full report)
./memory-usage-report-esxi.sh --output json

# Display version
./memory-usage-report-esxi.sh --version
```

---

### 🔍 `memory-usage-report-openstack.sh`

Provides an accurate summary of OpenStack resources per domain, with a per-project breakdown. It reports:

- Instance count per project
- vCPU and RAM allocation per project
- Volume count and total volume size per project
- Domain-wide totals

#### ⚙️ Requirements

- Required tools:
  - `openstack` CLI (configured with admin or domain admin scope)
  - `jq`
- A sourced OpenStack credentials file (e.g., `openrc.sh`)

#### 💡 Recommendations

- Source your OpenStack credentials before running:
  ```bash
  source ~/openrc.sh
  ```
- For large domains with many projects, execution may take time due to API queries per project and server.

#### 🚀 Usage

```bash
# Summarize resources for a specific domain
./memory-usage-report-openstack.sh my-domain

# Display version
./memory-usage-report-openstack.sh --version

# Display help
./memory-usage-report-openstack.sh --help
```

---

### 🔍 `os-import-cloud-images.sh`

Imports upstream cloud images into OpenStack Glance with standardized metadata properties optimized for virtio/UEFI/q35 environments. Dynamically discovers the latest releases from distribution mirrors, optionally customizes them, converts to the target disk format, and uploads with full Glance metadata.

Supported distributions: **Debian**, **Ubuntu LTS**, **Rocky Linux** (plain and LVM), **openSUSE Leap**, **Oracle Linux**.

Default disk format is **raw** (recommended for Ceph RBD backends).

#### ⚙️ Requirements

- Required tools:
  - `openstack` CLI (python-openstackclient, configured with admin credentials)
  - `qemu-img` (qemu-utils / qemu-tools)
  - `jq`
  - `curl` or `wget`
- Optional:
  - `virt-customize` (libguestfs-tools) — for image customization (see below)
- A sourced OpenStack credentials file (e.g., `openrc.sh`)

#### 🔧 Per-Distribution Customizations

When `virt-customize` is available (and `--no-customize` is not used), the following customizations are applied:

| Distribution | Customization | Details |
|---|---|---|
| Debian, Ubuntu | `guest-agent` | Installs `qemu-guest-agent` package (not included by default) |
| openSUSE Leap | `ptp-fix` | Injects `/etc/modules-load.d/ptp_kvm.conf` to load the `ptp_kvm` kernel module |
| Rocky Linux (LVM) | `lvm-pvresize` | Injects a cloud-init bootcmd (`/etc/cloud/cloud.cfg.d/99-pvresize.cfg`) that runs `pvresize` on all PVs at every boot, so the VG gains free space after a volume resize. LV allocation (`lvresize`/`lvcreate`) is left to the user. |
| Rocky Linux, Oracle Linux | — | No customization needed (guest-agent already included) |

All customized images have `/etc/machine-id` truncated to avoid duplicate IDs on clone.

#### 📋 Glance Image Properties

Every imported image is tagged with standardized hardware metadata:

| Property | Value | Purpose |
|---|---|---|
| `os_type` | `linux` | OS family |
| `hw_machine_type` | `q35` | Modern PCIe-native machine type |
| `hw_firmware_type` | `uefi` | UEFI boot |
| `hw_scsi_model` | `virtio-scsi` | Paravirtualized SCSI controller |
| `hw_disk_bus` | `scsi` | Disk attached via virtio-scsi |
| `hw_vif_model` | `virtio` | Paravirtualized NIC |
| `hw_vif_multiqueue_enabled` | `true` | Multi-queue for better network throughput |
| `hw_virtio_packed_ring` | `true` | Packed virtqueue for lower overhead |
| `hw_video_model` | `virtio` | Paravirtualized GPU |
| `hw_serial_port_count` | `1` | Serial console access |
| `hw_qemu_guest_agent` | `true` | Enables guest agent communication |
| `os_require_quiesce` | `true` | Quiesced snapshots for consistent backups |
| `hw_require_fsfreeze` | `true` | Filesystem freeze before snapshots |

Per-distribution properties are also set: `os_distro`, `os_version`, `os_admin_user`, `has_auto_disk_config`, and `os_license`.

| Distribution | `os_distro` | `os_admin_user` | `has_auto_disk_config` | `os_license` |
|---|---|---|---|---|
| Debian | `debian` | `debian` | `true` | `opensource` |
| Ubuntu | `ubuntu` | `ubuntu` | `true` | `opensource` |
| Rocky Linux | `rocky` | `rocky` | `true` | `opensource` |
| Rocky Linux (LVM) | `rocky` | `rocky` | `false` | `opensource` |
| openSUSE Leap | `opensuse` | `opensuse` | `true` | `opensource` |
| Oracle Linux | `oel` | `oracle` | `false` | `opensource` |

The `os_license` property defaults to `opensource` for all discovered distributions and can be overridden with `--os-license` (e.g. `--os-license rhel` for RHEL images).

#### 💡 Recommendations

- Source your OpenStack credentials before running:
  ```bash
  source ~/openrc.sh
  ```
- Use `raw` disk format (default) when your Glance backend is Ceph RBD to leverage copy-on-write cloning.
- Use `--no-customize` if guest-agent installation will be handled via cloud-init user-data instead.
- For LVM images, after booting a VM with a larger volume, the PV is already resized. Use `vgs` to see free space, then `lvresize`/`lvcreate` as needed.

#### 🚀 Usage

```bash
# List available images
./os-import-cloud-images.sh -l

# Interactive selection
./os-import-cloud-images.sh -i

# Import all images in batch
./os-import-cloud-images.sh -b

# Import Debian images only
./os-import-cloud-images.sh -b -d debian

# Import as private images
./os-import-cloud-images.sh -b --visibility private

# Use qcow2 format (non-Ceph backends)
./os-import-cloud-images.sh -b -f qcow2

# Override os_license property
./os-import-cloud-images.sh -b --os-license rhel

# Dry run
./os-import-cloud-images.sh -n -b

# Display version
./os-import-cloud-images.sh --version

# Display help
./os-import-cloud-images.sh --help
```

---

### 🔍 `create-ssl-csr.sh`

Helps create an SSL Certificate Signing Request (CSR) to be shared with a Certificate Authority. It generates a private key and CSR based on configurable variables defined in the script. Optionally, it can generate a CA certificate or a self-signed certificate.

#### ⚙️ Requirements

- Required tools:
  - `openssl`

#### 💡 Recommendations

- Edit the configuration variables at the top of the script (`SITE`, `ORGDOMAIN`, `COUNTRY`, `STATE`, etc.) to match your environment before running.

#### 🚀 Usage

```bash
# Generate a standard CSR
./create-ssl-csr.sh

# Generate a CA certificate signing request
./create-ssl-csr.sh --ca

# Generate a self-signed certificate
./create-ssl-csr.sh --self-signed

# Generate a self-signed CA certificate
./create-ssl-csr.sh --ca --self-signed

# Display version
./create-ssl-csr.sh --version

# Display help
./create-ssl-csr.sh --help
```

---

### 🔍 `guacamole-reset-user-otp.sh`

Resets the TOTP (Time-based One-Time Password) enrollment for a specified user in Apache Guacamole. After running, the user will need to re-enroll their OTP device on next login.

#### ⚙️ Requirements

- Required tools:
  - `mysql` (MySQL/MariaDB client)
- A working Guacamole database with the native TOTP module enabled
- Database credentials configured in `~/.my.cnf` or edited directly in the script

#### 🚀 Usage

```bash
# Reset OTP for a specific user
./guacamole-reset-user-otp.sh ciro.iriarte

# Display version
./guacamole-reset-user-otp.sh --version

# Display help
./guacamole-reset-user-otp.sh --help
```

---

## 📖 Documentation

Man pages are available under `man/man1/` for detailed reference.

**Preview locally** (no installation required):

```bash
man -l man/man1/memory-usage-report-kvm.1
```

**Install system-wide:**

```bash
sudo make install-man
```

After installation, use `man <script-name>` to view the man page (e.g., `man memory-usage-report-kvm`).

**Uninstall:**

```bash
sudo make uninstall-man
```

---

## 🔗 Related Projects

| Project | Description |
|---|---|
| [nic-xray](https://github.com/ciroiriarte/nic-xray) | Network interface diagnostics tool (formerly part of this repository) |

---

## 🤝 Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

---

## 👤 Author

**Ciro Iriarte** &mdash; [GitHub](https://github.com/ciroiriarte)
