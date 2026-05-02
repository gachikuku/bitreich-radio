#!/bin/sh

# bitreich-radio installer
# Clones sacc, patches config.h, builds, drops binary here.
# No sudo. No system-wide install. POSIX shell.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SACC_GIT="git://git.codemadness.org/sacc"
BUILD_DIR="$(mktemp -d)"
OS="$(uname -s)"

sed_inplace() {
    _file="$1"
    shift
    _tmp="${_file}.tmp"
    sed "$@" "$_file" > "$_tmp" && mv "$_tmp" "$_file"
}

# find_libtls: sets TLS_INCDIR and TLS_LIBDIR.
# Prefers libretls (OpenSSL-backed, better CA handling) over libressl.
find_libtls() {
    TLS_INCDIR=""
    TLS_LIBDIR=""

    # 1. Nix: libretls first (OpenSSL-backed, best CA handling), then libressl
    for _pattern in "libretls" "libressl"; do
        _dir="$(ls -d /nix/store/*${_pattern}*/include/tls.h 2>/dev/null | sort -V | tail -1)"
        if [ -n "$_dir" ]; then
            _base="$(dirname "$(dirname "$_dir")")"
            TLS_INCDIR="${_base}/include"
            TLS_LIBDIR="${_base}/lib"
            [ -d "$TLS_INCDIR" ] && [ -d "$TLS_LIBDIR" ] && return 0
        fi
    done
    # libressl splits into -dev (headers) and lib (libraries)
    _dev="$(ls -d /nix/store/*libressl*-dev/include/tls.h 2>/dev/null | sort -V | tail -1)"
    if [ -n "$_dev" ]; then
        TLS_INCDIR="$(dirname "$_dev")"
        _pc="$(ls /nix/store/*libressl*-dev/lib/pkgconfig/libtls.pc 2>/dev/null | sort -V | tail -1)"
        if [ -n "$_pc" ]; then
            TLS_LIBDIR="$(sed -n 's/^libdir=//p' "$_pc")"
            [ -n "$TLS_INCDIR" ] && [ -n "$TLS_LIBDIR" ] && return 0
        fi
    fi

    # 2. pkg-config
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libtls 2>/dev/null; then
        TLS_INCDIR="$(pkg-config --variable=includedir libtls 2>/dev/null)"
        TLS_LIBDIR="$(pkg-config --variable=libdir libtls 2>/dev/null)"
        return 0
    fi

    # 3. Homebrew
    for _prefix in /opt/homebrew/opt/libressl /usr/local/opt/libressl; do
        if [ -f "${_prefix}/include/tls.h" ]; then
            TLS_INCDIR="${_prefix}/include"
            TLS_LIBDIR="${_prefix}/lib"
            return 0
        fi
    done

    # 4. System paths
    for _inc in /usr/include /usr/local/include; do
        if [ -f "${_inc}/tls.h" ]; then
            TLS_INCDIR="$_inc"
            TLS_LIBDIR="$(dirname "$_inc")/lib"
            return 0
        fi
    done

    return 1
}

echo "==> bitreich-radio installer"

# --- Check tools ---
missing=""
for cmd in mpv cc make git; do
    command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
done
if [ -n "$missing" ]; then
    echo "ERROR: missing:$missing"
    exit 1
fi

# --- Find libtls ---
if ! find_libtls; then
    echo "ERROR: libtls not found."
    echo ""
    case "$OS" in
        Darwin) echo "  brew install libressl   # or: nix-env -iA nixpkgs.libretls" ;;
        *)      echo "  apt install libtls-dev  # or equivalent for your distro" ;;
    esac
    exit 1
fi
echo "    libtls: ${TLS_LIBDIR}"

# --- Clone and build sacc ---
echo "==> Building sacc..."
cd "$BUILD_DIR"
git clone --depth 1 -q "$SACC_GIT" sacc
cd sacc

# Patch config.h: set plumber and yanker
cp "${SCRIPT_DIR}/config.h" ./config.h

# Set build flags: TLS enabled, correct include/lib paths
sed_inplace config.mk 's/^#*IO = .*/IO = tls/'
sed_inplace config.mk 's/^#*IOLIBS = .*/IOLIBS = -ltls/'
sed_inplace config.mk 's/^#*IOCFLAGS = .*/IOCFLAGS = -DUSE_TLS/'

case "$OS" in
    Linux)
        sed_inplace config.mk "s|^OSCFLAGS = .*|OSCFLAGS = -D_DEFAULT_SOURCE -D_XOPEN_SOURCE=700 -D_BSD_SOURCE -D_GNU_SOURCE -I${TLS_INCDIR}|"
        ;;
    *)
        sed_inplace config.mk "s|^OSCFLAGS = .*|OSCFLAGS = -I${TLS_INCDIR}|"
        ;;
esac
sed_inplace config.mk "s|^OSLDFLAGS =.*|OSLDFLAGS = -L${TLS_LIBDIR}|"

if ! make >/dev/null 2>&1; then
    echo "ERROR: build failed:"
    make
    exit 1
fi

cp sacc "${SCRIPT_DIR}/sacc"
chmod 755 "${SCRIPT_DIR}/sacc"
rm -rf "$BUILD_DIR"

echo ""
echo "Done! Run './radio' to listen."
