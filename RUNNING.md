## Running the iPod Touch 2G Emulator

This file contains the instructions on how to run the iPod Touch 2G emulator using QEMU.
Note that this is an experimental release and the functionality of the device is still limited.
Linux compatibility is currently unstable. Efforts are underway to improve it.

### Getting the Source Code

Clone the repository using the following commands:

```
git clone https://github.com/devos50/qemu-ios.git
cd qemu-ios
```

Now you can proceed with the rest of the instructions for building and running the emulator.

### Building QEMU

Make sure you have the required libraries installed to compile QEMU:

```
# On MacOS
brew install glib ninja pixman pkg-config sdl2

# On Linux (Ubuntu)
sudo apt install make ninja-build pkg-config libssl-dev libsdl2-dev libpixman-1-dev libpixman-1-0 libglib2.0-dev

# On Linux (Arch)
sudo pacman -S --needed make ninja pkgconf openssl sdl2 pixman glib2

# On Windows (MSYS2/mingw64)
pacman -S base-devel mingw-w64-x86_64-toolchain git python ninja mingw-w64-x86_64-glib2 mingw-w64-x86_64-pixman python-setuptools mingw-w64-x86_64-SDL2

```
Compile QEMU by running the following commands from the root directory:

```
mkdir build
cd build

# On Intel Macs
../configure --target-list=arm-softmmu --extra-cflags=-I/usr/local/opt/openssl@3/include --extra-ldflags='-L/usr/local/opt/openssl@3/lib -lcrypto'

# On Apple Silicon Macs
../configure --enable-sdl --target-list=arm-softmmu --disable-capstone --disable-pie --disable-slirp --extra-cflags=-I/opt/homebrew/opt/openssl@3/include --extra-ldflags='-L/opt/homebrew/opt/openssl@3/lib -lcrypto'

# On Linux
../configure --enable-sdl --disable-cocoa --target-list=arm-softmmu --disable-capstone --disable-slirp --extra-cflags=-I/usr/include/openssl --extra-ldflags='-lcrypto' --disable-werror --enable-pie

# On Microsoft Windows (with MINGW64)
../configure --enable-sdl --disable-cocoa --target-list=arm-softmmu --disable-capstone --disable-slirp --disable-pie --extra-cflags=-I/mingw64/include/openssl --extra-ldflags='-L/mingw64/lib -lcrypto' --disable-stack-protector --disable-werror

make
```

Note that we’re explicitly enabling compilation of the SDL library which is used for interaction with the emulator (e.g., capturing keyboard and mouse events). Also, we only configure and build the ARM emulator.
We are also linking against OpenSSL as the AES/SHA1/PKE engines use some of the library’s cryptographic functions.
Remember to update the include and library paths to the OpenSSL library in case they are located elsewhere.
You can speed up the `make` command by passing the number of available CPU cores with the `-j` flag, e.g., use `make -j6` to compile using six CPU cores.
The compilation process should produce the `qemu-system-arm` binary in the `build/arm-softmmu` directory.

### Downloading the Required Files

We need a few files to successfully boot the iPod Touch emulator to the home screen, which I published [here](https://github.com/devos50/qemu-ios/releases/tag/n72ap_v1) for convenience. You can download all these files from here, and they include the following:
- The S5L8720 bootrom binary, which is started as the very first thing when booting.
- A NOR image that contains various auxillary files used by the bootloader. I provide some instructions on how to generate this image yourself [here](https://github.com/devos50/qemu-ios-generate-nor).
- A NAND image that contains the root file system. I provide some instructions on how to generate this image yourself [here](https://github.com/devos50/qemu-ios-generate-nand).

Download all the required files and save them to a convenient location. You should unzip the `nand_n72ap.zip` file, which contains a single directory named `nand`.

### Running the Emulator

We are now ready to run the emulator from the build directory with the following command:

```
./arm-softmmu/qemu-system-arm -M iPod-Touch,bootrom=<path to bootrom>,nand=<path to NAND directory>,nor=<path to NOR directory> -serial mon:stdio -cpu max -m 2G -d unimp
```

If there are any issues running the above commands, please let me know by [opening an issue](https://github.com/devos50/qemu-ios/issues/new).

### Running on Android (Termux)

The emulator can be built and run natively on an arm64 Android device inside [Termux](https://f-droid.org/packages/com.termux/) (install it from F-Droid, not the Play Store). This is experimental.

1. Get the source into Termux's home directory, for example with `pkg install git && git clone https://github.com/KD3533/qemu-ios-for-android.git`.
2. Run the setup script. It downloads the firmware into `~/ipod/` (about 250 MB), packs the NAND into the flat image `~/ipod/nand.img` (1–3 GB of disk space), installs the dependencies, builds the emulator, and installs the `ipod` command. It is safe to re-run; finished steps are skipped. After updating the source, run it with `--rebuild`.
   ```
   bash qemu-ios/scripts/android/setup.sh
   ```
3. Install a VNC viewer, for example AVNC or bVNC.
4. Start the iPod:
   ```
   ipod start
   ```
   The emulator starts in the background, and your VNC viewer opens on `localhost:5900` once it is ready.

Controls: tap the screen for touch. With the viewer's keyboard, `h` is home, `p` is power, and `-` and `=` are volume. From Termux:
```
ipod home                # also: power, volup, voldown
ipod power 3000          # hold for 3 seconds
ipod status              # is it running?
ipod log                 # follow the emulator output
ipod stop                # shut it down
ipod update              # rebuild after changing the source
ipod reset               # factory reset: discard all changes made on the iPod
ipod backups             # list the automatic backups
ipod restore             # roll back to a backup (asks which one)
```
The iPod saves its changes (settings, photos, apps' data) into `~/ipod/nand.img`, so they survive a restart. The unpacked `~/ipod/nand` directory stays as the original, which `ipod reset` copies back. `ipod stop` ends the emulator like pulling the battery, which can leave iOS unable to boot, so turn the iPod off first (hold Power, slide to power off). Before each start, `ipod` backs up the image to `~/ipod/backups` and keeps the newest 3 (`IPOD_BACKUPS` changes the number, 0 turns backups off). Each backup takes about as much disk space as `nand.img`. If the iPod no longer boots, `ipod restore` rolls it back to the state before an earlier start. Its Wi-Fi is connected to the phone's network through QEMU's user-mode network: join the network in Settings → Wi-Fi.
`ipod` keeps a Termux wake lock while the emulator runs, so Android does not stop it in the background. The firmware paths can be changed with `IPOD_BOOTROM`, `IPOD_NAND` and `IPOD_NOR`.

#### Running by hand

`setup.sh` builds with `scripts/android/termux-build.sh`. To run in the foreground instead of with `ipod`, for example with SDL on [Termux:X11](https://github.com/termux/termux-x11) (`termux-x11 :0 &`):
```
bash qemu-ios/scripts/android/run-ipod.sh ~/ipod/bootrom_240_4 ~/ipod/nand ~/ipod/nor_n72ap.bin
```
The script uses SDL on Termux:X11 if it is running, otherwise it serves VNC on `localhost:5900`. Set `DISPLAY_MODE=vnc` to force VNC. Extra arguments are passed to QEMU, for example `-d unimp`. Keep the NAND directory in `$HOME`, not on `/sdcard`: the emulator opens one file for every NAND page read, which is slow on shared storage.

The QEMU monitor listens on a socket; `scripts/android/ipod-key.sh` sends commands to it (`ipod-key.sh monitor info status`).
