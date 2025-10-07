#!/bin/bash
#
# Script Name: create-csr.sh
# Description: This script builds a CSR file to be sent to a CA.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Created: 2025-06-06
#
# Requirements:
#   - Requires: openssl
#
# Change Log:
#   - 2025-06-06: Initial version
#   - 2025-10-07: Add CA option
#                 Add self signed option

# === Configuration ===
SITE="site1"                 # Replace with your site identifier
ORGDOMAIN="my.corp"          # Replace with your organization domain
COUNTRY="PY"                 # 2-letter country code
STATE="Central"              # Full state name
LOCALITY="Asuncion"          # City
ORG="Super Corp"             # Organization name
ORG_UNIT="IT Infra"          # Organizational unit
EMAIL="admin@${ORGDOMAIN}"   # Contact email
DAYS_VALID=365               # Certificate validity in days (for optional self-signed cert)
IS_CA=false                  # Default: not a CA
IS_SELF_SIGNED=false  # Default: do not generate self-signed certificate


# === Parse Arguments ===
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ca) IS_CA=true ;;
        --self-signed) IS_SELF_SIGNED=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# === Derived Variables ===
FQDN="thesite.oam.${SITE}.platform.${ORGDOMAIN}"
KEY_FILE="${FQDN}.key"
CSR_FILE="${FQDN}.csr"
CONFIG_FILE="${FQDN}_csr.conf"
CERT_FILE="${FQDN}.crt"           # Optional: for self-signed cert

# === Generate OpenSSL Config ===
if [ "${IS_CA}" = true ]
then
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

# === Generate Private Key and CSR ===
openssl req -new -newkey rsa:2048 -nodes -keyout "$KEY_FILE" -out "$CSR_FILE" -config "$CONFIG_FILE"

# === Generate Self-Signed Certificate if requested ===
if [ "${IS_SELF_SIGNED}" = true ]; then
    openssl x509 -req -days "$DAYS_VALID" -in "$CSR_FILE" -signkey "$KEY_FILE" -out "$CERT_FILE" -extensions req_ext -extfile "$CONFIG_FILE"
    echo "✅ Self-signed certificate generated: $CERT_FILE"
fi

echo "✅ Key and CSR generated:"
echo "  - Key: $KEY_FILE"
echo "  - CSR: $CSR_FILE"
