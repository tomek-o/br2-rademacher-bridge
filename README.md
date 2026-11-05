# Buildroot for the Rademacher Smart2Smart bridge

A small Linux system for the Rademacher bridge (Raspberry Pi Zero with a KS8851 SPI Ethernet chip),
built with Buildroot. It replaces the stock HomePilot firmware on the SD card; nothing from the stock
firmware is included.

What you get: kernel 6.12, BusyBox, sysvinit, OpenSSH, lighttpd and Midnight Commander, plus curl, nano, htop,
rsync, tcpdump, ethtool, sudo and ALSA tools (`aplay`, `amixer`). `lsusb` is BusyBox's.

- hostname `bridge`, static IP 192.168.0.52, netmask 255.255.254.0, gateway 192.168.0.1
- users `root` and `tomeko`, both with password `tomeko`; root cannot log in over SSH. `tomeko` is in the `sudo` and
  `audio` groups, so use `sudo` (or `su`)
- web server: lighttpd on ports 80 and 443 (self-signed certificate created on first boot, replace
  `/etc/lighttpd/server.pem` to use your own), with a small status demo page at `http://192.168.0.52/`
- two partitions: a small FAT boot partition and an ext4 root that grows to fill the card on first boot
- time from NTP (BusyBox ntpd, `pool.ntp.org`, set in `/etc/default/ntpd`); DNS is static in `/etc/resolv.conf`
  (gateway, then 1.1.1.1). The board has no clock chip and starts in 1970 until the first sync.
- fewer SD card writes: `noatime`, logs and `/tmp` in RAM, lazy writeback
- USB (host), HDMI console on tty1 and HDMI audio; a USB sound card works too (`snd-usb-audio`)
- the KS8851 has no EEPROM, so the MAC is derived from the Pi's serial number (a locally administered `02:...`
  address, stable per board); `~tomeko/set-mac.sh` sets a fixed one instead, e.g. the one from the device sticker
- hardware watchdog: BusyBox `watchdog` pings it every 5 s, so a hung board resets itself
- the serial port `ttyAMA0` is left alone, because on this board it goes to the radio controller

Status: it boots and runs on the real board (about 8 seconds from power-on to SSH). Tested there: Ethernet, SSH,
sudo, HTTPS, NTP, curl, rsync (local), the watchdog, USB host and the VC4/HDMI-audio drivers loading. Not tested: the
HDMI picture (no mini-HDMI cable here) and a USB sound card.

## Layout

    buildroot/             Buildroot 2026.02.3 (the upstream release, unmodified)
    configs/               rdm_bridge_defconfig
    board/rdm_bridge/      device tree, kernel options, boot files, rootfs overlay, scripts
    patches/               source hash (kernel), small patches for rsync
    debug/                 tools for debugging boot problems without a console (see debug/README.md)
    external.mk            Buildroot external tree hook (regulatory.db for the kernel)
    build.sh               wrapper around make

Downloads and build output are not in git. They go to `../build/` (override with `BR2_DL_DIR` and `OUT`).
If you change Buildroot itself, keep it as a separate commit so it stays easy to update.

## Building

You need the usual Buildroot host packages (`build-essential curl wget unzip rsync bc cpio file patch perl
python3 libncurses-dev libssl-dev`), about 15 GB of disk and an hour or so. Then:

    ./build.sh

The result is `../build/out/images/sdcard.img` and a compressed `sdcard.img.xz` (about 20 MB).
Problems along the way are collected in [GOTCHAS.md](GOTCHAS.md).
See [INSTALL.md](INSTALL.md) for writing it to a card.

To change the configuration: `make -C ../build/out menuconfig` (or `linux-menuconfig`), then
`make -C ../build/out savedefconfig BR2_DEFCONFIG=$PWD/configs/rdm_bridge_defconfig`.

## Notes

- After a power cut you can lose up to 30 seconds of file changes (`commit=30`). The filesystem stays consistent.
- The default passwords are trivial. Change them if the bridge is on a network you don't trust.
- HDMI: the console is on tty1 (VC4 driver), with the full `start.elf` and `gpu_mem=64`.
- The default gateway in the image is 192.168.0.1, also the first DNS server. NTP needs a working route out;
  change `board/rdm_bridge/overlay/etc/network/interfaces` (and the DNS line in `post-build.sh`) if your router differs,
  or edit `/etc/network/interfaces` and `/etc/resolv.conf` on the running board (INSTALL.md).
- Ideas not done: Python and pyserial for the radio code, an MQTT client, a firewall, picking the first gateway that
  answers from a list.
