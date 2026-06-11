#!/bin/bash
# build.sh — Compile the patched linux-pipewire OBS plugin
#
# Prerequisites:
#   sudo dnf install gcc obs-studio-devel pipewire-devel libdrm-devel \
#     extra-cmake-modules glib2-devel
#
# Usage:
#   ./build.sh
#   sudo cp linux-pipewire.so /usr/lib64/obs-plugins/linux-pipewire.so

set -euo pipefail

SRCDIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${OUTDIR:-/tmp}"

echo "==> Compiling linux-pipewire.so with deferred session patch..."

gcc -shared -fPIC -o "$OUTDIR/linux-pipewire.so" \
    "$SRCDIR/linux-pipewire.c" \
    "$SRCDIR/pipewire.c" \
    "$SRCDIR/portal.c" \
    "$SRCDIR/screencast-portal.c" \
    "$SRCDIR/camera-portal.c" \
    "$SRCDIR/formats.c" \
    "$SRCDIR/glad.c" \
    -I "$SRCDIR" \
    -I /usr/include/obs \
    -I /usr/include/pipewire-0.3 \
    -I /usr/include/spa-0.2 \
    $(pkg-config --cflags --libs gio-2.0) \
    $(pkg-config --cflags --libs libdrm) \
    $(pkg-config --cflags --libs libpipewire-0.3) \
    -lobs -lpthread -ldl -lm \
    -Wl,-rpath,/usr/lib64

echo "==> Compiled: $OUTDIR/linux-pipewire.so"
echo ""
echo "To install:"
echo "  sudo cp /usr/lib64/obs-plugins/linux-pipewire.so{,.bak}"
echo "  sudo cp $OUTDIR/linux-pipewire.so /usr/lib64/obs-plugins/linux-pipewire.so"
echo ""
echo "To restore original:"
echo "  sudo cp /usr/lib64/obs-plugins/linux-pipewire.so.bak /usr/lib64/ops-plugins/linux-pipewire.so"