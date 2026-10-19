# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

QEMU-iOS: a fork of upstream QEMU (base version in `VERSION`, 8.2.0) that adds an emulated **iPod Touch 2G** (S5L8720 SoC, ARM1176 CPU, board N72AP). The README also mentions iPod Touch 1G support, but only the 2G machine lives in this tree. Everything outside the `ipod_touch_*` files is upstream QEMU; avoid touching it unless a change requires it.

## Build

Only the ARM system emulator is built. Run from the repo root (see `RUNNING.md` for flags on Intel Macs, Linux, and Windows):

```sh
# macOS deps: brew install glib ninja pixman pkg-config sdl2 (plus openssl@3)
mkdir build && cd build
# Apple Silicon
../configure --enable-sdl --target-list=arm-softmmu --disable-capstone --disable-pie --disable-slirp \
  --extra-cflags=-I/opt/homebrew/opt/openssl@3/include --extra-ldflags='-L/opt/homebrew/opt/openssl@3/lib -lcrypto'
make -j$(sysctl -n hw.ncpu)    # produces build/arm-softmmu/qemu-system-arm
```

- OpenSSL `-lcrypto` is required: the AES, SHA1, and PKE engine models call into it.
- SDL handles display and input. The keyboard drives the hardware buttons through `ipod_touch_key_event`, which toggles GPIO pins: **P** = power, **H** = home, **-**/**=** = volume. Key codes are defined in `include/hw/arm/ipod_touch_2g.h`. The multitouch screen takes mouse input.
- Button interrupts are level-triggered against `GPIO_INTLEVEL` in the sysic (`ipod_touch_sysic_set_gpio_level`). iOS flips a button's polarity bit after every interrupt and reads it back to tell a press from a release, so that register must keep the values iOS writes. iOS also ignores very short presses, so the key handler holds each button down for at least `BUTTON_MIN_HOLD_MS` of guest time.
- After the first configure, re-running `make` (or `ninja` in `build/`) rebuilds incrementally.

## Run

```sh
./arm-softmmu/qemu-system-arm -M iPod-Touch,bootrom=<bootrom.bin>,nand=<nand dir>,nor=<nor image> \
  -serial mon:stdio -cpu max -m 2G -d unimp
```

You need the S5L8720 bootrom, a NOR image, and a NAND directory. Download them from the `n72ap_v1` GitHub release of devos50/qemu-ios; they are not in the repo. `-d unimp` logs accesses to registers that aren't modeled yet. Emulation starts at the bootrom, which then loads the bootloader from NOR and iOS from NAND.

There are no iPod-specific tests. In practice you test by booting toward the home screen and reading the serial output and `-d unimp` logs. The upstream QEMU test suites (`make check`, etc.) still exist but don't cover the iPod hardware.

## Architecture

- **Machine:** `hw/arm/ipod_touch_2g.c` (`IPodTouchMachineState`; type `TYPE_IPOD_TOUCH` = `"iPod-Touch"`). `ipod_touch_machine_init` builds the SoC by hand. It instantiates every peripheral with `qdev_new`/`sysbus_create_simple`, maps it at a fixed `*_MEM_BASE`, and connects its IRQ to one of two PL192 VICs (`hw/intc/pl192.c`) via `s5l8900_get_irq`. All MMIO bases and IRQ numbers are in `include/hw/arm/ipod_touch_2g.h`. The bootrom, NOR, and NAND paths are QOM string properties on the machine.
- **Peripherals:** one device per file, `hw/arm/ipod_touch_<name>.c` with its header in `include/hw/arm/`. Most are reverse-engineered register models whose QOM type names start with `ipodtouch.`. The UARTs reuse upstream `exynos4210_uart`, and DMA reuses `pl080`.
- **Buses and child devices:**
  - SPI (`ipod_touch_spi.c`): `set_spi_base(n)` must be called before each controller is created, because the global it sets decides which child device gets attached. SPI0 gets the NOR flash (`ipod_touch_nor_spi.c`), and SPI4 gets the multitouch controller (`ipod_touch_multitouch.c`), which also needs pointers to sysic and gpio for its interrupts.
  - I2C (`hw/i2c/ipod_touch_i2c.c`, the only iPod file outside `hw/arm`): I2C0 carries the PMU (`pcf50633`, 0x73) and the accelerometer (`lis302dl`, 0x1D). I2C1 carries the light sensor (`isl29003dl`, 0x44) and Mikey (`cd3272mikey`, 0x39). The `cs42l58` audio codec is commented out and not compiled.
  - NAND: `ipod_touch_fmss.c` reads pages lazily from `<nand>/cs<N>/<page>.page`.
  - Display pipeline: LCD, MIPI-DSI, scaler/CSC, MBX (GPU stub), and TV-out.
- **Build wiring:** `CONFIG_IPOD_TOUCH_2G` (`hw/arm/Kconfig`, enabled in `configs/devices/arm-softmmu/default.mak`) selects `PL192`. To add a peripheral, create the `.c`/`.h` pair, add the `.c` to the `CONFIG_IPOD_TOUCH_2G` file list in `hw/arm/meson.build` (or `hw/i2c/meson.build` for I2C), and then instantiate and map it in `ipod_touch_machine_init`.

## Conventions

The upstream rules in `docs/devel/style.rst` apply. `scripts/checkpatch.pl` checks upstream style, but the iPod files don't follow it strictly (they mix tabs and spaces and use `//` comments), so match the file you're editing. Register models usually call `hw_error(...)` on an access to an unknown register, which aborts the emulator. A guest crash at a new MMIO offset therefore usually means that register needs to be modeled.

## Android (Termux)

`scripts/android/setup.sh` is the one-shot entry point: it downloads the `n72ap_v1` firmware into `~/ipod/`, builds, symlinks `scripts/android/ipod` into `$PREFIX/bin`, and sets `allow-external-apps` so other apps can start the emulator through Termux's `RUN_COMMAND` intent. `ipod start|stop|status|home|power|…` runs the emulator in the background (pid and log in `~/ipod/`). Underneath, `scripts/android/termux-build.sh` builds natively into `build-termux/`, using `--enable-pie` because Android requires position-independent executables, and `scripts/android/run-ipod.sh` runs the emulator on Termux:X11 through SDL, or over VNC on `localhost:5900`. User-facing steps are in `RUNNING.md`. It builds on a Galaxy Note 8 (Android 9, Termux, Python 3.14). Things that were needed to get there:
- `meson.build` maps host OS `android` to `linux`, because Python 3.13+ reports `android` and QEMU otherwise drops all Linux code paths.
- Newer Termux sysroots export libc functions that bionic declares only for higher API levels than Termux targets (`close_range`, `copy_file_range`, `syncfs`, `sync_file_range`, `getrandom`). Their `cc.has_function` checks in `meson.build` therefore pass a `prefix:` with the header, which makes meson require a declaration. Add a prefix the same way if another "call to undeclared function" error shows up.
- `fsdev/9p-marshal.h` undefines bionic's `st_*time_nsec` macros (Termux patch 0003).
- The script disables features that clash with bionic or Termux headers and that the iPod doesn't use: vhost, vduse, virtfs, OpenGL/EGL, GTK, the D-Bus display, tools, the guest agent and KVM. It also runs `pip install distlib`, because recent pip no longer bundles `distlib.version`.

- **Merged from [canadacow/qemu-ios](https://github.com/canadacow/qemu-ios)** (September 2026, same devos50 base):
  - BCM4325 Wi-Fi in `ipod_touch_sdio.c`. It is attached to `nd_table[0]`, so `run-ipod.sh` passes `-nic user`; the Termux build needs `--enable-slirp` and `libslirp`.
  - Persistent NAND writes, which need a flat NAND image (`ipod_touch_fmss.c`/`.h`).
  - `include/hw/arm/ipod_touch_debug.h`, which redefines `printf` in the device models to print nothing unless built with `-DIPOD_TOUCH_DEBUG=1`.
  - Once-per-register warnings for unmodelled reads.

  We left out canadacow's device bezel (an iPod frame picture with clickable buttons, `ipod_touch_bezel.h`): the image's origin and license are unknown, and the viewer app has its own buttons.
- **Flat NAND image:** `scripts/android/nand-to-image.py` packs `nand/cs<N>/<page>.page` into it.
  - One 4160-byte record per `(cs, page)` at `(cs * 524288 + page) * 4160`.
  - Then a presence bitmap, one bit per record, LSB first; a clear bit reads as an erased page.
  - Then a zeroed logical-page map. The file is truncated to `NAND_IMAGE_LOGICAL_AREA`.
  - The file is sparse.
  - `ipod` copies the image (`cp --sparse=always`) to `~/ipod/backups/nand-<date>.img` before each start and keeps `IPOD_BACKUPS` (default 3). `ipod restore` copies one back. A killed emulator can leave iOS's filesystem unbootable, and the script can't tell which backup booted, hence several generations.

For new bionic failures, port the matching patch from the Termux `qemu-system-x86-64-headless` recipe, or disable the unused feature.
