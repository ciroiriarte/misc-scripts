# Misc Sysadmin & Infrastructure Scripts

A collection of Bash scripts to simplify repetitive sysadmin and infrastructure operations.

## 📦 Latest Release: [v2.0](https://github.com/ciroiriarte/misc-scripts/releases/tag/v2.0)

| Script | Version |
|---|---|
| `nic-xray.sh` | 1.3 |
| `memory-usage-report-kvm.sh` | 2.4 |
| `memory-usage-report-esxi.sh` | 1.2 |
| `memory-usage-report-openstack.sh` | 0.2 |
| `create-ssl-csr.sh` | 1.1 |
| `guacamole-reset-user-otp.sh` | 1.0 |

All scripts support `--version` / `-v` and `--help` / `-h` flags.

---

## 📖 Man Pages

Man pages are available under `man/man1/` for detailed reference.

**Preview locally** (no installation required):

```bash
man -l man/man1/nic-xray.1
```

**Install system-wide:**

```bash
sudo make install-man
```

After installation, use `man nic-xray` to view the man page.

**Uninstall:**

```bash
sudo make uninstall-man
```

---

## 🔍 `guacamole-reset-user-otp.sh`

**Author**: Ciro Iriarte
**Created**: 2021-11-02
**Updated**: 2026-02-27

### 📝 Description

`guacamole-reset-user-otp.sh` resets the TOTP (Time-based One-Time Password) enrollment for a specified user in Apache Guacamole. After running, the user will need to re-enroll their OTP device on next login.

---

### ⚙️ Requirements

- Required tools:
  - `mysql` (MySQL/MariaDB client)
- A working Guacamole database with the native TOTP module enabled
- Database credentials configured in `~/.my.cnf` or edited directly in the script

---

### 🚀 Usage

Reset OTP for a specific user:

```bash
./guacamole-reset-user-otp.sh ciro.iriarte
```

Display version:

```bash
./guacamole-reset-user-otp.sh --version
```

Display help:

```bash
./guacamole-reset-user-otp.sh --help
```

---

## 🔍 `nic-xray.sh`

**Author**: Ciro Iriarte
**Created**: 2025-06-05
**Updated**: 2026-02-27

### 📝 Description

`nic-xray.sh` is a diagnostic script that provides a detailed overview of all **physical network interfaces** on a Linux system. It displays:

- PCI slot
- Firmware version
- Interface name
- MAC address
- MTU
- Link status (with color)
- Negotiated speed and duplex (color-coded by tier: 200G magenta, 100G cyan, 25G/40G/50G white, 10G green, 1G yellow, <1G/unknown red)
- Bond membership (with color)
- LLDP peer information (switch and port)
- Optionally: LACP status, VLAN tagging, bond MAC address

Supports multiple output formats: **table** (default, with dynamic column widths), **CSV**, and **JSON**.

Originally developed for OpenStack node deployments, it is suitable for any Linux environment.

---

### ⚙️ Requirements

- Must be run as **root**
- Required tools:
  - `ethtool`
  - `lldpctl`
  - `ip`, `awk`, `grep`, `cat`, `readlink`
- Switch configuration:
  - Switch should advertise LLDP messages
  - Cisco doesn't include VLAN information by default.
    Hint:
    ```bash
    lldp tlv-select vlan-name
    ```

---

### 💡 Recommendations

- Copy the script to `/usr/local/sbin` for easy access:
  ```bash
  sudo cp nic-xray.sh /usr/local/sbin/
  sudo chmod +x /usr/local/sbin/nic-xray.sh
  ```

- Ensure lldpd service is running to retrieve LLDP information:
  ```bash
  sudo systemctl enable --now lldpd
  ```

---

### 🚀 Usage

Default view:

```bash
sudo nic-xray.sh
```

Show VLAN information:

```bash
sudo nic-xray.sh --vlan
```

Show LACP peer information:

```bash
sudo nic-xray.sh --lacp
```

Show bond MAC address:

```bash
sudo nic-xray.sh --bmac
```

Table output with `│` column separators:

```bash
sudo nic-xray.sh -s
sudo nic-xray.sh --separator
```

Table output with a custom separator:

```bash
sudo nic-xray.sh --separator='|'
```

CSV output:

```bash
sudo nic-xray.sh --output csv
```

Pipe-delimited CSV:

```bash
sudo nic-xray.sh --output csv --separator='|'
```

Tab-separated CSV:

```bash
sudo nic-xray.sh --output csv --separator=$'\t'
```

JSON output:

```bash
sudo nic-xray.sh --output json
```

All optional columns with JSON output:

```bash
sudo nic-xray.sh --vlan --lacp --bmac --output json
```

Group rows by bond (bonded interfaces first, then unbonded):

```bash
sudo nic-xray.sh --group-bond
sudo nic-xray.sh --group-bond --lacp -s
```

Display version:

```bash
sudo nic-xray.sh -v
sudo nic-xray.sh --version
```

Display help:

```bash
sudo nic-xray.sh -h
sudo nic-xray.sh --help
```

---

## 🔍 `create-ssl-csr.sh`

**Author**: Ciro Iriarte
**Created**: 2025-06-06
**Updated**: 2026-02-27

### 📝 Description

`create-ssl-csr.sh` helps create an SSL Certificate Signing Request (CSR) to be shared with a Certificate Authority. It generates a private key and CSR based on configurable variables defined in the script. Optionally, it can generate a CA certificate or a self-signed certificate.

---

### ⚙️ Requirements

- Required tools:
  - `openssl`

---

### 💡 Recommendations

- Edit the configuration variables at the top of the script (`SITE`, `ORGDOMAIN`, `COUNTRY`, `STATE`, etc.) to match your environment before running.

---

### 🚀 Usage

Generate a standard CSR:

```bash
./create-ssl-csr.sh
```

Generate a CA certificate signing request:

```bash
./create-ssl-csr.sh --ca
```

Generate a self-signed certificate:

```bash
./create-ssl-csr.sh --self-signed
```

Generate a self-signed CA certificate:

```bash
./create-ssl-csr.sh --ca --self-signed
```

Display version:

```bash
./create-ssl-csr.sh --version
```

Display help:

```bash
./create-ssl-csr.sh --help
```

---

## 🔍 `memory-usage-report-kvm.sh`

**Author**: Ciro Iriarte
**Created**: 2025-09-11
**Updated**: 2026-02-27

### 📝 Description

`memory-usage-report-kvm.sh` provides a comprehensive KVM host memory usage and optimization summary. It reports:

Supports **table** (default), **CSV**, and **JSON** output formats.

- Host total, available, and used memory
- Per-VM memory allocation (max, current, guest used, guest free)
- Per-VM guest swap activity (swap in/out)
- KSM (Kernel Same-page Merging) savings
- Host-level configuration (hugepages, overcommit settings)
- Optional baseline comparison for tracking memory changes over time

---

### ⚙️ Requirements

- Must be run as **root**
- Required tools:
  - `virsh` (libvirt)
  - `bc`, `getconf`, `free`, `sysctl`
  - `awk`, `grep`

---

### 💡 Recommendations

- Run on a KVM host with libvirt installed and VMs running for meaningful output.
- Create a memory baseline for future comparisons:
  ```bash
  (echo "# Recorded on: $(date)"; free -m) > /var/log/mem_baseline.txt
  ```

---

### 🚀 Usage

Run the report:

```bash
sudo ./memory-usage-report-kvm.sh
```

CSV output (VM table):

```bash
sudo ./memory-usage-report-kvm.sh --output csv
```

JSON output (full report):

```bash
sudo ./memory-usage-report-kvm.sh --output json
```

Display version:

```bash
sudo ./memory-usage-report-kvm.sh --version
```

---

## 🔍 `memory-usage-report-esxi.sh`

**Author**: Ciro Iriarte
**Created**: 2025-09-11
**Updated**: 2026-02-27

### 📝 Description

`memory-usage-report-esxi.sh` reports memory usage and optimization metrics for ESXi hosts and virtual machines. It uses native ESXi tools to extract host memory, per-VM allocation, and advanced metrics like ballooning, swapping, compression, and shared memory.

Supports **table** (default), **CSV**, and **JSON** output formats.

---

### ⚙️ Requirements

- Must be run directly on the **ESXi host** (via SSH or shell)
- Required tools:
  - `vsish`
  - `vim-cmd`
  - `awk`, `grep`, `sed`

---

### 💡 Recommendations

- Ensure SSH access is enabled on the ESXi host.
- Review ballooning and swap metrics to identify memory pressure on VMs.

---

### 🚀 Usage

Run the report from the ESXi shell:

```bash
./memory-usage-report-esxi.sh
```

CSV output (VM table):

```bash
./memory-usage-report-esxi.sh --output csv
```

JSON output (full report):

```bash
./memory-usage-report-esxi.sh --output json
```

Display version:

```bash
./memory-usage-report-esxi.sh --version
```

---

## 🔍 `memory-usage-report-openstack.sh`

**Author**: Ciro Iriarte
**Created**: 2025-12-24
**Updated**: 2026-02-27

### 📝 Description

`memory-usage-report-openstack.sh` provides an accurate summary of OpenStack resources per domain, with a per-project breakdown. It reports:

- Instance count per project
- vCPU and RAM allocation per project
- Volume count and total volume size per project
- Domain-wide totals

---

### ⚙️ Requirements

- Required tools:
  - `openstack` CLI (configured with admin or domain admin scope)
  - `jq`
- A sourced OpenStack credentials file (e.g., `openrc.sh`)

---

### 💡 Recommendations

- Source your OpenStack credentials before running:
  ```bash
  source ~/openrc.sh
  ```
- For large domains with many projects, execution may take time due to API queries per project and server.

---

### 🚀 Usage

Summarize resources for a specific domain:

```bash
./memory-usage-report-openstack.sh my-domain
```

Display version:

```bash
./memory-usage-report-openstack.sh --version
```

Display help:

```bash
./memory-usage-report-openstack.sh --help
```
