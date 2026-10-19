# Installing the iPod touch 2G emulator on Android

This tree (devos50's qemu-ios, QEMU 8.2, plus our Android changes) builds and runs natively on the phone inside Termux. It shows the iPod's screen over VNC. You can view it in any VNC viewer, or in the companion **iDevice** viewer app (`../ipod-viewer`; formerly "iPod Touch"), which adds Home, Power and volume buttons. It's been tested on a Galaxy Note 8 (Android 9) and a Galaxy Z Fold6 (Android 16).

## 1. Requirements

- **CPU:** a 64-bit ARM phone (`arm64-v8a`). Check from a computer with `adb shell getprop ro.product.cpu.abilist`.
- **Android:** 7.0 or newer, since current Termux needs it.
- **RAM:** about 3 GB or more is comfortable. The build is the memory-hungry part; on 2 GB phones, build with `make -j2`.
- **Free storage:** 4–10 GB in total:
  - Termux packages, the source and the build folder: about 2–3 GB
  - the firmware: 530 MB unpacked NAND, plus `nand.img` with 1–3 GB of real disk use
  - up to 3 automatic backups, each about the size of `nand.img`
- **Termux** from [F-Droid](https://f-droid.org/packages/com.termux/) or its GitHub releases. **Not the Play Store version**, which is outdated and can't install the packages.
- Optional: Termux:Widget, for home-screen shortcuts.

### Android 12 and newer: allow background processes

Android 12+ kills processes that apps like Termux start in the background (the "phantom process killer"). Both the build and the emulator run that way. Turn it off once:

- **Android 14+:** Developer options → **Disable child process restrictions**.
- **Android 12–13** (or any version), from a computer with adb:

  ```sh
  adb shell settings put global settings_enable_monitor_phantom_procs false
  ```

  Set it back to `true` to undo.

## 2. Get the source onto the phone

Our Android changes exist only in this local tree, not in devos50's GitHub repository. So copy this tree, not a fresh clone. On the Mac, from the folder that contains `qemu-ios`:

```sh
COPYFILE_DISABLE=1 tar --exclude='.git' --exclude='build' --exclude='build-termux' \
    -czf qemu-ios.tgz qemu-ios
adb push qemu-ios.tgz /sdcard/Download/
```

In Termux on the phone:

```sh
termux-setup-storage            # allow storage access, tap Allow
tar xzf ~/storage/downloads/qemu-ios.tgz -C ~
```

## 3. Run the setup

```sh
bash ~/qemu-ios/scripts/android/setup.sh
```

`setup.sh` does everything in one go, and skips any step that's already done. You can run it again any time.

1. Downloads the firmware from devos50's `n72ap_v1` release into `~/ipod/` (about 250 MB):
   - `bootrom_240_4`
   - `nor_n72ap.bin`
   - `nand_n72ap.zip`, unpacked to `~/ipod/nand`
2. Packs the NAND into the flat image `~/ipod/nand.img` with `scripts/android/nand-to-image.py`. The iPod saves its changes into this image. `~/ipod/nand` stays as the untouched original.
3. Builds the emulator with `scripts/android/termux-build.sh`: Termux packages, `configure`, then `make` into `build-termux/`. This takes 20–40 minutes on older phones.
4. Links the `ipod` command into `$PREFIX/bin`.
5. Adds `allow-external-apps = true` to `~/.termux/termux.properties`, so the viewer app may start the emulator.

After updating the source, run `setup.sh --rebuild`. It reconfigures and rebuilds; `ipod update` only runs `make`.

## 4. Use it

```sh
ipod start        # start in the background and open a VNC viewer on localhost:5900
ipod home         # also: power, volup, voldown; optional hold time in ms, e.g. "ipod power 3000"
ipod status       # running or stopped
ipod log          # follow the emulator output (~/ipod/ipod.log)
ipod stop         # quit the emulator
ipod update       # rebuild after changing the source
ipod reset        # factory reset: rebuild nand.img from ~/ipod/nand (asks first)
ipod backups      # list automatic backups
ipod restore [n]  # roll back to a backup (asks which one)
```

| Variable | Default | Meaning |
|---|---|---|
| `IPOD_NAND` | `~/ipod/nand.img`, else `~/ipod/nand` | NAND image or page folder. The folder is read-only, so changes aren't saved. |
| `IPOD_BOOTROM` | `~/ipod/bootrom_240_4` | SecureROM |
| `IPOD_NOR` | `~/ipod/nor_n72ap.bin` | NOR image |
| `IPOD_BACKUPS` | `3` | How many automatic backups to keep. `0` turns them off. |

**Controls:** tap the screen to touch. With a keyboard, `h` is Home, `p` is Power, and `-` / `=` are volume down / up.

**Wi-Fi:** the iPod's Wi-Fi uses QEMU's user-mode network. Join the network in Settings → Wi-Fi.

**Backups:** before each start, `ipod` copies `nand.img` to `~/ipod/backups/nand-<date>.img` and keeps the newest ones. The script can't tell whether a state boots. If one session left the iPod unbootable, restore a backup from before that session.

### Shut down safely

- `ipod stop` ends the emulator immediately, which for the iPod is like pulling the battery. That can leave iOS unable to boot. **First turn the iPod off:** hold Power (`ipod power 3000`, or hold the app's Power button), slide to power off, and wait until the screen is black.
- **Avoid short Power taps.** They put the iPod to sleep, and waking it up doesn't work yet.

## 5. The viewer app (optional)

`../ipod-viewer` is a fork of the AVNC viewer:
- When it opens, it starts the emulator through Termux (`ipod start --no-viewer`) and connects.
- One finger acts as the touchscreen.
- It has a bar with Vol−, Home, Power and Vol+, and a "Shut down device" entry in its side toolbar.

Build and install it from the Mac, as described in `../ipod-viewer/IPOD.md`:

```sh
cd ../ipod-viewer
git submodule update --init
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
PATH="$PWD/tools/host-bin:$PATH" ./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Then, on the phone:

1. Fully close Termux once, so it rereads `termux.properties`.
2. Open **iDevice** and allow the "Run commands in Termux environment" permission.

Any other VNC viewer works too: run `ipod start`, then connect to `localhost:5900`.

## 6. Troubleshooting

- **Build fails with `call to undeclared function 'xyz'`:**
  - **Cause:** newer Termux toolchains export libc functions that bionic only declares for newer Android versions.
  - **Fix:** in `meson.build`, give that function's `cc.has_function(...)` check a `prefix:` with its header. `close_range`, `copy_file_range`, `syncfs`, `sync_file_range` and `getrandom` are already handled this way. Then run `setup.sh --rebuild`.
- **Other build errors:** port the matching patch from Termux's `qemu-system-x86-64-headless` package, or disable the unused feature in `scripts/android/termux-build.sh`.
- **Stuck at the Apple logo after an unclean stop:** wait a few minutes first, since iOS may be repairing its filesystem. Then try `ipod restore`, or as a last resort `ipod reset`.
- **Boot from the untouched original, saving nothing:** `IPOD_NAND=~/ipod/nand ipod start`.
- **Logs:** `~/ipod/ipod.log` (or `ipod log`).
- **Emulator vanishes in the background:** check the background-process setting from section 1, and that `ipod start` took its wake lock (Termux shows a notification).
