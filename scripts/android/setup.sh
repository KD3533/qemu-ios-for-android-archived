#!/data/data/com.termux/files/usr/bin/bash
#
# One-shot setup of the iPod Touch 2G emulator in Termux: downloads the
# firmware, builds qemu-system-arm and installs the "ipod" command.
# Safe to re-run; finished steps are skipped.
#
# Usage: bash scripts/android/setup.sh [--rebuild]
#   --rebuild  rebuild the emulator even if it is already built

set -euo pipefail

if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
    echo "error: \$PREFIX is not set; this script must run inside Termux" >&2
    exit 1
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IPOD_DIR="${IPOD_DIR:-$HOME/ipod}"
RELEASE_URL="https://github.com/devos50/qemu-ios/releases/download/n72ap_v1"
QEMU="$SRC_DIR/build-termux/arm-softmmu/qemu-system-arm"

step() { echo; echo "==> $*"; }

step "Firmware ($IPOD_DIR)"
command -v curl >/dev/null && command -v unzip >/dev/null || pkg install -y curl unzip
mkdir -p "$IPOD_DIR"
for f in bootrom_240_4 nor_n72ap.bin; do
    if [ -s "$IPOD_DIR/$f" ]; then
        echo "$f: already there"
    else
        curl -fL --retry 3 -o "$IPOD_DIR/$f.part" "$RELEASE_URL/$f"
        mv "$IPOD_DIR/$f.part" "$IPOD_DIR/$f"
    fi
done
if [ -d "$IPOD_DIR/nand/cs0" ]; then
    echo "nand: already there"
else
    # about 250 MB download, 530 MB unpacked; -C - resumes an interrupted download
    curl -fL --retry 3 -C - -o "$IPOD_DIR/nand_n72ap.zip" "$RELEASE_URL/nand_n72ap.zip"
    rm -rf "$IPOD_DIR/nand.part"
    unzip -q "$IPOD_DIR/nand_n72ap.zip" -d "$IPOD_DIR/nand.part"
    mv "$IPOD_DIR/nand.part/nand" "$IPOD_DIR/nand"
    rm -rf "$IPOD_DIR/nand.part" "$IPOD_DIR/nand_n72ap.zip"
fi
# The flat image is the iPod's working copy: its changes are saved into it.
# The nand directory stays untouched, for "ipod reset".
if [ -f "$IPOD_DIR/nand.img" ]; then
    echo "nand.img: already there"
else
    echo "nand.img: packing the NAND into a flat image (1-3 GB of disk space)"
    python3 "$SRC_DIR/scripts/android/nand-to-image.py" "$IPOD_DIR/nand" "$IPOD_DIR/nand.img"
fi

step "Emulator"
if [ -x "$QEMU" ] && [ "${1:-}" != "--rebuild" ]; then
    echo "already built (use --rebuild to build again)"
else
    bash "$SRC_DIR/scripts/android/termux-build.sh"
fi

step "ipod command"
chmod +x "$SRC_DIR/scripts/android/ipod"
ln -sf "$SRC_DIR/scripts/android/ipod" "$PREFIX/bin/ipod"
echo "installed $PREFIX/bin/ipod"

step "Allow other apps (the iPod viewer) to start the emulator"
PROPS="$HOME/.termux/termux.properties"
mkdir -p "$(dirname "$PROPS")"
touch "$PROPS"
if grep -Eq '^[[:space:]]*allow-external-apps[[:space:]]*=[[:space:]]*true' "$PROPS"; then
    echo "already allowed"
else
    echo "allow-external-apps = true" >> "$PROPS"
    command -v termux-reload-settings >/dev/null && termux-reload-settings || true
    echo "added allow-external-apps = true to $PROPS"
fi

echo
echo "Done. Start the iPod with:  ipod start"
echo "Buttons: ipod home | power | volup | voldown     Stop: ipod stop"
