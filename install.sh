#!/bin/sh

# bitreich-radio installer
# Clones latest sacc source, patches it with our plumber, builds it,
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

# find_libtls: locate libtls include and lib dirs across platforms.
# Sets TLS_INCDIR and TLS_LIBDIR on success, returns 1 on failure.
find_libtls() {
    TLS_INCDIR=""
    TLS_LIBDIR=""

    # 1. Try pkg-config first (works on most Linux distros and nix)
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libtls 2>/dev/null; then
        TLS_INCDIR="$(pkg-config --variable=includedir libtls 2>/dev/null)"
        TLS_LIBDIR="$(pkg-config --variable=libdir libtls 2>/dev/null)"
        if [ -n "$TLS_INCDIR" ] && [ -n "$TLS_LIBDIR" ]; then
            return 0
        fi
        # fallback: parse cflags/libs
        TLS_INCDIR="$(pkg-config --cflags libtls 2>/dev/null | sed -n 's/.*-I\([^ ]*\).*/\1/p')"
        TLS_LIBDIR="$(pkg-config --libs libtls 2>/dev/null | sed -n 's/.*-L\([^ ]*\).*/\1/p')"
        # even if dirs are empty, pkg-config found it -- system paths
        return 0
    fi

    # 2. Nix store (nix-darwin, NixOS, nix profile)
    #    Nix splits libressl into multiple outputs (-dev, -bin, lib).
    #    The -dev output has lib/pkgconfig/libtls.pc which contains
    #    the correct libdir and includedir paths for all outputs.
    #    We find the .pc file and parse it directly.
    if [ -d /nix/store ]; then
        _nix_pc="$(ls /nix/store/*libressl*-dev/lib/pkgconfig/libtls.pc 2>/dev/null | sort -V | tail -1)"
        if [ -n "$_nix_pc" ]; then
            TLS_INCDIR="$(sed -n 's/^includedir=//p' "$_nix_pc")"
            TLS_LIBDIR="$(sed -n 's/^libdir=//p' "$_nix_pc")"
            if [ -n "$TLS_INCDIR" ] && [ -n "$TLS_LIBDIR" ]; then
                return 0
            fi
        fi
    fi

    # 3. Homebrew (macOS)
    for _prefix in /opt/homebrew/opt/libressl /usr/local/opt/libressl; do
        if [ -f "${_prefix}/include/tls.h" ]; then
            TLS_INCDIR="${_prefix}/include"
            TLS_LIBDIR="${_prefix}/lib"
            return 0
        fi
    done

    # 4. Standard system paths
    for _inc in /usr/include /usr/local/include; do
        if [ -f "${_inc}/tls.h" ]; then
            TLS_INCDIR="$_inc"
            # lib is usually the sibling
            _base="$(dirname "$_inc")"
            TLS_LIBDIR="${_base}/lib"
            return 0
        fi
    done

    return 1
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

# --- Find libtls (required for gophers://) ---
# Bitreich radio uses gophers:// which needs libtls.
# sacc must be compiled with IO=tls and -DUSE_TLS.
echo "==> Looking for libtls..."
if ! find_libtls; then
    echo "ERROR: libtls not found."
    echo ""
    echo "Bitreich radio connects over gophers:// (TLS) so libtls is required."
    echo "Install libressl/libtls for your platform:"
    echo ""
    case "$PLATFORM" in
        macos)
            echo "  brew install libressl"
            echo "  -- or with nix: nix-env -iA nixpkgs.libressl"
            ;;
        linux|wsl)
            echo "  Debian/Ubuntu: sudo apt install libtls-dev"
            echo "  Fedora:        sudo dnf install libressl-devel"
            echo "  Arch:          sudo pacman -S libressl"
            echo "  Void:          sudo xbps-install libtls-devel"
            echo "  Nix:           nix-env -iA nixpkgs.libressl"
            ;;
        windows)
            echo "  MSYS2: pacman -S mingw-w64-ucrt-x86_64-libressl"
            ;;
    esac
    echo ""
    echo "Then run ./install.sh again."
    exit 1
fi

echo "    Found: include=${TLS_INCDIR:-system} lib=${TLS_LIBDIR:-system}"

# --- Clone latest sacc source ---
echo "==> Cloning latest sacc..."
cd "$BUILD_DIR"
git clone --depth 1 -q "$SACC_GIT" sacc
cd sacc
SACC_VERSION="$(git describe --tags 2>/dev/null || git rev-parse --short HEAD)"
echo "    sacc version: ${SACC_VERSION}"

# --- Patch config ---
echo "==> Patching sacc for bitreich-radio..."
cp "${SCRIPT_DIR}/config.h" ./config.h

# Patch io_tls.c: use TOFU (Trust On First Use) for gophers://.
# In parseurl_tls(), change the initial TLS mode from TLS_ON to
# TLS_PEM so sacc auto-accepts and saves server certs on first
# connect. Only patch the gophers URL parser (line after the
# strncmp "gophers" check), not the one in connect_tls() that
# switches back to TLS_ON after saving the cert.
_tmp="io_tls.c.patchtmp"
awk '/strncmp\(url, "gophers"/{f=1} f && /tls = TLS_ON/{sub(/TLS_ON/, "TLS_PEM"); f=0} 1' io_tls.c > "$_tmp" && mv "$_tmp" io_tls.c

# Ensure TLS is enabled in config.mk (IO=tls, -DUSE_TLS, -ltls)
sed_inplace config.mk 's/^#*IO = .*/IO = tls/'
sed_inplace config.mk 's/^#*IOLIBS = .*/IOLIBS = -ltls/'
sed_inplace config.mk 's/^#*IOCFLAGS = .*/IOCFLAGS = -DUSE_TLS/'

# --- Set include/lib paths from find_libtls ---
if [ -n "$TLS_INCDIR" ]; then
    case "$PLATFORM" in
        linux|wsl)
            sed_inplace config.mk "s|^OSCFLAGS = .*|OSCFLAGS = -D_DEFAULT_SOURCE -D_XOPEN_SOURCE=700 -D_BSD_SOURCE -D_GNU_SOURCE -I${TLS_INCDIR}|"
            ;;
        *)
            sed_inplace config.mk "s|^OSCFLAGS = .*|OSCFLAGS = -I${TLS_INCDIR}|"
            ;;
    esac
fi
if [ -n "$TLS_LIBDIR" ]; then
    sed_inplace config.mk "s|^OSLDFLAGS =.*|OSLDFLAGS = -L${TLS_LIBDIR}|"
fi

# --- Build ---
echo "==> Building sacc..."
make clean >/dev/null 2>&1 || true
if ! make >/dev/null 2>&1; then
    echo "ERROR: Build failed. Re-running with output:"
    make
    exit 1
fi

# --- Copy binary into the repo directory ---
cp sacc "${SCRIPT_DIR}/sacc"
chmod 755 "${SCRIPT_DIR}/sacc"

# --- Cleanup ---
rm -rf "$BUILD_DIR"

echo ""
echo "Done! Run './radio' from this directory to tune in."
