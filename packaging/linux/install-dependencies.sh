#!/bin/sh
set -eu

APP_DIR=${1:-"$HOME/.local/share/rtl-explorer"}
INSTALL_MODE=${2:-user}
OSS_TAG=2026-07-05
OSS_DATE=20260705
SV2V_VERSION=0.0.13
MAMBA_VERSION=2.8.1-0

case "$APP_DIR" in
    ""|/) echo "Unsafe application directory: $APP_DIR" >&2; exit 1 ;;
esac
case "$INSTALL_MODE" in
    user|system) ;;
    *) echo "Unknown installation mode: $INSTALL_MODE" >&2; exit 1 ;;
esac

download() {
    url=$1
    destination=$2
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --retry 3 "$url" -o "$destination"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$destination" "$url"
    else
        echo "curl or wget is required to download the portable runtime." >&2
        exit 1
    fi
}

install_system_packages() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "System installation requires: sudo make install-system" >&2
        exit 1
    fi
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y tcl tk g++ curl ca-certificates tar
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y tcl tk gcc-c++ curl ca-certificates tar
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --needed --noconfirm tcl tk gcc curl ca-certificates tar
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install tcl tk gcc-c++ curl ca-certificates tar
    else
        echo "Unsupported system package manager." >&2
        exit 1
    fi
}

case "$(uname -m)" in
    x86_64|amd64) OSS_ARCH=x64; MAMBA_ARCH=linux-64 ;;
    aarch64|arm64) OSS_ARCH=arm64; MAMBA_ARCH=linux-aarch64 ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if ! command -v tar >/dev/null 2>&1; then
    echo "tar is required for installation." >&2
    exit 1
fi

TOOLS_DIR="$APP_DIR/tools"
RUNTIME_DIR="$APP_DIR/runtime"
mkdir -p "$TOOLS_DIR"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

if [ "$INSTALL_MODE" = system ]; then
    install_system_packages
else
    MAMBA_NAME="micromamba-$MAMBA_ARCH"
    MAMBA_URL="https://github.com/mamba-org/micromamba-releases/releases/download/$MAMBA_VERSION/$MAMBA_NAME"
    download "$MAMBA_URL" "$TMP_DIR/$MAMBA_NAME"
    download "$MAMBA_URL.sha256" "$TMP_DIR/$MAMBA_NAME.sha256"
    MAMBA_EXPECTED=$(cat "$TMP_DIR/$MAMBA_NAME.sha256")
    MAMBA_ACTUAL=$(sha256sum "$TMP_DIR/$MAMBA_NAME" | awk '{print $1}')
    if [ "$MAMBA_EXPECTED" != "$MAMBA_ACTUAL" ]; then
        echo "micromamba checksum validation failed." >&2
        exit 1
    fi
    chmod 0755 "$TMP_DIR/$MAMBA_NAME"
    MAMBA_ROOT_PREFIX="$APP_DIR/.mamba" \
        "$TMP_DIR/$MAMBA_NAME" create -y -p "$RUNTIME_DIR" -c conda-forge \
        tk cxx-compiler
fi

OSS_URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$OSS_TAG/oss-cad-suite-linux-$OSS_ARCH-$OSS_DATE.tgz"
download "$OSS_URL" "$TMP_DIR/oss-cad-suite.tgz"
tar -xzf "$TMP_DIR/oss-cad-suite.tgz" -C "$TMP_DIR"
rm -rf "$TOOLS_DIR/oss-cad-suite"
mv "$TMP_DIR/oss-cad-suite" "$TOOLS_DIR/oss-cad-suite"

if [ "$OSS_ARCH" = x64 ]; then
    SV2V_URL="https://github.com/zachjs/sv2v/releases/download/v$SV2V_VERSION/sv2v-Linux.zip"
    download "$SV2V_URL" "$TMP_DIR/sv2v.zip"
    PYTHON="$TOOLS_DIR/oss-cad-suite/bin/tabbypy3"
    if [ ! -x "$PYTHON" ]; then
        echo "The Python runtime supplied by OSS CAD Suite was not found." >&2
        exit 1
    fi
    "$PYTHON" -m zipfile -e "$TMP_DIR/sv2v.zip" "$TMP_DIR/sv2v"
    mkdir -p "$TOOLS_DIR/sv2v"
    SV2V_BIN=$(find "$TMP_DIR/sv2v" -type f -name sv2v | head -n 1)
    test -n "$SV2V_BIN"
    install -m 0755 "$SV2V_BIN" "$TOOLS_DIR/sv2v/sv2v"
elif command -v sv2v >/dev/null 2>&1; then
    mkdir -p "$TOOLS_DIR/sv2v"
    cp "$(command -v sv2v)" "$TOOLS_DIR/sv2v/sv2v"
else
    echo "sv2v has no official ARM64 binary. Install sv2v in your account and repeat." >&2
    exit 1
fi

echo "All RTL Explorer dependencies were installed in $APP_DIR."
