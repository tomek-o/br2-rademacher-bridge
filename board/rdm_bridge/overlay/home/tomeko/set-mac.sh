#!/bin/sh
# Set a fixed MAC address for eth0, e.g. the one printed on the device sticker.
#
#   ./set-mac.sh              show the current address and the stored one
#   ./set-mac.sh AA:BB:CC:DD:EE:FF
#   ./set-mac.sh --clear      forget it, go back to the default (derived from the board serial)
#
# The address is stored as "hwaddress ether ..." in /etc/network/interfaces, so it is set on every boot.
# Without this the KS8851 (no EEPROM) gets a stable default from /usr/libexec/default-mac, based on the board serial.
# eth0 is restarted to apply it, so an SSH session over this interface stops for a few seconds.
CONF=/etc/network/interfaces
IF=eth0

[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"

show() {
    echo "current: $(cat /sys/class/net/$IF/address)"
    echo "stored:  $(sed -n 's/^[[:space:]]*hwaddress ether[[:space:]]*//p' $CONF | head -n 1)"
}

case "$1" in
    "") show; exit 0 ;;
    --clear) mac="" ;;
    *)
        mac=$(echo "$1" | tr 'A-F-' 'a-f:')
        echo "$mac" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || { echo "not a MAC address: $1 (use AA:BB:CC:DD:EE:FF)" >&2; exit 1; }
        first=$((0x${mac%%:*}))
        [ $((first & 1)) = 0 ] || { echo "multicast address (first byte is odd), not usable" >&2; exit 1; }
        [ "$mac" != "00:00:00:00:00:00" ] || { echo "all zeros is not a valid address" >&2; exit 1; }
        ;;
esac

grep -q "^iface $IF inet static" $CONF || { echo "no 'iface $IF inet static' in $CONF" >&2; exit 1; }
sed -i '/^[[:space:]]*hwaddress ether/d' $CONF
[ -z "$mac" ] || sed -i "/^iface $IF inet static/a\\	hwaddress ether $mac" $CONF
sync

echo "restarting $IF ..."
ifdown $IF >/dev/null 2>&1
[ -z "$mac" ] || ip link set dev $IF address "$mac"
ifup $IF >/dev/null 2>&1
show
