## 🔍 `guacamole-reset-user-otp.sh`

**Author**: Ciro Iriarte  
**Created**: 2021-11-02 
**Updated**: 2021-11-02  

### 📝 Description

`guacamole-reset-user-otp.sh` is a quick script to disable OTP for a user for Guacamole (using native OTP module)

### 🚀 Usage

Default view

```bash
guacamole-reset-user-otp.sh the.user
  ```

## 🔍 `nic-xray.sh`

**Author**: Ciro Iriarte  
**Created**: 2025-06-05  
**Updated**: 2025-06-07  

### 📝 Description

`nic-xray.sh` is a diagnostic script that provides a detailed overview of all **physical network interfaces** on a Linux system. It displays:

- PCI slot
- Firmware version
- Interface name
- MAC address
- MTU
- Link status (with color)
- Negotiated speed and duplex
- Bond membership (with color)
- LLDP peer information (switch and port)

Originally developed for OpenStack node deployments, it is suitable for any Linux environment.

---

### ⚙️ Requirements

- Must be run as **root**
- Required tools:
  - `ethtool`
  - `lldpctl`
  - `awk`, `grep`, `cat`, `readlink`
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

Default view

```bash
sudo nic-xray.sh
  ```

Show VLAN information

```bash
sudo nic-xray.sh --vlan
```

Show LACP peer information

```bash
sudo nic-xray.sh --lacp
```

---

### 📤 Output Example

```bash
echo "Sorry, can't share"
```

## 🔍 `create-ssl-csr.sh`
**Author**: Ciro Iriarte
**Created**: 2025-06-06
**Updated**: 2025-06-06

### 📝 Description

`create-ssl-csr.sh`Helps to create a SSL Certificate Signing Request to be shared with a CA entity.

---

### ⚙️ Requirements

- Required tools:
  - `openssl`

---

### 🚀 Usage

Edit the variables to match your environment and run the script.

```bash
./create-ssl-csr.sh
```

## 🔍 `kvm-memory-usage-report.sh`
**Author**: Ciro Iriarte  
**Created**: 2025-09-10  
**Updated**: 2025-09-10  

## 📝 Description

Reports memory usage for KVM-based virtual machines using `virsh`. It provides host memory usage, per-VM allocation, and total memory consumption.

---

## ⚙️ Requirements

- Required tools:
  - `virsh`
  - `awk`, `grep`, `sed`

---

## 🚀 Usage

Run the script on a KVM host with libvirt installed:

```bash
./kvm-memory-usage-report.sh
```

## 🔍 `esxi-memory-usage-report.sh`
**Author**: Ciro Iriarte  
**Created**: 2025-09-10  
**Updated**: 2025-09-10  

### 📝 Description

Reports memory usage and optimization metrics for ESXi hosts and virtual machines. Uses native ESXi tools to extract host memory, per-VM allocation, and advanced metrics like ballooning, swapping, compression, and shared memory.

### ⚙️ Requirements

- Must be run directly on the ESXi host (via SSH or shell)
- Required tools:
  - `virsh`
  - `awk`, `grep`, `sed`

---

### 🚀 Usage

Run the script from the ESXi shell:

```bash
./esxi-memory-usage-report.sh
```
