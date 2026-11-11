# Automated end-to-end test of the "Connect to Claude/Agy" app - RUN ON THE CONSOLE:
#   python3 /mnt/sdcard/mustardos_remoteai/test-connect-ai-app.py [dir filter ...]
# Runs the app script in an 80x24 pseudo-terminal and walks through:
#   n -> first tool -> directory browser (PROJECTS_ROOT, then each filter, e.g. "myproject") -> Enter -> detach
#   n -> second tool (if configured) -> "l" (last directory) -> Enter -> detach -> session list -> q
# Leaves 1-2 sessions on the laptop (kill them: psmux kill-server).
# Author: Patryk Strzelecki <patryk@strzelecki.info>
import os, sys, pty, time, re, select, fcntl, termios, struct

HERE = os.path.dirname(os.path.abspath(__file__))

def conf(key, default=""):
    try:
        for line in open(os.path.join(HERE, "mustardos-remoteai.conf")):
            m = re.match(r"\s*%s=(['\"]?)(.*?)\1\s*(#.*)?$" % key, line.rstrip("\r\n"))
            if m:
                return m.group(2)
    except OSError:
        pass
    return default

APP = os.path.join(conf("CONSOLE_APP_DIR", "/mnt/sdcard/MUOS/application"), "Connect to Claude-Agy", "session-menu.sh")
FILTERS = sys.argv[1:]

def run():
    pid, fd = pty.fork()
    if pid == 0:
        os.execv("/bin/sh", ["sh", APP])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    def rd(t):
        out = b""; end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.3)
            if r:
                try: out += os.read(fd, 65536)
                except OSError: break
        s = out.decode("utf-8", "replace")
        s = re.sub(r"\x1b\[[0-9;?<>=]*[A-Za-z~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[=>()][0-9A-B]?|\x1bP[^\x1b]*\x1b\\", "", s)
        return "\n".join(l for l in s.splitlines() if l.strip())
    def step(title, keys, wait, tail=600):
        os.write(fd, keys)
        out = rd(wait)
        print(f"=== {title} ===\n" + out[-tail:])
        return out
    print(f"=== START ({APP}) ===\n" + rd(8)[-600:])
    out = step("NEW SESSION", b"n\r", 2, 300)
    if "Tool:" in out:
        out = step("FIRST TOOL", b"\r", 3)
    for f in FILTERS:
        step(f"FILTER {f}", f.encode() + b"\r", 3)
    step("FIRST SESSION STARTED", b"\r", 15, 500)
    out = step("AFTER DETACH", b"\x02d", 4, 300)
    os.write(fd, b"n\r")
    out = rd(2)
    if "Tool:" in out:
        m = re.findall(r"(\S+) = ", out)
        second = m[1] if len(m) > 1 else ""
        print(f"=== SECOND TOOL key '{second}' ===")
        os.write(fd, second.encode() + b"\r"); rd(3)
        step("LAST DIR", b"l\r", 3, 300)
        step("SECOND SESSION STARTED", b"\r", 15, 500)
        step("SESSION LIST", b"\x02d", 4)
    else:
        step("CANCEL BROWSER", b"q\r", 3)
    os.write(fd, b"q\r"); rd(3)
    os.close(fd)

run()
