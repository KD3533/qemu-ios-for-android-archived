#!/data/data/com.termux/files/usr/bin/bash
#
# Press an iPod Touch button in a running emulator (started with run-ipod.sh)
# by sending "sendkey" to the QEMU monitor socket.
#
# Usage: bash scripts/android/ipod-key.sh <button> [hold_ms]
#   button:  home | power | volup | voldown
#            or "monitor <command...>" to run any QEMU monitor command
#   hold_ms: how long to hold the button (default 100), e.g. 3000 for a long
#            power press

set -euo pipefail

MON_SOCK="${IPOD_MONITOR:-${TMPDIR:-$PREFIX/tmp}/qemu-ipod.monitor}"

if [ $# -lt 1 ]; then
    sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

case "$1" in
    home)    CMD="sendkey h" ;;
    power)   CMD="sendkey p" ;;
    volup)   CMD="sendkey equal" ;;
    voldown) CMD="sendkey minus" ;;
    monitor) shift; CMD="$*" ;;
    *) echo "error: unknown button '$1' (home, power, volup, voldown, monitor)" >&2; exit 1 ;;
esac
if [ "${1:-}" != "monitor" ] && [ -n "${2:-}" ]; then
    CMD="$CMD $2"
fi

if [ ! -S "$MON_SOCK" ]; then
    echo "error: monitor socket $MON_SOCK not found; is run-ipod.sh running?" >&2
    exit 1
fi

python3 - "$MON_SOCK" "$CMD" <<'EOF'
import socket, sys

path, cmd = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(path)

def read_until_prompt():
    buf = b""
    while not buf.endswith(b"(qemu) "):
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
    return buf.decode(errors="replace")

read_until_prompt()                      # banner + first prompt
s.sendall(cmd.encode() + b"\n")
out = read_until_prompt()                # echo + output + next prompt
s.close()

# Drop the echoed command and the trailing prompt; strip terminal escapes.
lines = [l for l in out.replace("\r", "").split("\n")
         if l and not l.startswith("(qemu)") and "\x1b" not in l]
if lines:
    print("\n".join(lines))
EOF
