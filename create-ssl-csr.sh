#!/usr/bin/env bash

# Script Name: create-ssl-csr.sh
# Description: Generates a private key and CSR file to be sent to a CA.
#              Optionally generates a self-signed certificate.
#
# Author: Ciro Iriarte <ciro.iriarte+software@gmail.com>
# Created: 2025-06-06
# Version: 1.1
#
# Requirements:
#   - openssl
#
# Changelog:
#   - 2025-06-06: v1.0 - Initial version.
#   - 2025-10-07: v1.1 - Added CA and self-signed options.

# --- Configuration ---
SCRIPT_VERSION="1.1"
SITE="site1"                 # Replace with your site identifier
ORGDOMAIN="my.corp"          # Replace with your organization domain
COUNTRY="PY"                 # 2-letter country code
STATE="Central"              # Full state name
LOCALITY="Asuncion"          # City
ORG="Super Corp"             # Organization name
ORG_UNIT="IT Infra"          # Organizational unit
EMAIL="admin@${ORGDOMAIN}"   # Contact email
DAYS_VALID=365               # Certificate validity in days
IS_CA=false                  # Default: not a CA
IS_SELF_SIGNED=false         # Default: do not generate self-signed certificate

# --- Functions ---

show_help() {
    echo "Usage: $0 [-h|--help] [-v|--version] [--ca] [--self-signed]"
    echo ""
    echo "Version: $SCRIPT_VERSION"
    echo ""
    echo "Description:"
    echo " Generates a private key and CSR file to be sent to a CA."
    echo " Optionally generates a self-signed certificate."
    echo ""
    echo "Options:"
    echo " -h, --help        Display this help message"
    echo " -v, --version     Display version information"
    echo " --ca              Generate a CA certificate (sets keyUsage to keyCertSign, cRLSign)"
    echo " --self-signed     Also generate a self-signed certificate"
    echo ""
    echo "Example:"
    echo " $0 --self-signed"
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -v|--version)
            echo "$0 $SCRIPT_VERSION"
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --ca)
            IS_CA=true
            ;;
        --self-signed)
            IS_SELF_SIGNED=true
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
        *)
            echo "Error: Unexpected argument: $1" >&2
            show_help >&2
            exit 1
            ;;
    esac
    shift
done

# --- Derived Variables ---
FQDN="thesite.oam.${SITE}.platform.${ORGDOMAIN}"
KEY_FILE="${FQDN}.key"
CSR_FILE="${FQDN}.csr"
CONFIG_FILE="${FQDN}_csr.conf"
CERT_FILE="${FQDN}.crt"

# --- Generate OpenSSL Config ---
if [[ "${IS_CA}" = true ]]; then
    KEY_USAGE="keyCertSign, cRLSign"
else
    KEY_USAGE="nonRepudiation, digitalSignature, keyEncipherment"
fi

cat > "$CONFIG_FILE" <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[ dn ]
C  = ${COUNTRY}
ST = ${STATE}
L  = ${LOCALITY}
O  = ${ORG}
OU = ${ORG_UNIT}
CN = ${FQDN}
emailAddress = ${EMAIL}

[ req_ext ]
subjectAltName = @alt_names
basicConstraints = CA:${IS_CA}
keyUsage = ${KEY_USAGE}

[ alt_names ]
DNS.1 = ${FQDN}
EOF

# --- Generate Private Key and CSR ---
openssl req -new -newkey rsa:2048 -nodes -keyout "$KEY_FILE" -out "$CSR_FILE" -config "$CONFIG_FILE"

# --- Generate Self-Signed Certificate (if requested) ---
if [[ "${IS_SELF_SIGNED}" = true ]]; then
    openssl x509 -req -days "$DAYS_VALID" -in "$CSR_FILE" -signkey "$KEY_FILE" -out "$CERT_FILE" -extensions req_ext -extfile "$CONFIG_FILE"
    echo "✅ Self-signed certificate generated: $CERT_FILE"
fi

echo "✅ Key and CSR generated:"
echo "  - Key: $KEY_FILE"
echo "  - CSR: $CSR_FILE"
