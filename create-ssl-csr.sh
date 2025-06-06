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

# === Configuration ===
SITE="site1"                     # Replace with your site identifier
ORGDOMAIN="my.corp"           # Replace with your organization domain
COUNTRY="PY"                      # 2-letter country code
STATE="Central"                # Full state name
LOCALITY="Asuncion"          # City
ORG="Super Corp"                # Organization name
ORG_UNIT="IT Infra"          # Organizational unit
EMAIL="admin@${ORGDOMAIN}"        # Contact email
DAYS_VALID=365                    # Certificate validity in days (for optional self-signed cert)

# === Derived Variables ===
FQDN="thesite.oam.${SITE}.platform.${ORGDOMAIN}"
KEY_FILE="${FQDN}.key"
CSR_FILE="${FQDN}.csr"
CONFIG_FILE="${FQDN}_csr.conf"
CERT_FILE="${FQDN}.crt"           # Optional: for self-signed cert

# === Generate OpenSSL Config ===
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

[ alt_names ]
DNS.1 = ${FQDN}
EOF

# === Generate Private Key and CSR ===
openssl req -new -newkey rsa:2048 -nodes -keyout "$KEY_FILE" -out "$CSR_FILE" -config "$CONFIG_FILE"

# === Optional: Generate Self-Signed Certificate ===
# openssl x509 -req -days "$DAYS_VALID" -in "$CSR_FILE" -signkey "$KEY_FILE" -out "$CERT_FILE" -extensions req_ext -extfile "$CONFIG_FILE"

echo "✅ Key and CSR generated:"
echo "  - Key: $KEY_FILE"
echo "  - CSR: $CSR_FILE"
# echo "  - Self-signed cert: $CERT_FILE"
