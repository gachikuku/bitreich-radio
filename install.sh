#!/bin/sh

# bitreich-radio installer
# Downloads sacc source, patches it with our plumber, builds it,
# and places the binary right here in this directory. No sudo needed.
#
# POSIX-compliant -- works with sh, dash, bash, zsh, ksh, mksh, etc.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SACC_GIT="git://git.codemadness.org/sacc"
BUILD_DIR="$(mktemp -d)"
OS="$(uname -s)"

# sed_inplace: portable in-place sed (POSIX has no sed -i)
sed_inplace() {
    _file="$1"
    shift
    _tmp="${_file}.sedtmp"
    sed "$@" "$_file" > "$_tmp" && mv "$_tmp" "$_file"
}

echo "==> bitreich-radio installer"
echo "    Detected OS: ${OS}"
echo ""

# --- Detect platform ---
case "$OS" in
    Darwin)  PLATFORM="macos" ;;
    Linux)   PLATFORM="linux" ;;
    MINGW*|MSYS*|CYGWIN*)  PLATFORM="windows" ;;
    *)
        echo "WARNING: Unrecognized OS '$OS' -- proceeding as Linux-like."
        PLATFORM="linux"
        ;;
esac

# WSL detection
if [ "$PLATFORM" = "linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
    PLATFORM="wsl"
    echo "    Detected WSL (Windows Subsystem for Linux)"
fi

# --- Check dependencies ---
missing=""
for cmd in mpv cc make git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing="$missing $cmd"
    fi
done

if [ -n "$missing" ]; then
    echo "ERROR: Missing required tools:$missing"
    echo ""
    case "$PLATFORM" in
        macos)
            echo "Install with: brew install mpv"
            echo "For compiler: xcode-select --install"
            ;;
        linux|wsl)
            echo "On Debian/Ubuntu: sudo apt install build-essential mpv git"
            echo "On Fedora:        sudo dnf install gcc make mpv git"
            echo "On Arch:          sudo pacman -S base-devel mpv git"
            ;;
        windows)
            echo "Install MSYS2 from https://www.msys2.org and run:"
            echo "  pacman -S mingw-w64-x86_64-gcc make git mingw-w64-x86_64-mpv"
            ;;
    esac
    exit 1
fi

# --- Check for TLS library (required for gophers://) ---
# Bitreich radio uses gophers:// which needs libtls.
# sacc must be compiled with IO=tls and -DUSE_TLS.
tls_ok=0
if pkg-config --exists libtls 2>/dev/null; then
    tls_ok=1
elif [ -f /usr/include/tls.h ] || [ -f /usr/local/include/tls.h ] || \
     [ -f /opt/homebrew/include/tls.h ] || [ -f /usr/include/libressl/tls.h ]; then
    tls_ok=1
fi

if [ "$tls_ok" = "0" ]; then
    echo "ERROR: libtls not found."
    echo ""
    echo "Bitreich radio connects over gophers:// (TLS) so libtls is required."
    echo "Install libressl/libtls for your platform:"
    echo ""
    case "$PLATFORM" in
        macos)   echo "  brew install libressl" ;;
        linux|wsl)
            echo "  Debian/Ubuntu: sudo apt install libtls-dev"
            echo "  Fedora:        sudo dnf install libressl-devel"
            echo "  Arch:          sudo pacman -S libressl"
            echo "  Void:          sudo xbps-install libtls-devel"
            ;;
        windows)
            echo "  MSYS2: pacman -S mingw-w64-ucrt-x86_64-libressl"
            ;;
    esac
    echo ""
    echo "Then run ./install.sh again."
    exit 1
fi

# --- Clone latest sacc source ---
echo "==> Cloning latest sacc from ${SACC_GIT}..."
cd "$BUILD_DIR"
git clone --depth 1 "$SACC_GIT" sacc
cd sacc
SACC_VERSION="$(git describe --tags 2>/dev/null || git rev-parse --short HEAD)"
echo "    sacc version: ${SACC_VERSION}"

# --- Patch config ---
echo "==> Patching config.h with bitreich-radio plumber..."
cp "${SCRIPT_DIR}/config.h" ./config.h

# Ensure TLS is enabled in config.mk (IO=tls, -DUSE_TLS, -ltls)
sed_inplace config.mk 's/^#*IO = .*/IO = tls/'
sed_inplace config.mk 's/^#*IOLIBS = .*/IOLIBS = -ltls/'
sed_inplace config.mk 's/^#*IOCFLAGS = .*/IOCFLAGS = -DUSE_TLS/'

# --- Platform-specific build flags ---
case "$PLATFORM" in
    macos)
        # Homebrew libressl paths
        LIBRESSL=""
        if [ -d /opt/homebrew/opt/libressl ]; then
            LIBRESSL="/opt/homebrew/opt/libressl"
        elif [ -d /usr/local/opt/libressl ]; then
            LIBRESSL="/usr/local/opt/libressl"
        fi
        if [ -n "$LIBRESSL" ]; then
            sed_inplace config.mk "s|^OSCFLAGS = .*|OSCFLAGS = -I${LIBRESSL}/include|"
            sed_inplace config.mk "s|^OSLDFLAGS =.*|OSLDFLAGS = -L${LIBRESSL}/lib|"
        fi
        ;;
    linux|wsl)
        if pkg-config --exists libtls 2>/dev/null; then
            TLS_CFLAGS="$(pkg-config --cflags libtls)"
            TLS_LIBS="$(pkg-config --libs libtls)"
            if [ -n "$TLS_CFLAGS" ]; then
                sed_inplace config.mk "s|^OSCFLAGS = .*|OSCFLAGS = -D_DEFAULT_SOURCE -D_XOPEN_SOURCE=700 -D_BSD_SOURCE -D_GNU_SOURCE ${TLS_CFLAGS}|"
            fi
            if [ -n "$TLS_LIBS" ]; then
                sed_inplace config.mk "s|^IOLIBS = .*|IOLIBS = ${TLS_LIBS}|"
            fi
        fi
        ;;
    windows)
        sed_inplace config.mk 's/^OSCFLAGS = .*/OSCFLAGS = -D_DEFAULT_SOURCE -D_GNU_SOURCE/'
        ;;
esac

# --- Build ---
echo "==> Building sacc..."
make clean 2>/dev/null || true
make

# --- Copy binary into the repo directory ---
echo "==> Installing sacc binary to ${SCRIPT_DIR}..."
cp sacc "${SCRIPT_DIR}/sacc"
chmod 755 "${SCRIPT_DIR}/sacc"

# --- Cleanup ---
echo "==> Cleaning up build files..."
rm -rf "$BUILD_DIR"

echo ""
echo "Done! Run './radio' from this directory to tune in."
echo "Read the sacc manpage: man sacc (or ./sacc --help)"
if [ "$PLATFORM" = "wsl" ]; then
    echo ""
    echo "NOTE (WSL): Make sure mpv and PulseAudio/PipeWire are configured"
    echo "for audio output. See README.md for WSL audio setup."
fi
