#!/usr/bin/env python3
# Keyboard proxy for the console apps (MustardOS_RemoteAI).
# Author: Patryk Strzelecki
#
# muOS's terminal (muxterm) keeps the physical PgUp/PgDn keys for its own scrollback and never sends them to the
# program (MustardOS/frontend terminal/input.c). Inside psmux that scrollback is empty, so the keys did nothing.
# This proxy grabs external keyboards (Bluetooth/USB) exclusively and re-emits every key through a virtual
# keyboard, with PgUp -> F9 and PgDn -> F10. psmux maps F9/F10 back to PageUp/PageDown (laptop\psmux.conf).
# Started by the apps' mux_launch.sh before muxterm, stopped when the app exits. Pure Python, no extra modules.
import fcntl, os, select, signal, struct, sys, time

NAME = b"MustardOS_RemoteAI keyboard"
REMAP = {104: 67, 109: 68}            # KEY_PAGEUP -> KEY_F9, KEY_PAGEDOWN -> KEY_F10
SKIP = ("muOS", "axp", NAME.decode()) # console buttons / power key / ourselves
EV_SYN, EV_KEY = 0, 1
EVIOCGRAB = 0x40044590
UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x5501, 0x5502
EVENT = struct.Struct("llHHi")
KEY_A = 30
ONLY = sys.argv[1] if len(sys.argv) > 1 else ""   # optional: grab only keyboards whose name contains this (tests)

def ioc_bits(ev, size):        # EVIOCGBIT(ev, size)
    return 0x80000000 | (size << 16) | (0x45 << 8) | (0x20 + ev)

def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)

def make_uinput():
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for code in range(1, 256):
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)
    os.write(fd, NAME.ljust(80, b"\0") + struct.pack("<HHHHi", 0x06, 0x1d6b, 0x0104, 1, 0) + b"\0" * (64 * 4 * 4))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    return fd

def is_keyboard(path):
    ev = os.path.basename(path)
    try:
        name = open("/sys/class/input/%s/device/name" % ev).read().strip()
    except OSError:
        return None
    if name.startswith(SKIP) or (ONLY and ONLY not in name):
        return None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return None
    buf = bytearray(96)
    try:
        fcntl.ioctl(fd, ioc_bits(EV_KEY, len(buf)), buf)
    except OSError:
        os.close(fd); return None
    if not buf[KEY_A // 8] >> (KEY_A % 8) & 1:   # not a real keyboard (no letter keys)
        os.close(fd); return None
    return fd, name

def main():
    out = make_uinput()
    grabbed = {}   # fd -> (path, name)

    def stop(*_):
        for fd in grabbed:
            try: fcntl.ioctl(fd, EVIOCGRAB, 0)
            except OSError: pass
        try: fcntl.ioctl(out, UI_DEV_DESTROY)
        except OSError: pass
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGHUP, stop)

    last_scan = 0
    while True:
        if time.time() - last_scan > 2:   # keyboards connect/disconnect over Bluetooth at any time
            last_scan = time.time()
            known = {p for p, _ in grabbed.values()}
            for e in sorted(os.listdir("/dev/input")):
                path = "/dev/input/" + e
                if not e.startswith("event") or path in known:
                    continue
                r = is_keyboard(path)
                if not r:
                    continue
                fd, name = r
                try:
                    fcntl.ioctl(fd, EVIOCGRAB, 1)
                except OSError:
                    os.close(fd); continue
                grabbed[fd] = (path, name)
                log("grabbed", path, name)
        if not grabbed:
            time.sleep(0.5); continue
        ready, _, _ = select.select(list(grabbed), [], [], 1.0)
        for fd in ready:
            try:
                data = os.read(fd, EVENT.size * 64)
            except OSError:
                log("lost", *grabbed[fd]); os.close(fd); grabbed.pop(fd); continue
            for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                sec, usec, typ, code, val = EVENT.unpack_from(data, i)
                if typ == EV_KEY:
                    os.write(out, EVENT.pack(sec, usec, EV_KEY, REMAP.get(code, code), val))
                elif typ == EV_SYN:
                    os.write(out, EVENT.pack(sec, usec, EV_SYN, code, val))

if __name__ == "__main__":
    main()
