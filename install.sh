#!/bin/sh

# bitreich-radio installer
# Downloads sacc source, patches it with our plumber, builds, and installs.
# Works on macOS, Linux, and Windows (via WSL/MSYS2).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
SACC_VERSION="1.07"
SACC_HTTP_URL="https://codemadness.org/releases/sacc/sacc-${SACC_VERSION}.tar.gz"
BUILD_DIR="$(mktemp -d)"
OS="$(uname -s)"

echo "==> bitreich-radio installer"
echo "    Detected OS: ${OS}"
echo ""

# --- Detect platform ---
case "$OS" in
    Darwin)  PLATFORM="macos" ;;
    Linux)   PLATFORM="linux" ;;
    MINGW*|MSYS*|CYGWIN*)  PLATFORM="windows" ;;
    *)
        echo "WARNING: Unrecognized OS '$OS' — proceeding as Linux-like."
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
for cmd in mpv cc make curl; do
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
            echo "On Debian/Ubuntu: sudo apt install build-essential mpv curl"
            echo "On Fedora:        sudo dnf install gcc make mpv curl"
            echo "On Arch:          sudo pacman -S base-devel mpv curl"
            ;;
        windows)
            echo "Install MSYS2 from https://www.msys2.org and run:"
            echo "  pacman -S mingw-w64-x86_64-gcc make curl mingw-w64-x86_64-mpv"
            ;;
    esac
    exit 1
fi

# --- Check for TLS library (needed for gophers://) ---
tls_ok=0
if pkg-config --exists libtls 2>/dev/null; then
    tls_ok=1
elif [ -f /usr/include/tls.h ] || [ -f /usr/local/include/tls.h ] || \
     [ -f /opt/homebrew/include/tls.h ] || [ -f /usr/include/libressl/tls.h ]; then
    tls_ok=1
fi

if [ "$tls_ok" = "0" ]; then
    echo "WARNING: libtls not found. sacc will be built WITHOUT gophers:// (TLS) support."
    echo "         Bitreich radio requires TLS. Install libtls/libressl first."
    echo ""
    case "$PLATFORM" in
        macos)   echo "         brew install libressl" ;;
        linux|wsl)
            echo "         Debian/Ubuntu: sudo apt install libtls-dev"
            echo "         Fedora:        sudo dnf install libressl-devel"
            echo "         Arch:          sudo pacman -S libressl"
            echo "         Void:          sudo xbps-install libtls-devel"
            ;;
    esac
    echo ""
    printf "Continue without TLS? [y/N] "
    read -r ans
    case "$ans" in
        [yY]*) IO_TYPE="clr" ;;
        *) exit 1 ;;
    esac
else
    IO_TYPE="tls"
fi

# --- Download sacc source ---
echo "==> Downloading sacc ${SACC_VERSION}..."
cd "$BUILD_DIR"
curl -fsSL "$SACC_HTTP_URL" -o sacc.tar.gz
tar xzf sacc.tar.gz
cd "sacc-${SACC_VERSION}"

# --- Patch config ---
echo "==> Patching config.h with bitreich-radio plumber..."
cp "${SCRIPT_DIR}/config.h" ./config.h

# Adjust config.mk for IO type
if [ "$IO_TYPE" = "clr" ]; then
    sed -i.bak 's/^IO = tls/IO = clr/' config.mk
    sed -i.bak 's/^IOLIBS = -ltls/IOLIBS =/' config.mk
    sed -i.bak 's/^IOCFLAGS = -DUSE_TLS/IOCFLAGS =/' config.mk
fi

# --- Platform-specific build flags ---
case "$PLATFORM" in
    macos)
        # Homebrew libressl paths
        if [ -d /opt/homebrew/opt/libressl ]; then
            LIBRESSL="/opt/homebrew/opt/libressl"
        elif [ -d /usr/local/opt/libressl ]; then
            LIBRESSL="/usr/local/opt/libressl"
        fi
        if [ -n "$LIBRESSL" ] && [ "$IO_TYPE" = "tls" ]; then
            sed -i.bak "s|^OSCFLAGS = .*|OSCFLAGS = -I${LIBRESSL}/include|" config.mk
            sed -i.bak "s|^OSLDFLAGS =.*|OSLDFLAGS = -L${LIBRESSL}/lib|" config.mk
        fi
        ;;
    linux|wsl)
        # Linux defaults in config.mk are usually correct.
        # If libtls is from a non-standard path, detect via pkg-config.
        if [ "$IO_TYPE" = "tls" ] && pkg-config --exists libtls 2>/dev/null; then
            TLS_CFLAGS="$(pkg-config --cflags libtls)"
            TLS_LIBS="$(pkg-config --libs libtls)"
            if [ -n "$TLS_CFLAGS" ]; then
                sed -i.bak "s|^OSCFLAGS = .*|OSCFLAGS = -D_DEFAULT_SOURCE -D_XOPEN_SOURCE=700 -D_BSD_SOURCE -D_GNU_SOURCE ${TLS_CFLAGS}|" config.mk
            fi
            if [ -n "$TLS_LIBS" ]; then
                sed -i.bak "s|^IOLIBS = .*|IOLIBS = ${TLS_LIBS}|" config.mk
            fi
        fi
        ;;
    windows)
        # MSYS2/MinGW
        sed -i.bak 's/^OSCFLAGS = .*/OSCFLAGS = -D_DEFAULT_SOURCE -D_GNU_SOURCE/' config.mk
        ;;
esac

# --- Build ---
echo "==> Building sacc..."
make clean 2>/dev/null || true
make

# --- Install ---
echo "==> Installing to ${PREFIX}/bin..."

# Use sudo only if we don't own the prefix
if [ -w "${PREFIX}/bin" ] 2>/dev/null; then
    SUDO=""
else
    SUDO="sudo"
fi

$SUDO make install PREFIX="$PREFIX"
$SUDO install -m 755 "${SCRIPT_DIR}/sacc-plumber.sh" "${PREFIX}/bin/sacc-plumber.sh"
$SUDO install -m 755 "${SCRIPT_DIR}/radio" "${PREFIX}/bin/radio"

# --- Cleanup ---
echo "==> Cleaning up..."
rm -rf "$BUILD_DIR"

echo ""
echo "Done! Run 'radio' to tune in to Bitreich Radio."
if [ "$PLATFORM" = "wsl" ]; then
    echo ""
    echo "NOTE (WSL): Make sure mpv and PulseAudio/PipeWire are configured"
    echo "for audio output. See README.md for WSL audio setup."
fi
