#!/bin/bash

##
# Changelog
##

## v1.0 - 20211102 - Ciro Iriarte
# * First release

DBNAME=guacamole
DBUSER=guacamoleuser
DBPASS=you.wish
# Command to be used if credentials are defined at ~/.my.cnf (my preference)
DBCMD="mysql"
# Command to be used if credentials are defined in this script
#DBCMD="mysql --user=$DBUSER --password=$DBPASS"

if [ $# -ne 1 ]
then
        echo "Usage: $0 <username>"
        echo -e "\t $0 ciro.iriarte"
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
