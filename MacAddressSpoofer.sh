#!/usr/bin/env bash
set -euo pipefail

# This program is a learning project to spoof a network interface MAC address:
#   - Toggle spoofing on/off
#   - Disconnect & reconnect under a new MAC
#   - Generate random MACs or use a user-specified OUI or full address

list_wifi_networks() {
    echo "Wi-Fi networks:"
    nmcli dev wifi list
}

# Allow the user to assign the OUI of the MAC
read_first_three_octets() {
	echo "Enter three octets (hex pairs) in ONE of these formats:" >&2
    echo "  • Space-separated:   00 1A 2B" >&2
    echo "  • Double-colon:      00::1A::2B" >&2
    echo "  • One per line:" >&2
    echo "    00" >&2
    echo "    1A" >&2
    echo "    2B" >&2
	echo "    " >&2
    local input=()

    # Read lines until we have 3 octets
    while [[ ${#input[@]} -lt 3 ]] && IFS= read -r line; do
        local parts
        if [[ $line == *" "* ]]; then
            IFS=' ' read -ra parts <<< "$line"
        elif [[ $line == *"::"* ]]; then
            IFS='::' read -ra parts <<< "$line"
        else
            parts=("$line")
        fi
        for p in "${parts[@]}"; do
            [[ -n $p ]] && input+=("$p")
        done
    done

    if (( ${#input[@]} != 3 )); then
        echo "Error: expected 3 octets, got ${#input[@]}" >&2
        exit 1
    fi

    # Validate each octet is exactly two hex digits
    for oct in "${input[@]}"; do
        if [[ ! $oct =~ ^[0-9A-Fa-f]{2}$ ]]; then
            echo "Error: invalid octet '$oct'" >&2
            exit 1
        fi
    done

    # Echo them as space-separated (so the caller can read -a into an array)
    printf "%s %s %s\n" "${input[0]}" "${input[1]}" "${input[2]}"
}

# Default values
declare -a oui=()   # will hold first 3 octets if -f used
mode_random=true           # if false, we’ll use the -f OUI
mode_reconnect=false       # if true, disconnect from the SSID, change the mac, then reconnect
current_wifi=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
# Parse options

#OPTIONS
#d list all available networks before prompting for a network
#f allow the user to assign the OUI
#r disconnect and reconnect to the same network
#h display options

while getopts "dfhr" opt; do
    case "$opt" in
        d) list_wifi_networks; exit 0 ;;
        f)
            mode_random=false
            # capture the three octets into oui array
            read -r -a oui <<< "$(read_first_three_octets)"
            ;;
		r) mode_reconnect=true;;
        h)
            cat <<EOF
Usage: $0 [options]
  -d    List available Wi-Fi networks
  -f    Specify first 3 octets (OUI); You’ll be prompted for form
  -r 	Disconnect and reconnect to the same network
  -h    Show this help
EOF
            exit 0
            ;;
        *)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

# If user didn’t supply -f, generate three random octets:
if $mode_random; then
    for i in 0 1 2; do
        # Random byte 00–FF
        printf -v oui[$i] "%02X" $(( RANDOM % 256 ))
    done
fi

# Now build the full MAC: OUI + 3 more random bytes
declare -a fullMAC
fullMAC=( "${oui[@]}" )
for i in 3 4 5; do
    printf -v fullMAC[$i] "%02X" $(( RANDOM % 256 ))
done

if [[ ! $mode_reconnect ]]; then
	# Prompt for network name
	read -r -p "What network would you like to connect to? " connection
elif [[ -n "$current_wifi"  ]]; then
	# Reconnect to the same network
	connection="$current_wifi" 
else
	read -r -p "You are not currently connected to a network. What network would you like to connect to? " connection
fi

# Ask for password
read -s -p "Enter Wi-Fi password for '$connection': " password
echo

if [[ -n "$current_wifi"  ]]; then
	nmcli connection down "$connection"
fi

# Generate MAC string
mac=$(printf "%02X:%02X:%02X:%02X:%02X:%02X" \
  $(( 0x${fullMAC[0]} )) $(( 0x${fullMAC[1]} )) $(( 0x${fullMAC[2]} )) \
  $(( 0x${fullMAC[3]} )) $(( 0x${fullMAC[4]} )) $(( 0x${fullMAC[5]} )))
echo "Connecting to '$connection' with MAC: $mac"

nmcli connection delete "spoofed-$connection" 2>/dev/null || true
# Create or modify connection
nmcli device wifi connect "$connection" password "$password" name "spoofed-$connection"
nmcli connection modify "spoofed-$connection" 802-11-wireless.cloned-mac-address "$mac"

# Reconnect
nmcli connection up "spoofed-$connection"