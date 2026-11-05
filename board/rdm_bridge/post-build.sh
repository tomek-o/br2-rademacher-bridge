#!/bin/sh
# Post-build: runs on the target rootfs before the filesystem image is created.
set -eu
TARGET_DIR="$1"

# Root cannot log in over SSH (log in as tomeko, then use su). Password logins for other users stay enabled.
if [ -f "${TARGET_DIR}/etc/ssh/sshd_config" ]; then
    sed -i -E 's/^#?PermitRootLogin.*/PermitRootLogin no/; s/^#?PasswordAuthentication.*/PasswordAuthentication yes/' \
        "${TARGET_DIR}/etc/ssh/sshd_config"
    grep -q '^PermitRootLogin no' "${TARGET_DIR}/etc/ssh/sshd_config" || \
        echo 'PermitRootLogin no' >> "${TARGET_DIR}/etc/ssh/sshd_config"
fi

# HDMI console: Buildroot already adds a getty on tty1 (BR2_TARGET_GENERIC_GETTY_PORT).
# Remove any extra tty1 entry from earlier versions of this script (two gettys on one tty fight).
if [ -e "${TARGET_DIR}/etc/inittab" ]; then
    sed -i '/^tty1::/d' "${TARGET_DIR}/etc/inittab"
fi

# Mount point for the (normally unmounted, read-only) FAT boot partition.
mkdir -p "${TARGET_DIR}/boot"

# noatime/nodiratime cannot go through rootflags= (ext4 rejects them there and the root mount fails with
# "ext4: Unknown parameter 'noatime'"), so apply them when init remounts the root read-write.
if [ -e "${TARGET_DIR}/etc/inittab" ]; then
    sed -i 's|^\(.*mount -o remount,rw\) /$|\1,noatime,nodiratime /|' "${TARGET_DIR}/etc/inittab"
fi


# Static DNS (the network is configured statically, nothing fills in /run/resolv.conf): the gateway first,
# then a public resolver. Needed for the NTP pool names.
rm -f "${TARGET_DIR}/etc/resolv.conf"
printf 'nameserver 192.168.0.1\nnameserver 1.1.1.1\n' > "${TARGET_DIR}/etc/resolv.conf"

# lighttpd shuts itself down when the clock jumps (NTP sets it from 1970), expecting a supervisor to start it
# again. Let init do that: respawn it from inittab (after rcS has finished) instead of the S50lighttpd script.
rm -f "${TARGET_DIR}/etc/init.d/S50lighttpd"
if [ -e "${TARGET_DIR}/etc/inittab" ] && ! grep -q '^lh:' "${TARGET_DIR}/etc/inittab"; then
    sed -i 's|^\(1::respawn:/sbin/getty.*\)$|\1\nlh:345:respawn:/usr/sbin/lighttpd -D -f /etc/lighttpd/lighttpd.conf|' "${TARGET_DIR}/etc/inittab"
fi
