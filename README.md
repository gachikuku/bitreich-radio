# bitreich-radio

Listen to [Bitreich Radio](gopher://bitreich.org/1/radio) from your terminal
via the Gopher protocol.

Uses [sacc](gopher://bitreich.org/1/scm/sacc) (a terminal gopher client) with
a custom plumber that pipes audio streams through
[mpv](https://mpv.io).

Works on **macOS**, **Linux**, and **Windows** (via WSL or MSYS2).

**No sudo required.** Everything lives inside this directory.

## Requirements

### Build dependencies (for compiling sacc)

| Dependency | Purpose |
|---|---|
| C compiler (cc/gcc/clang) | Build sacc |
| make | Build system |
| libtls (libretls or LibreSSL) | TLS support for `gophers://` |
| ncurses/curses | Terminal UI |

### Runtime dependencies

| Dependency | Purpose |
|---|---|
| **mpv** | Audio playback |
| **git** | Cloning sacc source during install |

### Installing dependencies by platform

**macOS (Homebrew):**
```sh
xcode-select --install   # compiler + make
brew install libressl mpv
```

**Debian / Ubuntu:**
```sh
sudo apt install build-essential libtls-dev libncurses-dev mpv git
```

**Fedora:**
```sh
sudo dnf install gcc make libressl-devel ncurses-devel mpv git
```

**Arch Linux:**
```sh
sudo pacman -S base-devel libressl mpv git
```

**Void Linux:**
```sh
sudo xbps-install base-devel libtls-devel ncurses-devel mpv git
```

**Nix / NixOS:**
```sh
nix-shell -p libressl mpv git gnumake gcc ncurses
```

**Windows (WSL) -- recommended:**
```powershell
# 1. Install WSL if you haven't
wsl --install -d Ubuntu

# 2. Inside WSL, install dependencies
sudo apt install build-essential libtls-dev libncurses-dev mpv git
```

**Windows (MSYS2) -- alternative:**
```sh
# In MSYS2 UCRT64 shell
pacman -S mingw-w64-ucrt-x86_64-gcc make curl mingw-w64-ucrt-x86_64-mpv \
          mingw-w64-ucrt-x86_64-libressl mingw-w64-ucrt-x86_64-ncurses
```

## Install

```sh
git clone https://github.com/gachikuku/bitreich-radio.git
cd bitreich-radio
./install.sh
./radio
```

The installer auto-detects your platform (macOS / Linux / WSL / MSYS2) and will:
1. Clone the latest sacc source from `git://git.codemadness.org/sacc`
2. Patch it with the bundled `config.h` (sets `sacc-plumber.sh` as the plumber)
3. Compile sacc with TLS support
4. Copy the `sacc` binary into this directory
5. Clean up the temp build files

Run `./install.sh` again at any time to rebuild with the latest sacc.

No files are installed outside this directory. No sudo needed.

## Windows notes

### WSL (recommended)

WSL is the easiest way to run this on Windows. After installing dependencies
inside your WSL distro, just run `./install.sh` and `./radio` as normal.

**Audio setup:** WSL2 with Windows 11 has built-in audio passthrough via
PulseAudio/PipeWire. On older setups you may need to install PulseAudio on
the Windows side and configure `PULSE_SERVER` in WSL:

```sh
export PULSE_SERVER=tcp:$(hostname).local
```

### MSYS2

Run the installer from an MSYS2 UCRT64 terminal. The scripts use POSIX shell
so they work under MSYS2's bash.

## Usage

```sh
cd bitreich-radio
./radio
```

This opens the Bitreich Radio lawn in sacc. Navigate with vi keys (`j`/`k`),
select a stream with `l`, and mpv will start playing audio in the background.
Press `q` to quit -- any running mpv instance is cleaned up automatically.

### Controls inside sacc

| Key | Action |
|---|---|
| `j` / `k` | Move up / down |
| `l` | Open selected item |
| `h` | Go back |
| `q` | Quit |
| `?` | Help |

## How it works

```
./radio (shell script)
  |-- ./sacc (gopher client, connects to gophers://bitreich.org/1/radio/lawn)
       |-- ./sacc-plumber.sh (handles URLs selected in sacc)
            |-- mpv --no-video (plays audio streams)
```

The `radio` script prepends its own directory to `PATH` before launching
`sacc`, so sacc can find `sacc-plumber.sh` right next to it. Everything
resolves relative to wherever you cloned the repo.

- `radio` -- entry point; launches sacc pointing at the Bitreich Radio gopher
  page; cleans up mpv on exit.
- `sacc` -- terminal gopher client compiled with `sacc-plumber.sh` as its
  plumber (configured at compile-time in `config.h`).
- `sacc-plumber.sh` -- when you select a link in sacc, this script is invoked.
  Audio files and HTTP(S) URLs are played with mpv. Everything else is opened
  with `xdg-open` (Linux), `open` (macOS), or falls back to printing the URL.

### The plumbing in detail

sacc follows the [suckless](https://suckless.org) philosophy: configuration
is done by editing C header files and recompiling. There is no runtime config
file. The relevant file is `config.h`, which sacc's Makefile copies from
`config.def.h` on first build if it doesn't exist.

By default, sacc ships with `xdg-open` as its plumber (the program invoked
when you select a non-directory item):

```c
/* default plumber */
static char *plumber = "xdg-open";
```

We change it to our custom plumber so audio streams are handled by mpv:

```c
/* default plumber */
static char *plumber = "sacc-plumber.sh";
```

The bundled `config.h` in this repo already has this change applied.
The installer copies it into sacc's source tree before compiling, so you
don't have to edit anything manually.

If you're building sacc yourself (without the installer), clone the source
from `git://git.codemadness.org/sacc`, copy `config.def.h` to `config.h`,
make the plumber change above, then run `make`.

When you select any non-directory item in sacc, it invokes
`sacc-plumber.sh <url>`. The plumber script then:

1. Checks if the URL matches an audio pattern (`.mp3`, `.ogg`, `.flac`, etc.)
   or is an HTTP(S) URL
2. If yes: kills any previously playing mpv, launches `mpv --no-video` in the
   background, and saves the PID for cleanup
3. If no: opens the URL with the system opener (`xdg-open` / `open`)

### Customizing sacc

sacc is configured entirely through `config.h`. You can change:

- **Plumber** -- the program that handles non-directory items (we set
  `sacc-plumber.sh`)
- **Yanker** -- the clipboard program for yanking URIs (`pbcopy` on macOS,
  `xclip` on Linux)
- **Keybindings** -- vi-style by default (`h`/`j`/`k`/`l`)
- **Modal plumber** -- whether sacc waits for the plumber to return (we
  set this to 0 so audio plays in the background)

Edit `config.h` in this repo, then run `./install.sh` again to rebuild.

sacc also supports multiple UI backends via `config.mk`:
- `UI=ti` -- default screen-oriented UI (uses curses)
- `UI=txt` -- plain text UI
- `UI=rogue` -- roguelike dungeon UI (experimental, see `ui_rogue_readme`
  in sacc source)

And two IO backends:
- `IO=tls` -- TLS support via libtls (required for `gophers://`)
- `IO=clr` -- plain gopher, no TLS

## Further reading

Read the sacc manpage for full documentation:

```sh
man sacc
```

It covers all keybindings, command-line flags, environment variables
(`PAGER`, `SACC_CERT_DIR`), and how the plumber/yanker system works.

- sacc source: `git://git.codemadness.org/sacc`
- sacc web: https://codemadness.org/git/sacc/log.html

## Uninstall

Just delete the directory:

```sh
rm -rf bitreich-radio
```

Nothing was installed anywhere else on your system.

## License

The `radio` and `sacc-plumber.sh` scripts are public domain.
sacc is licensed under the ISC license -- see the sacc source for details.
