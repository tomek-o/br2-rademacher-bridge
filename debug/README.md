# Debugging a board that panics at boot, without a console

These are the tools that found the real cause of the early panics (see ../GOTCHAS.md). They are not part of the
normal build.

## What they do
- **netconsole**: sends kernel messages as UDP packets over the board's Ethernet chip (`debug/netcon.py` collects
  them on the PC). The Ethernet chip can only send about 45 packets while the log is replayed at start-up and it
  cannot send once the kernel is panicking, so on its own it only shows the first lines of the boot.
- **ramoops/pstore**: on a panic the kernel saves its log in a reserved block of RAM. The RAM survives the
  reset that `panic=10` triggers (checked on this board). `debug/patches/0001-...patch` prints the tail of that
  saved log at the very start of the next boot, at error level, so that netconsole sends it first.
  `debug/patches/0002-...patch` enlarges netpoll's packet pool.

## How to use
1. Copy `debug/patches/*.patch` to `patches/linux/`, append `debug/linux-debug.fragment` to
   `board/rdm_bridge/linux.fragment`, run `make -C ../build/out linux-dirclean`, then `./build.sh`.
2. On the PC: `python3 debug/netcon.py netcon.log 3000` (listens on UDP 6666 for 50 minutes).
3. On the SD card's boot partition use this `cmdline.txt` (one line; adjust the addresses; the target MAC is
   the PC's, so that no ARP is needed):

       root=/dev/mmcblk0p2 rootwait rw rootfstype=ext4 rootflags=commit=30 console=tty1 panic=10 loglevel=4
       mem=440M ramoops.mem_address=0x1b800000 ramoops.mem_size=0x100000 ramoops.console_size=0x40000
       ramoops.record_size=0x8000 ramoops.max_reason=2 pstore.compress=none netpoll.carrier_timeout=10
       netconsole=@192.168.0.52/eth0,6666@<PC-IP>/<PC-MAC>      (e.g. ...@192.168.0.10/aa:bb:cc:dd:ee:ff)

4. Power-cycle the board. The first boot panics and saves the record; the second boot's log starts with
   `prev> ...` lines, the end of the previous boot's log with the panic message.

`loglevel=4` keeps the replay short so that the `prev>` lines are among the first ones sent. Note that
`mem=440M` has to match the memory the firmware gives the kernel (448 MB with `gpu_mem=64`); the ramoops block
sits just above it.
