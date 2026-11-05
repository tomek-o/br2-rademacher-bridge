# Installing

Use a spare SD card (4 GB or more), not the one from your bridge, unless you have a backup of it.

## Write the card

Find the card (check the size and model!):

    lsblk -o NAME,SIZE,MODEL,TRAN,RM

Then, replacing `sdX`:

    sudo umount /dev/sdX?* 2>/dev/null
    xzcat ../build/out/images/sdcard.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress

Or use `sdcard.img` directly with `dd if=...`, or Raspberry Pi Imager / balenaEtcher.
A wrong device name here will wipe another disk.

## First boot

Put the card in the bridge, plug in Ethernet and power. The first boot takes a few minutes: the root
partition is enlarged, the board reboots once on its own, then the filesystem is resized and the SSH
host keys are generated.

The bridge has a fixed address, 192.168.0.52 (netmask 255.255.254.0, gateway 192.168.0.1), so your
computer needs to be in that network. If it isn't:

    sudo ip addr add 192.168.0.10/23 dev eth0

Then:

    ssh tomeko@192.168.0.52        # password: tomeko

Root login over SSH is disabled; use `sudo` (password `tomeko`) or `su` once you are in. If ssh complains about a changed host key, run `ssh-keygen -R 192.168.0.52`.

If your router is not 192.168.0.1 (the clock then stays in 1970, because NTP cannot get out), change it on the bridge:

    sudo sed -i 's/192.168.0.1/YOUR.ROUTER.IP/' /etc/network/interfaces /etc/resolv.conf
    sudo ip route replace default via YOUR.ROUTER.IP

To use the MAC address from the device sticker (otherwise a stable `02:...` address derived from the board serial is used):

    ./set-mac.sh AA:BB:CC:DD:EE:FF      # stored in /etc/network/interfaces, applied at every boot
    ./set-mac.sh --clear                # back to the default address

## Checking

    df -h /                  # about the size of the whole card
    ip addr show eth0
    dmesg | grep -i ks8851
    mount | grep ' / '       # noatime,nodiratime,commit=30
    date                     # right a minute after boot (needs a route to the internet, see README)
    aplay -l                 # HDMI audio, and a USB sound card if one is plugged in

## If it doesn't work

- No ping: check the cable and the link LEDs, and your computer's address. With a monitor on the
  mini-HDMI port you should see the boot messages and a login prompt on tty1, and `dmesg` will say
  whether the ks8851 was found.
- Nothing at all: re-write the card.
- Root stays small: run `/etc/init.d/S05resizefs start` as root.

To get the stock firmware back, put the original card in, or restore your backup with `restore_sdcard.sh`.
To change the IP, edit `/etc/network/interfaces` on the bridge, or
`board/rdm_bridge/overlay/etc/network/interfaces` in the build.
