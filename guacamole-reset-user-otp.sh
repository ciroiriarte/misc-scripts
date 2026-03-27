#!/usr/bin/env bash

# Script Name: guacamole-reset-user-otp.sh
# Description: Resets the TOTP (OTP) enrollment for a Guacamole user,
#              forcing them to re-enroll on next login.
#
# Author: Ciro Iriarte <ciro.iriarte+software@gmail.com>
# Created: 2021-11-02
# Version: 1.0
#
# Changelog:
#   - 2021-11-02: v1.0 - Initial version.

# --- Configuration ---
SCRIPT_VERSION="1.0"
DBNAME="guacamole"
DBUSER="guacamoleuser"
DBPASS="you.wish"
# Command to be used if credentials are defined at ~/.my.cnf (my preference)
DBCMD="mysql"
# Command to be used if credentials are defined in this script
#DBCMD="mysql --user=$DBUSER --password=$DBPASS"

# --- Functions ---

show_help() {
    echo "Usage: $0 [-h|--help] [-v|--version] <username>"
    echo ""
    echo "Version: $SCRIPT_VERSION"
    echo ""
    echo "Description:"
    echo " Resets the TOTP (OTP) enrollment for a Guacamole user."
    echo " The user will need to re-enroll on next login."
    echo ""
    echo "Arguments:"
    echo " username    Guacamole username to reset OTP for"
    echo ""
    echo "Options:"
    echo " -h, --help        Display this help message"
    echo " -v, --version     Display version information"
    echo ""
    echo "Example:"
    echo " $0 ciro.iriarte"
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
        -*)
            echo "Error: Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
    shift
done

# --- Validation ---
if [[ $# -ne 1 ]]; then
    show_help >&2
    exit 1
fi

U="$1"

# Sanitize username: allow only alphanumeric, dots, hyphens, underscores, and @
if [[ ! "$U" =~ ^[a-zA-Z0-9._@-]+$ ]]; then
    echo "Error: Invalid username format." >&2
    exit 1
fi

# --- Main ---
echo "Resetting OTP for user [$U]"
echo "  (user will need to re-enroll)"

$DBCMD "$DBNAME" <<EOF
UPDATE
    guacamole_user_attribute AS gua,
    guacamole_entity AS ge,
    guacamole_user AS gu
SET
    gua.attribute_value = 'false'
WHERE
    ge.type = 'USER'
    AND ge.name = '$U'
    AND ge.entity_id = gu.entity_id
    AND gu.user_id = gua.user_id
    AND attribute_name = 'guac-totp-key-confirmed';
EOF
