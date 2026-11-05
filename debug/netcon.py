#!/usr/bin/env python3
"""Collect kernel messages sent by the bridge's netconsole (UDP 6666) into a timestamped file."""
import socket, sys, time
out = sys.argv[1]
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", 6666))
s.settimeout(1.0)
end = time.time() + int(sys.argv[2]) if len(sys.argv) > 2 else None
with open(out, "a", buffering=1) as f:
    f.write("# listener started %s\n" % time.strftime("%T"))
    while end is None or time.time() < end:
        try:
            data, addr = s.recvfrom(4096)
        except socket.timeout:
            continue
        for line in data.decode(errors="replace").splitlines():
            f.write("%s %s\n" % (time.strftime("%T"), line))
