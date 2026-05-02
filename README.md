# bitreich-radio

Listen to [Bitreich Radio](gopher://bitreich.org/1/radio) from your terminal
via the Gopher protocol.

Uses [sacc](gopher://bitreich.org/1/scm/sacc) (a terminal gopher client) with
a custom plumber that pipes audio streams through
[mpv](https://mpv.io).

Works on **macOS**, **Linux**, and **Windows** (via WSL or MSYS2).

## Requirements

### Build dependencies (for compiling sacc)

| Dependency | Purpose |
|---|---|
| C compiler (cc/gcc/clang) | Build sacc |
| make | Build system |
| libtls (LibreSSL) | TLS support for `gophers://` |
| ncurses/curses | Terminal UI |

### Runtime dependencies

| Dependency | Purpose |
|---|---|
| **mpv** | Audio playback |
| **curl** | Downloading sacc source during install |

### Installing dependencies by platform

**macOS (Homebrew):**
```sh
xcode-select --install   # compiler + make
brew install libressl mpv
```

**Debian / Ubuntu:**
```sh
sudo apt install build-essential libtls-dev libncurses-dev mpv curl
```

**Fedora:**
```sh
sudo dnf install gcc make libressl-devel ncurses-devel mpv curl
```

**Arch Linux:**
```sh
sudo pacman -S base-devel libressl mpv curl
```

**Void Linux:**
```sh
sudo xbps-install base-devel libtls-devel ncurses-devel mpv curl
```

**Nix / NixOS:**
```sh
nix-shell -p libressl mpv curl gnumake gcc ncurses
```

**Windows (WSL) — recommended:**
```powershell
# 1. Install WSL if you haven't
wsl --install -d Ubuntu

# 2. Inside WSL, install dependencies
sudo apt install build-essential libtls-dev libncurses-dev mpv curl
```

**Windows (MSYS2) — alternative:**
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
```

The installer auto-detects your platform (macOS / Linux / WSL / MSYS2) and will:
1. Download the sacc 1.07 source
2. Patch it with the bundled `config.h` (sets `sacc-plumber.sh` as the plumber)
3. Compile sacc with TLS support
4. Install `sacc`, `sacc-plumber.sh`, and `radio` to `/usr/local/bin`

To install to a different prefix (no sudo needed):
```sh
PREFIX=~/.local ./install.sh
```

## Windows notes

### WSL (recommended)

WSL is the easiest way to run this on Windows. After installing dependencies
inside your WSL distro, just run `./install.sh` and `radio` as normal.

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
radio
```

This opens the Bitreich Radio lawn in sacc. Navigate with vi keys (`j`/`k`),
select a stream with `l`, and mpv will start playing audio in the background.
Press `q` to quit — any running mpv instance is cleaned up automatically.

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
radio (shell script)
  |-- sacc (gopher client, connects to gophers://bitreich.org/1/radio/lawn)
       |-- sacc-plumber.sh (handles URLs selected in sacc)
            |-- mpv --no-video (plays audio streams)
```

- `radio` — entry point; launches sacc pointing at the Bitreich Radio gopher
  page; cleans up mpv on exit.
- `sacc` — terminal gopher client compiled with `sacc-plumber.sh` as its
  plumber (configured at compile-time in `config.h`).
- `sacc-plumber.sh` — when you select a link in sacc, this script is invoked.
  Audio files and HTTP(S) URLs are played with mpv. Everything else is opened
  with `xdg-open` (Linux), `open` (macOS), or falls back to printing the URL.

### The plumbing in detail

sacc uses a **plumber** to handle non-directory items (audio streams, URLs,
files, etc.). By default, sacc ships with `xdg-open` as its plumber:

```c
/* default plumber */
static char *plumber = "xdg-open";
```

This is a **compile-time** setting in sacc's `config.h` — it gets baked into
the binary. To make radio streams work, we change it to our custom plumber:

```c
/* default plumber */
static char *plumber = "sacc-plumber.sh";
```

The bundled `config.h` in this repo already has this change applied.
The installer copies it into sacc's source tree before compiling, so you
don't have to edit anything manually.

If you're building sacc yourself (without the installer), you need to make
this change in `config.h` before running `make`.

When you select any non-directory item in sacc, it invokes
`sacc-plumber.sh <url>`. The plumber script then:

1. Checks if the URL matches an audio pattern (`.mp3`, `.ogg`, `.flac`, etc.)
   or is an HTTP(S) URL
2. If yes: kills any previously playing mpv, launches `mpv --no-video` in the
   background, and saves the PID for cleanup
3. If no: opens the URL with the system opener (`xdg-open` / `open`)

sacc follows the suckless philosophy — read the manpage (`man sacc`) after
installing to understand all the options, keybindings, and how plumbing works.
The source is short and readable; `config.h` is where all user customization
happens.

## Further reading

After installing, read the sacc manpage:

```sh
man sacc
```

It covers all keybindings, command-line flags, and how the plumber/yanker
system works. sacc is a suckless-style program — all configuration lives in
`config.h` and requires recompilation. If you want to tweak keybindings,
change the yanker (clipboard tool), or swap the plumber for something else,
edit `config.h` and rebuild.

## Uninstall

```sh
sudo rm /usr/local/bin/radio /usr/local/bin/sacc /usr/local/bin/sacc-plumber.sh
sudo rm /usr/local/share/man/man1/sacc.1
```

Or if you used a custom prefix:
```sh
rm ~/.local/bin/radio ~/.local/bin/sacc ~/.local/bin/sacc-plumber.sh
```

## License

The `radio` and `sacc-plumber.sh` scripts are public domain.
sacc is licensed under the ISC license — see the sacc source for details.
