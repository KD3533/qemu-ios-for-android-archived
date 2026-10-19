#!/data/data/com.termux/files/usr/bin/bash
#
# Build the iPod Touch 2G emulator (qemu-system-arm) natively inside Termux
# on an Android device. Run from anywhere; the build goes to build-termux/.
#
# Usage: bash scripts/android/termux-build.sh [--no-deps]

set -euo pipefail

if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
    echo "error: \$PREFIX is not set; this script must run inside Termux" >&2
    exit 1
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$SRC_DIR/build-termux"

if [ "${1:-}" != "--no-deps" ]; then
    pkg update -y
    # sdl2 and termux-x11 live in the x11 repository
    pkg install -y x11-repo
    # git is needed for meson to fetch the dtc subproject
    pkg install -y clang make ninja pkg-config python python-pip git \
        glib libpixman openssl libandroid-shmem libslirp \
        sdl2 termux-x11-nightly
    # configure's mkvenv needs distlib.scripts and distlib.version; recent pip
    # no longer vendors distlib.version, so install the standalone package
    pip install distlib
fi

if ! python3 -c 'import distlib.scripts, distlib.version' 2>/dev/null; then
    echo "error: python distlib missing; run: pip install distlib" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Android only runs position-independent executables, hence --enable-pie.
# The vhost/vduse helpers and virtfs (9p) clash with bionic and, like the
# tools, guest agent and KVM, are not used by the iPod Touch machine.
# slirp provides the user-mode network behind the iPod's emulated Wi-Fi.
# Only SDL (2D) and VNC displays are built: Termux has no EGL headers, and the
# iPod LCD is rendered in software.
"$SRC_DIR/configure" \
    --target-list=arm-softmmu \
    --enable-pie \
    --enable-sdl \
    --enable-vnc \
    --disable-cocoa \
    --disable-capstone \
    --enable-slirp \
    --disable-gnutls \
    --disable-tools \
    --disable-guest-agent \
    --disable-kvm \
    --disable-vhost-user \
    --disable-vhost-kernel \
    --disable-vhost-vdpa \
    --disable-libvduse \
    --disable-vduse-blk-export \
    --disable-virtfs \
    --disable-opengl \
    --disable-gtk \
    --disable-vte \
    --disable-dbus-display \
    --disable-spice \
    --disable-virglrenderer \
    --disable-rutabaga-gfx \
    --disable-sdl-image \
    --disable-curses \
    --disable-werror \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib -lcrypto -landroid-shmem"

make -j"$(nproc)"

echo
echo "Built: $BUILD_DIR/arm-softmmu/qemu-system-arm"
"$BUILD_DIR/arm-softmmu/qemu-system-arm" -M help | grep -i ipod || {
    echo "warning: iPod-Touch machine not found in the build" >&2
    exit 1
}
