#!/bin/bash
#
# Script Name: guacamole-reset-user-otp.sh
# Description: Resets the TOTP (OTP) enrollment for a Guacamole user,
#              forcing them to re-enroll on next login.
#
# Author: Ciro Iriarte
# Created: 2021-11-02
#
# Change Log:
#   - 2021-11-02: Initial version
#
# Version: 1.0

VERSION="1.0"

# === Functions ===

show_help() {
    echo "Usage: $0 [-h|--help] [-v|--version] <username>"
    echo ""
    echo "Version: $VERSION"
    echo ""
    echo "Description:"
    echo " Resets the TOTP (OTP) enrollment for a Guacamole user."
    echo " The user will need to re-enroll on next login."
    echo ""
    echo "Arguments:"
    echo " username    Guacamole username to reset OTP for"
    echo ""
    echo "Options:"
    echo " -v, --version     Display version information"
    echo " -h, --help        Display this help message"
    echo ""
    echo "Example:"
    echo " $0 ciro.iriarte"
}

# === Configuration ===

DBNAME=guacamole
DBUSER=guacamoleuser
DBPASS=you.wish
# Command to be used if credentials are defined at ~/.my.cnf (my preference)
DBCMD="mysql"
# Command to be used if credentials are defined in this script
#DBCMD="mysql --user=$DBUSER --password=$DBPASS"

# === Argument Parsing ===
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -v|--version)
            echo "$0 $VERSION"
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [ $# -ne 1 ]
then
        show_help >&2
        exit 1
else
        U=$1
        echo "Resetting OTP for user [$1]"
        echo -e "\t(user will need to re-enroll)"
        echo "update 
    guacamole_user_attribute AS gua,
    guacamole_entity AS ge,
    guacamole_user AS gu
set 
    gua.attribute_value = 'false'
where
    (
        ge.type = 'USER' 
    AND
        ge.name = '$U'
    AND
        ge.entity_id = gu.entity_id  
    AND
        gu.user_id = gua.user_id
    AND
        attribute_name = 'guac-totp-key-confirmed'
    );" |$DBCMD $DBNAME

fi
