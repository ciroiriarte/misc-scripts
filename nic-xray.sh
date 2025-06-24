#!/bin/bash
#
# Script Name: nic-xray.sh
# Description: This script lists all physical network interfaces on the system,
#              showing PCI slot, firmware version, MAC address, MTU, link status,
#              negotiated speed/duplex, bond membership, and LLDP peer info.
#              It uses color to highlight link status and bond groupings.
#              Created initially to deploy Openstack nodes, but should work
#              with any Linux machine.
#
# Author: Ciro Iriarte <ciro.iriarte@millicom.com>
# Created: 2025-06-05
#
# Requirements:
#   - Must be run as root
#   - Requires: ethtool, lldpctl, awk, grep, cat, readlink
#
# Change Log:
#   - 2025-06-05: Initial version
#   - 2025-06-06: Added color for bond names and link status
#                 Fixed alignment issues with ANSI color codes
#                 Changed variables to uppercase
#                 Added  LACP peer info (requires LLDP)
#                 Added  VLAN peer info (requires LLDP)
#   - 2025-06-25: Fixed MAC extraction for bond slaves
#

# LOCALE setup, we expect output in English for proper parsing
LANG=en_US.UTF-8

# --- Argument Parsing ---
SHOW_LACP=false
SHOW_VLAN=false
SHOW_BMAC=false
OUTPUT_FORMAT="table"


# Parse options using getopt
OPTIONS=$(getopt -o h --long help,lacp,vlan,bmac,output: -n "$0" -- "$@")
if [ $? -ne 0 ]; then
	echo "Failed to parse options." >&2
	exit 1
fi


# Reorder the positional parameters according to getopt's output
eval set -- "$OPTIONS"

# Process options
while true; do
	case "$1" in
		--lacp)
			SHOW_LACP=true
			shift
			;;
		--vlan)
			SHOW_VLAN=true
			shift
			;;
		--bmac)
			SHOW_BMAC=true
			shift
			;;
		--output)
			case "$2" in
				table|csv|json)
				OUTPUT_FORMAT="$2"
				;;
			*)
				echo "Invalid output format: $2. Choose from table, csv, or json." >&2
				exit 1
				;;
			esac
			shift 2
			;;
		-h|--help)
			echo -e "Usage: $0 [--lacp] [--vlan] [--bmac] [--output FORMAT] [--help]"
			echo -e ""
			echo -e "Description:"
			echo -e " Lists physical network interfaces with detailed information including:"
			echo -e " PCI slot, firmware, MAC, MTU, link, speed/duplex, bond membership,"
			echo -e " LLDP peer info, and optionally LACP status and VLAN tagging (via LLDP)."
			echo -e ""
			echo -e "Options:"
			echo -e " --lacp         Show LACP Aggregator ID and Partner MAC per interface"
			echo -e " --vlan         Show VLAN tagging information (from LLDP)"
			echo -e " --bmac         Show bridge MAC address"
			echo -e " --output TYPE  Output format: table (default), csv, or json"
			echo -e " --help         Display this help message"
			exit 0
			;;
		--)
			shift
			break
			;;
		*)
			echo "Unexpected option: $1" >&2
			exit 1
			;;
	esac
done



# --- Validation Section ---
if [[ $EUID -ne 0 ]]; then
    echo -e "❌ This script must be run as root. Please use sudo or switch to root."
    exit 1
fi

REQUIRED_CMDS=("ethtool" "lldpctl" "readlink" "awk" "grep" "cat" "ip")

for CMD in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$CMD" &>/dev/null; then
        echo -e "❌ Required command '$CMD' is not installed or not in PATH."
        exit 1
    fi
done

# --- Color Setup ---
declare -A BOND_COLORS

COLOR_CODES=(
    "\033[1;34m"  # Blue
    "\033[1;36m"  # Cyan
    "\033[1;33m"  # Yellow
    "\033[1;35m"  # Magenta
    "\033[1;37m"  # White
)
RESET_COLOR="\033[0m"
COLOR_INDEX=0

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"

strip_ansi() {
    echo -e "$1" | sed -r 's/\x1B\[[0-9;]*[mK]//g'
}

pad_color() {
    local TEXT="$1"
    local WIDTH="$2"
    local STRIPPED=$(strip_ansi "$TEXT")
    local PAD=$((WIDTH - ${#STRIPPED}))
    printf "%s%*s" "$TEXT" "$PAD" ""
}

# --- Header ---
case ${OUTPUT_FORMAT} in
	table)
		FSEP="\t"
		;;
	csv)
		FSEP=","
		;;
	*)
		echo "something went wrong"
		exit 1
		;;
esac

printf "%s${FSEP}%s${FSEP}%s${FSEP}%s${FSEP}%s${FSEP}%b${FSEP}%s${FSEP}%b${FSEP}" "PCI Slot" "Firmware" "Interface" "MAC Address" "MTU" "Link" "Speed/Duplex" "Parent Bond"
${SHOW_BMAC} && printf "%b${FSEP}" "Bond MAC"
${SHOW_LACP} && printf "%b${FSEP}" "LACP Status"
${SHOW_VLAN} && printf "%s${FSEP}" "VLAN"
printf "%s${FSEP}%s\n" "Switch Name" "Port Name"
[[ ${OUTPUT_FORMAT} == "table" ]] && echo -e "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"

# --- Main Logic ---
for IFACE in $(ls /sys/class/net/ | grep -vE 'lo|vnet|virbr|br|bond|docker|tap|tun'); do
    [[ "$IFACE" == *.* ]] && continue

    DEVICE_PATH="/sys/class/net/$IFACE/device"
    [[ ! -e "$DEVICE_PATH" ]] && continue

    PCI_SLOT=$(basename "$(readlink -f "$DEVICE_PATH")")
    FIRMWARE=$(ethtool -i "$IFACE" 2>/dev/null | awk -F': ' '/firmware-version/ {print $2}')
    MTU=$(cat /sys/class/net/$IFACE/mtu 2>/dev/null)

    LINK_RAW=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)
    LINK_STATUS=$([[ "$LINK_RAW" == "up" ]] && echo -e "${GREEN}up${RESET_COLOR}" || echo -e "${RED}down${RESET_COLOR}")

    SPEED=$(ethtool "$IFACE" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}' | sed 's/Unknown.*/N\/A/')
    DUPLEX=$(ethtool "$IFACE" 2>/dev/null | awk -F': ' '/Duplex:/ {print $2}' | sed 's/Unknown.*/N\/A/')
    SPEED_DUPLEX="${SPEED:-N/A} (${DUPLEX:-N/A})"

    if [[ -L /sys/class/net/$IFACE/master ]]; then
        BOND_MASTER=$(basename "$(readlink -f /sys/class/net/$IFACE/master)")
    else
        BOND_MASTER="None"
    fi

    if [[ "$BOND_MASTER" != "None" ]]; then
        if [[ -z "${BOND_COLORS[$BOND_MASTER]}" ]]; then
            BOND_COLORS[$BOND_MASTER]=${COLOR_CODES[$COLOR_INDEX]}
            ((COLOR_INDEX=(COLOR_INDEX+1)%${#COLOR_CODES[@]}))
        fi
        COLORED_BOND="${BOND_COLORS[$BOND_MASTER]}$(printf '%s' "${BOND_MASTER}")${RESET_COLOR}"
        MAC=$(grep -E "Slave Interface: ${IFACE}|Permanent HW addr" /proc/net/bonding/${BOND_MASTER} |grep -A1 "Slave Interface: ${IFACE}"|tail -1|awk '{ print $4}' 2>/dev/null)
        BMAC=$(grep "System MAC address" /proc/net/bonding/${BOND_MASTER}|awk '{ print $4 }' 2>/dev/null)
    else
        COLORED_BOND=$(printf "%s" "${BOND_MASTER}")
        MAC=$(cat /sys/class/net/${IFACE}/address 2>/dev/null)
        BMAC="N/A"
    fi

    # LACP Status
    LACP_STATUS="N/A"
    if $SHOW_LACP && [[ "$BOND_MASTER" != "None" && -f /proc/net/bonding/$BOND_MASTER ]]; then
        LACP_STATUS=$(awk -v IFACE="$IFACE" '
            BEGIN { in_iface=0; in_actor=0; in_partner=0; agg=""; peer=""; state="" }
            $0 ~ "^Slave Interface: "IFACE"$" { in_iface=1; next }
            in_iface && /^Slave Interface:/ { in_iface=0 }
            in_iface && /Aggregator ID:/ { agg=$3 }
            in_iface && /details actor lacp pdu:/ { in_actor=1; next }
            in_actor && /^[[:space:]]*port state:/ { state=$3; in_actor=0 }
            in_iface && /details partner lacp pdu:/ { in_partner=1; next }
            in_partner && /^[[:space:]]*system mac address:/ { peer=$4; in_partner=0 }
            END {
                if (agg && peer && state == "63")
                    printf "AggID:%s Peer:%s", agg, peer
                else if (agg && peer)
                    printf "AggID:%s Peer:%s (Partial)", agg, peer
                else
                    print "Pending"
            }
        ' /proc/net/bonding/$BOND_MASTER)

        if [[ "$LACP_STATUS" == *"(Partial)"* ]]; then
            LACP_STATUS="${YELLOW}${LACP_STATUS}${RESET_COLOR}"
        elif [[ "$LACP_STATUS" == AggID* ]]; then
            LACP_STATUS="${GREEN}${LACP_STATUS}${RESET_COLOR}"
        else
            LACP_STATUS="${RED}${LACP_STATUS}${RESET_COLOR}"
        fi
    fi

    # LLDP Info
    LLDP_OUTPUT=$(lldpctl "$IFACE" 2>/dev/null)
    SWITCH_NAME=$(echo "$LLDP_OUTPUT" | awk -F'SysName: ' '/SysName:/ {print $2}' | xargs)
    PORT_NAME=$(echo "$LLDP_OUTPUT" | awk -F'PortID: ' '/PortID:/ {print $2}' | xargs)

    # VLAN Info from LLDP
    VLAN_INFO=""
    if $SHOW_VLAN; then
        while IFS= read -r LINE; do
            VLAN_ID=$(echo "$LINE" | awk -F'VLAN: ' '{print $2}' | awk -F', ' '{print $1}'|awk '{ print $1 }')
            PVID=$(echo "$LINE" | awk -F'pvid: ' '{print $2}' | awk '{print $1}')
            [[ $PVID == "yes" ]] && VLAN_INFO+="${VLAN_ID}[P];" || VLAN_INFO+="${VLAN_ID};"
        done <<< "$(echo "$LLDP_OUTPUT" | grep 'VLAN:')"
        VLAN_INFO=${VLAN_INFO%, }
	VLAN_INFO=$(echo ${VLAN_INFO}|sed 's/;$//g')
	if [ "${VLAN_INFO}x" == "x" ]
	then
		VLAN_INFO="N/A"
	fi
    fi

    # Output
    printf "%s${FSEP}%s${FSEP}%s${FSEP}%s${FSEP}%s${FSEP}%b${FSEP}%s${FSEP}%b${FSEP}" "$PCI_SLOT" "$FIRMWARE" "$IFACE" "$MAC" "$MTU" "$LINK_STATUS" "$SPEED_DUPLEX" "$COLORED_BOND"
    ${SHOW_BMAC} && printf "%b${FSEP}" "${BMAC}"
    ${SHOW_LACP} && printf "%b${FSEP}" "${LACP_STATUS}"
    ${SHOW_VLAN} && printf "%s${FSEP}" "${VLAN_INFO}"
    printf "%s${FSEP}%s\n" "${SWITCH_NAME}" "${PORT_NAME}"
done
