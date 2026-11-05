# Gotchas

Things that cost time while bringing this up, grouped by topic.

- [The board does not boot](#the-board-does-not-boot)
- [Debugging without a console](#debugging-without-a-console)
- [Device tree and hardware](#device-tree-and-hardware)
- [Running system](#running-system)
- [Buildroot](#buildroot)
- [Flashing and the test loop](#flashing-and-the-test-loop)

## The board does not boot

### `rootflags=noatime` makes the root mount fail, and the kernel panics
The root filesystem could not be mounted when `cmdline.txt` had `rootflags=noatime,nodiratime,commit=30`:

    ext4: Unknown parameter 'noatime'
    VFS: Unable to mount root fs ... Kernel panic

`noatime` and `nodiratime` are generic VFS mount flags, set by `mount(2)`. ext4 in 6.12 rejects them in the option
string that `rootflags=` passes; `commit=30` is fine. So `cmdline.txt` has only `rootflags=commit=30`, and
`post-build.sh` changes init's `mount -o remount,rw /` into `mount -o remount,rw,noatime,nodiratime /`.

This one mistake looked like many other problems for hours: an ARMv7 kernel, the device tree, USB, `device_tree=`,
clocks, a "cold boot only" problem and a damaged card were all suspected. On the board it looks like this: the red
LED flashes for 2-3 seconds, then the green LED blinks at 2 Hz, then the board resets and starts again. Lesson: when
restoring or comparing boot files, take **all** of them from the same working source, and compare the command line
(`cat /proc/cmdline` on a running board).

### The 2 Hz green blink is a real kernel panic
The green LED in the device tree has `panic-indicator;`. It stays on normally, as in the stock firmware, and blinks
every 200 ms while the kernel is in its panic countdown (`panic=10`). This needs `CONFIG_LEDS_TRIGGER_PANIC=y`.
So blinking means a real panic, not a hardware watchdog.

### The kernel must be ARMv6 only
`bcm2835_defconfig` only sets `CONFIG_ARCH_MULTI_V6=y`. In the kernel's Kconfig `ARCH_MULTI_V7` has `default y`, so
unless the config says otherwise it is switched on as well and the kernel is compiled for ARMv7. The Pi Zero's
ARM1176 is ARMv6 and panics a couple of seconds into boot. `linux.fragment` therefore has
`# CONFIG_ARCH_MULTI_V7 is not set`. After changing kernel options check that
`readelf -A build/linux-*/vmlinux | grep CPU_arch` says `v6K`.

## Debugging without a console

The board has no easy console (the UART goes to the radio controller), so see `debug/README.md` for the tools.
In short:

- netconsole alone only shows the first ~45 lines (the Ethernet chip's queue fills during the start-up replay, and
  it cannot send during a panic).
- ramoops/pstore keeps the log of a panicking boot in RAM, which survives the reset on this board. Printing that
  record at the start of the next boot, at error level, gets the panic text out through netconsole.
- Details that cost time: the pstore options are hidden unless `CONFIG_MISC_FILESYSTEMS=y` (the Pi defconfig turns it
  off, and Kconfig drops the lines silently); pstore compresses panic records unless `pstore.compress=none`; and
  `mem=` has to leave room for the reserved block.
- QEMU can boot the image: build with `BR2_PACKAGE_HOST_QEMU=y`, then
  `qemu-system-arm -M raspi0 -kernel zImage -dtb <dtb> -drive file=sd.img,if=sd,format=raw -nographic
  -append "root=/dev/mmcblk0p2 rootwait console=ttyAMA0,115200"` (the SD image size must be a power of two).
  It found the SPI pin conflict. It does not model the power manager's ASB registers (remove them from a test copy
  of the device tree: `reg = <0x7e100000 0x114>;` on the `bcm2835-pm` node) and has no USB device mode, KS8851 or
  LEDs. It did not find the `rootflags` problem because it was given its own command line.
- Boot the stock kernel from a backup of the original card with this root filesystem. If that works, the hardware
  and the root filesystem are fine.
- Don't open `/dev/ttyUSB*` on your PC just to see if something answers; those adapters may be in use by something else.

## Device tree and hardware

- The base `bcm2835-rpi-zero.dts` puts GPIO4-11 (ALT0) and GPIO18-21 (I2S) in the GPIO controller's own default pin
  state. That includes the SPI0 pins ("pin gpio7 already requested": the SPI controller does not probe and the KS8851
  never appears) and the green LED on GPIO18. The tree overrides it with `pinctrl-0 = <&gpioout>`.
- SPI0 has no pin or chip-select setup in the base tree; the KS8851 node needs `pinctrl-0 = <&spi0_gpio7>` and
  `cs-gpios`.
- Without the two LED nodes (red GPIO17, green GPIO18) there is no visible sign that the kernel runs.
- Custom DTS files are built from the top of `arch/arm/boot/dts`, so the include is
  `"broadcom/bcm2835-rpi-zero.dts"`, and the file must not repeat `/dts-v1/;`.
- The tree is installed as `bcm2835-rpi-zero.dtb`, the file the firmware loads by default, and `config.txt` has no
  `device_tree=` line. (`device_tree=` was blamed for the panics for a while; that was wrong, see above. But once the
  firmware ignored a `device_tree=` file written from Linux and loaded the default one.) Check which tree is live:
  `ls /sys/firmware/devicetree/base` shows `bridge-leds` and `ethernet@0` for this one, and `leds` and `ks8851@0` for
  the stock one.
- `start_cd.elf` (the cut-down firmware) has no video output at all. The stock firmware used it; for HDMI use
  `start.elf` with a larger `gpu_mem`.
- The Pi Zero has two micro-USB ports. Only the one marked USB carries data.
- A PC's USB port can power the Pi through the data cable. Switching off the bridge's own supply then doesn't reset
  the board.
- `ttyAMA0` (GPIO14/15) goes to the radio controller, so no console is put on it.

## Running system

### No clock, no DNS
The board has no battery-backed clock, so it starts in 1970. `S42ntpd` sets the time once the network is up. The
self-signed TLS certificate is made at first boot, usually before the time is right, so it would start in 1970:
`S49sslcert` leaves a marker and `/usr/libexec/ntp-event` (called by ntpd) makes the certificate again after the
first sync. `/etc/resolv.conf` is a real file with static servers, because with a static address nothing fills in
`/run/resolv.conf`, and ntpd could not resolve the pool names.

### The gateway is not the same on every network
The image assumes the router is 192.168.0.1. On a network where it is not, the bridge has no way out: no NTP, no DNS,
curl fails, and the clock stays in 1970. Every reflash brings back 192.168.0.1 (see INSTALL.md for changing it).

### lighttpd stops itself when the clock jumps
When NTP sets the clock from 1970, lighttpd notices ("clock jumped"), shuts down gracefully and expects a
supervisor to start it again. With a plain init script nobody does, so the web server was dead after every boot.
It is now started by init (`lh:345:respawn:` in inittab, added by `post-build.sh`; there is no `S50lighttpd`), and
the certificate hook only kills it so that init starts it again.

### MAC address
The KS8851 has no EEPROM and the device tree sets no address, so the kernel would use a random MAC at every boot.
`/usr/libexec/default-mac` (a `pre-up` line in `/etc/network/interfaces`) sets a stable one derived from the Pi
serial number in `/proc/cpuinfo`: `02:` plus 5 bytes of the md5 of the serial. `set-mac.sh` stores a fixed address
as `hwaddress ether` in the same file, and `default-mac` then does nothing.
To test a change to `/etc/network/interfaces` or these scripts on a running board, run `ifdown eth0; ifup eth0`
from a command with a timeout: the SSH session over eth0 stops for a few seconds.

### `regulatory.db failed with error -2`
The Wi-Fi core is built into the kernel and asks for `regulatory.db` before the root filesystem is mounted, so a
file in `/lib/firmware` is never found. The two files (`regulatory.db`, `.p7s`, from Buildroot's wireless-regdb)
are built into the kernel with `CONFIG_EXTRA_FIRMWARE`. Kernel fragments do not expand `$(BR2_EXTERNAL_...)`, so
`external.mk` copies them into the kernel's `firmware/` directory before the build.

### Testing the watchdog
`kill -STOP $(pidof watchdog)` as root: the board resets itself after about 15 s. (`watchdogd` in `ps` is a kernel
thread, not the userspace daemon; it does nothing without `/dev/watchdog` open.) `S03watchdog` is not stopped at
shutdown on purpose, so a shutdown that hangs also ends in a reset.

## Buildroot

- Buildroot does not rebuild a package when only its options change. After adding an option for a package that is
  already built (for example `BR2_PACKAGE_LIBOPENSSL_BIN`), run `make <package>-dirclean` and `make` again. This
  includes BusyBox: after changing `busybox.fragment`, run `make busybox-dirclean`.
- The firmware package copies `cmdline.txt` and `config.txt` into the image only when it is installed:
  `make rpi-firmware-dirclean; rm -rf images/rpi-firmware; make`.
- Patches in `patches/<package>/` are applied only when the source is extracted: `make <package>-dirclean` after
  adding or changing one.
- Wrong option names are ignored without a warning (`BR2_PACKAGE_OPENSSL_BIN=y` did nothing; the name is
  `BR2_PACKAGE_LIBOPENSSL_BIN`). After editing the defconfig, check the option is in `.config`.
- `usbutils` needs udev (this image uses mdev), so `lsusb` is BusyBox's (`CONFIG_LSUSB` in `busybox.fragment`).
- rsync 3.4 includes `<linux/openat2.h>` (kernel headers 5.6+), but the Bootlin toolchain has 5.5 headers.
  `patches/rsync/` adds the few definitions as a fallback; the running kernel has the syscall.

## Flashing and the test loop

- Don't paste a command with the `sdX` placeholder: `dd of=/dev/sdX` happily creates a regular file called
  `/dev/sdX` in RAM and writes nothing to the card. Check the device with `lsblk` first.
- `lsusb` / `dmesg` output about a USB port can be about the card reader and not the board. Failed enumerations
  (`error -110`) on a port were the empty card reader, and "Media removed" means the card is not seated.
- The image is 161 MB uncompressed (32 MB FAT boot, 128 MB ext4 root; the root grows to the whole card on first
  boot, so a small start costs nothing). Flash time is bytes written divided by the card's write speed, so
  compression (`.xz`, about 20 MB) only helps the download, not `dd`. Don't use `dd conv=sparse` on a card: old data
  stays where the image has zeros, and ext4 can depend on some of those areas really being zero.
- genimage puts the first partition at sector 1 unless `align = 1M` is set in the `hdimage` section.
- Faster loops while experimenting: change only the boot files, either on the card in the PC or over SSH
  (`mount -t vfat /dev/mmcblk0p1 /boot`, copy, `sync`, `umount`, `reboot`). Keep the kernel and `/lib/modules` from the
  same build. `/tmp` on the board is a tmpfs, so files copied there with `scp` are gone after a reboot, and a
  backgrounded `reboot` started from an SSH session can be killed when the session ends; run `reboot` as the last
  command instead.
