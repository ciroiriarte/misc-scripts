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
#   - 2025-06-23: Fixed MAC extraction for bond slaves
#                 Added support for CSV output
#

# LOCALE setup, we expect output in English for proper parsing
LANG=en_US.UTF-8

# --- Argument Parsing ---
SHOW_LACP=false
SHOW_VLAN=false
SHOW_BMAC=false
SHOW_SEPARATOR=false
OUTPUT_FORMAT="table"


# Parse options using getopt
OPTIONS=$(getopt -o hs --long help,lacp,vlan,bmac,separator,output: -n "$0" -- "$@")
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
		-s|--separator)
			SHOW_SEPARATOR=true
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
			echo -e "Usage: $0 [--lacp] [--vlan] [--bmac] [-s|--separator] [--output FORMAT] [--help]"
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
			echo -e " -s, --separator"
			echo -e "                Show column separators in table output"
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
    printf "%b%*s" "$TEXT" "$PAD" ""
}

# --- Helper: escape string for JSON output ---
json_escape() {
    local STR="$1"
    STR="${STR//\\/\\\\}"
    STR="${STR//\"/\\\"}"
    printf '%s' "$STR"
}

# --- Helper: compute max width from header label and data values ---
max_width() {
    local HEADER="$1"
    shift
    local MAX=${#HEADER}
    for VAL in "$@"; do
        (( ${#VAL} > MAX )) && MAX=${#VAL}
    done
    echo "$MAX"
}

# --- Data Collection Arrays ---
declare -a DATA_DEVICE DATA_FIRMWARE DATA_IFACE DATA_MAC DATA_MTU
declare -a DATA_LINK_PLAIN DATA_LINK_COLOR
declare -a DATA_SPEED
declare -a DATA_BOND_PLAIN DATA_BOND_COLOR
declare -a DATA_BMAC
declare -a DATA_LACP_PLAIN DATA_LACP_COLOR
declare -a DATA_VLAN DATA_SWITCH DATA_PORT
ROW_COUNT=0

# --- Data Collection ---
for IFACE in $(ls /sys/class/net/ | grep -vE 'lo|vnet|virbr|br|bond|docker|tap|tun'); do
    [[ "$IFACE" == *.* ]] && continue

    DEVICE_PATH="/sys/class/net/$IFACE/device"
    [[ ! -e "$DEVICE_PATH" ]] && continue

    DEVICE=$(basename "$(readlink -f "$DEVICE_PATH")")
    FIRMWARE=$(ethtool -i "$IFACE" 2>/dev/null | awk -F': ' '/firmware-version/ {print $2}')
    MTU=$(cat /sys/class/net/$IFACE/mtu 2>/dev/null)

    LINK_RAW=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)
    if [[ "$LINK_RAW" == "up" ]]; then
        LINK_PLAIN="up"
        LINK_COLOR="${GREEN}up${RESET_COLOR}"
    else
        LINK_PLAIN="down"
        LINK_COLOR="${RED}down${RESET_COLOR}"
    fi

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
        BOND_COLOR="${BOND_COLORS[$BOND_MASTER]}${BOND_MASTER}${RESET_COLOR}"
        BOND_PLAIN="$BOND_MASTER"
        MAC=$(grep -E "Slave Interface: ${IFACE}|Permanent HW addr" /proc/net/bonding/${BOND_MASTER} |grep -A1 "Slave Interface: ${IFACE}"|tail -1|awk '{ print $4}' 2>/dev/null)
        BMAC=$(grep "System MAC address" /proc/net/bonding/${BOND_MASTER}|awk '{ print $4 }' 2>/dev/null)
    else
        BOND_COLOR="$BOND_MASTER"
        BOND_PLAIN="$BOND_MASTER"
        MAC=$(cat /sys/class/net/${IFACE}/address 2>/dev/null)
        BMAC="N/A"
    fi

    # LACP Status
    LACP_PLAIN="N/A"
    LACP_COLOR="N/A"
    if $SHOW_LACP && [[ "$BOND_MASTER" != "None" && -f /proc/net/bonding/$BOND_MASTER ]]; then
        LACP_PLAIN=$(awk -v IFACE="$IFACE" '
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

        if [[ "$LACP_PLAIN" == *"(Partial)"* ]]; then
            LACP_COLOR="${YELLOW}${LACP_PLAIN}${RESET_COLOR}"
        elif [[ "$LACP_PLAIN" == AggID* ]]; then
            LACP_COLOR="${GREEN}${LACP_PLAIN}${RESET_COLOR}"
        else
            LACP_COLOR="${RED}${LACP_PLAIN}${RESET_COLOR}"
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

    # Store collected data
    DATA_DEVICE[$ROW_COUNT]="$DEVICE"
    DATA_FIRMWARE[$ROW_COUNT]="$FIRMWARE"
    DATA_IFACE[$ROW_COUNT]="$IFACE"
    DATA_MAC[$ROW_COUNT]="$MAC"
    DATA_MTU[$ROW_COUNT]="$MTU"
    DATA_LINK_PLAIN[$ROW_COUNT]="$LINK_PLAIN"
    DATA_LINK_COLOR[$ROW_COUNT]="$LINK_COLOR"
    DATA_SPEED[$ROW_COUNT]="$SPEED_DUPLEX"
    DATA_BOND_PLAIN[$ROW_COUNT]="$BOND_PLAIN"
    DATA_BOND_COLOR[$ROW_COUNT]="$BOND_COLOR"
    DATA_BMAC[$ROW_COUNT]="$BMAC"
    DATA_LACP_PLAIN[$ROW_COUNT]="$LACP_PLAIN"
    DATA_LACP_COLOR[$ROW_COUNT]="$LACP_COLOR"
    DATA_VLAN[$ROW_COUNT]="$VLAN_INFO"
    DATA_SWITCH[$ROW_COUNT]="$SWITCH_NAME"
    DATA_PORT[$ROW_COUNT]="$PORT_NAME"
    ((ROW_COUNT++))
done

# --- Compute Dynamic Column Widths ---
COL_W_DEVICE=$(max_width "Device" "${DATA_DEVICE[@]}")
COL_W_FIRMWARE=$(max_width "Firmware" "${DATA_FIRMWARE[@]}")
COL_W_IFACE=$(max_width "Interface" "${DATA_IFACE[@]}")
COL_W_MAC=$(max_width "MAC Address" "${DATA_MAC[@]}")
COL_W_MTU=$(max_width "MTU" "${DATA_MTU[@]}")
COL_W_LINK=$(max_width "Link" "${DATA_LINK_PLAIN[@]}")
COL_W_SPEED=$(max_width "Speed/Duplex" "${DATA_SPEED[@]}")
COL_W_BOND=$(max_width "Parent Bond" "${DATA_BOND_PLAIN[@]}")
COL_W_BMAC=$(max_width "Bond MAC" "${DATA_BMAC[@]}")
COL_W_LACP=$(max_width "LACP Status" "${DATA_LACP_PLAIN[@]}")
COL_W_VLAN=$(max_width "VLAN" "${DATA_VLAN[@]}")
COL_W_SWITCH=$(max_width "Switch Name" "${DATA_SWITCH[@]}")
COL_W_PORT=$(max_width "Port Name" "${DATA_PORT[@]}")

# --- Column Gap ---
if ${SHOW_SEPARATOR}; then
    COL_GAP=" │ "
else
    COL_GAP="   "
fi
COL_GAP_WIDTH=${#COL_GAP}

# --- Output ---
if [[ "${OUTPUT_FORMAT}" == "table" ]]; then
    # Header
    printf "%-${COL_W_DEVICE}s${COL_GAP}%-${COL_W_FIRMWARE}s${COL_GAP}%-${COL_W_IFACE}s${COL_GAP}%-${COL_W_MAC}s${COL_GAP}%-${COL_W_MTU}s${COL_GAP}%-${COL_W_LINK}s${COL_GAP}%-${COL_W_SPEED}s${COL_GAP}%-${COL_W_BOND}s" \
        "Device" "Firmware" "Interface" "MAC Address" "MTU" "Link" "Speed/Duplex" "Parent Bond"
    ${SHOW_BMAC} && printf "${COL_GAP}%-${COL_W_BMAC}s" "Bond MAC"
    ${SHOW_LACP} && printf "${COL_GAP}%-${COL_W_LACP}s" "LACP Status"
    ${SHOW_VLAN} && printf "${COL_GAP}%-${COL_W_VLAN}s" "VLAN"
    printf "${COL_GAP}%-${COL_W_SWITCH}s${COL_GAP}%s\n" "Switch Name" "Port Name"
    # Separator line
    SEP_WIDTH=$((COL_W_DEVICE + COL_GAP_WIDTH + COL_W_FIRMWARE + COL_GAP_WIDTH + COL_W_IFACE + COL_GAP_WIDTH + COL_W_MAC + COL_GAP_WIDTH + COL_W_MTU + COL_GAP_WIDTH + COL_W_LINK + COL_GAP_WIDTH + COL_W_SPEED + COL_GAP_WIDTH + COL_W_BOND))
    ${SHOW_BMAC} && SEP_WIDTH=$((SEP_WIDTH + COL_GAP_WIDTH + COL_W_BMAC))
    ${SHOW_LACP} && SEP_WIDTH=$((SEP_WIDTH + COL_GAP_WIDTH + COL_W_LACP))
    ${SHOW_VLAN} && SEP_WIDTH=$((SEP_WIDTH + COL_GAP_WIDTH + COL_W_VLAN))
    SEP_WIDTH=$((SEP_WIDTH + COL_GAP_WIDTH + COL_W_SWITCH + COL_GAP_WIDTH + COL_W_PORT))
    printf '%*s\n' "$SEP_WIDTH" '' | tr ' ' '-'
    # Data rows
    for ((i = 0; i < ROW_COUNT; i++)); do
        printf "%-${COL_W_DEVICE}s${COL_GAP}%-${COL_W_FIRMWARE}s${COL_GAP}%-${COL_W_IFACE}s${COL_GAP}%-${COL_W_MAC}s${COL_GAP}%-${COL_W_MTU}s${COL_GAP}" \
            "${DATA_DEVICE[$i]}" "${DATA_FIRMWARE[$i]}" "${DATA_IFACE[$i]}" "${DATA_MAC[$i]}" "${DATA_MTU[$i]}"
        pad_color "${DATA_LINK_COLOR[$i]}" "$COL_W_LINK"
        printf "${COL_GAP}%-${COL_W_SPEED}s${COL_GAP}" "${DATA_SPEED[$i]}"
        pad_color "${DATA_BOND_COLOR[$i]}" "$COL_W_BOND"
        if ${SHOW_BMAC}; then
            printf "${COL_GAP}%-${COL_W_BMAC}s" "${DATA_BMAC[$i]}"
        fi
        if ${SHOW_LACP}; then
            printf "${COL_GAP}"
            pad_color "${DATA_LACP_COLOR[$i]}" "$COL_W_LACP"
        fi
        ${SHOW_VLAN} && printf "${COL_GAP}%-${COL_W_VLAN}s" "${DATA_VLAN[$i]}"
        printf "${COL_GAP}%-${COL_W_SWITCH}s${COL_GAP}%s\n" "${DATA_SWITCH[$i]}" "${DATA_PORT[$i]}"
    done
elif [[ "${OUTPUT_FORMAT}" == "csv" ]]; then
    # CSV Header
    printf "%s,%s,%s,%s,%s,%s,%s,%s" "Device" "Firmware" "Interface" "MAC Address" "MTU" "Link" "Speed/Duplex" "Parent Bond"
    ${SHOW_BMAC} && printf ",%s" "Bond MAC"
    ${SHOW_LACP} && printf ",%s" "LACP Status"
    ${SHOW_VLAN} && printf ",%s" "VLAN"
    printf ",%s,%s\n" "Switch Name" "Port Name"
    # CSV Data rows
    for ((i = 0; i < ROW_COUNT; i++)); do
        printf "%s,%s,%s,%s,%s,%s,%s,%s" \
            "${DATA_DEVICE[$i]}" "${DATA_FIRMWARE[$i]}" "${DATA_IFACE[$i]}" "${DATA_MAC[$i]}" \
            "${DATA_MTU[$i]}" "${DATA_LINK_PLAIN[$i]}" "${DATA_SPEED[$i]}" "${DATA_BOND_PLAIN[$i]}"
        ${SHOW_BMAC} && printf ",%s" "${DATA_BMAC[$i]}"
        ${SHOW_LACP} && printf ",%s" "${DATA_LACP_PLAIN[$i]}"
        ${SHOW_VLAN} && printf ",%s" "${DATA_VLAN[$i]}"
        printf ",%s,%s\n" "${DATA_SWITCH[$i]}" "${DATA_PORT[$i]}"
    done
elif [[ "${OUTPUT_FORMAT}" == "json" ]]; then
    printf '[\n'
    for ((i = 0; i < ROW_COUNT; i++)); do
        printf '  {\n'
        printf '    "device": "%s",\n' "$(json_escape "${DATA_DEVICE[$i]}")"
        printf '    "firmware": "%s",\n' "$(json_escape "${DATA_FIRMWARE[$i]}")"
        printf '    "interface": "%s",\n' "$(json_escape "${DATA_IFACE[$i]}")"
        printf '    "mac_address": "%s",\n' "$(json_escape "${DATA_MAC[$i]}")"
        printf '    "mtu": %s,\n' "${DATA_MTU[$i]:-0}"
        printf '    "link": "%s",\n' "$(json_escape "${DATA_LINK_PLAIN[$i]}")"
        printf '    "speed_duplex": "%s",\n' "$(json_escape "${DATA_SPEED[$i]}")"
        printf '    "parent_bond": "%s"' "$(json_escape "${DATA_BOND_PLAIN[$i]}")"
        if ${SHOW_BMAC}; then
            printf ',\n    "bond_mac": "%s"' "$(json_escape "${DATA_BMAC[$i]}")"
        fi
        if ${SHOW_LACP}; then
            printf ',\n    "lacp_status": "%s"' "$(json_escape "${DATA_LACP_PLAIN[$i]}")"
        fi
        if ${SHOW_VLAN}; then
            printf ',\n    "vlan": "%s"' "$(json_escape "${DATA_VLAN[$i]}")"
        fi
        printf ',\n    "switch_name": "%s"' "$(json_escape "${DATA_SWITCH[$i]}")"
        printf ',\n    "port_name": "%s"' "$(json_escape "${DATA_PORT[$i]}")"
        printf '\n  }'
        if (( i < ROW_COUNT - 1 )); then
            printf ','
        fi
        printf '\n'
    done
    printf ']\n'
fi
