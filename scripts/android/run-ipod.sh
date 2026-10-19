#!/data/data/com.termux/files/usr/bin/bash
#
# Run the iPod Touch 2G emulator inside Termux.
#
# Usage: bash scripts/android/run-ipod.sh <bootrom> <nand> <nor image> [extra qemu args...]
#   <nand> is the page directory (read-only) or a flat image made with
#   nand-to-image.py (the iPod's changes are saved into it).
#
# Display:
#   - If termux-x11 is running (DISPLAY set, or socket $PREFIX/tmp/.X11-unix/X0 present),
#     the SDL window is shown there.
#   - Otherwise a VNC server is started on localhost:5900; connect with any
#     Android VNC client. Force this with DISPLAY_MODE=vnc.
#
# Controls (keyboard): P = power, H = home, - / = = volume down / up.
# Tap or click on the screen for touch input.
# The iPod's Wi-Fi reaches the network through QEMU's user-mode network.
# The serial console stays in this terminal (Ctrl+C quits). The QEMU monitor
# listens on a socket instead; press buttons from another Termux session with
# scripts/android/ipod-key.sh (e.g. "ipod-key.sh home").

set -euo pipefail

if [ $# -lt 3 ]; then
    sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

BOOTROM="$1"; NAND="$2"; NOR="$3"; shift 3

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QEMU="$SRC_DIR/build-termux/arm-softmmu/qemu-system-arm"

if [ ! -x "$QEMU" ]; then
    echo "error: $QEMU not found; run scripts/android/termux-build.sh first" >&2
    exit 1
fi
[ -f "$BOOTROM" ] || { echo "error: bootrom '$BOOTROM' not found" >&2; exit 1; }
[ -e "$NAND" ]    || { echo "error: NAND '$NAND' not found" >&2; exit 1; }
[ -f "$NOR" ]     || { echo "error: NOR image '$NOR' not found" >&2; exit 1; }

if [ -d "$NAND" ]; then
    case "$NAND" in
        /sdcard/*|/storage/*)
            echo "warning: NAND on shared storage is slow (one file opened per page read);" \
                 "copy it into \$HOME for better performance" >&2 ;;
    esac
fi

TMPDIR_X11="${TMPDIR:-$PREFIX/tmp}/.X11-unix/X0"
MODE="${DISPLAY_MODE:-auto}"
if [ "$MODE" = "auto" ]; then
    if [ -n "${DISPLAY:-}" ] || [ -S "$TMPDIR_X11" ]; then
        MODE=sdl
    else
        MODE=vnc
    fi
fi

if [ "$MODE" = "sdl" ]; then
    export DISPLAY="${DISPLAY:-:0}"
    DISPLAY_ARGS=(-display sdl)
    echo "Using SDL on termux-x11 (DISPLAY=$DISPLAY)"
else
    DISPLAY_ARGS=(-display none -vnc localhost:0)
    echo "Using VNC: connect a VNC client to localhost:5900"
fi

# Keep the monitor off stdio: the emulator's debug output would bury its prompt.
MON_SOCK="${IPOD_MONITOR:-${TMPDIR:-$PREFIX/tmp}/qemu-ipod.monitor}"
rm -f "$MON_SOCK"
echo "Monitor socket: $MON_SOCK (use scripts/android/ipod-key.sh)"

exec "$QEMU" \
    -M "iPod-Touch,bootrom=$BOOTROM,nand=$NAND,nor=$NOR" \
    -serial stdio -monitor "unix:$MON_SOCK,server=on,wait=off" -cpu max \
    -nic user \
    "${DISPLAY_ARGS[@]}" "$@"
