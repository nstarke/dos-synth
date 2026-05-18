#!/bin/bash
set -e

SRC="$(cd "$(dirname "$0")/.." && pwd)"

if [ -n "$1" ]; then
    DEST_ROOT="$1"
else
    DEST_ROOT="${HOME}/.config/86Box"
fi

DEST="${DEST_ROOT}/dos-synth"

if [ ! -d "$DEST_ROOT" ]; then
    echo "Error: 86Box installation directory does not exist: $DEST_ROOT" >&2
    exit 1
fi

mkdir -p "$DEST"

cp "$SRC/86box.cfg" "$DEST/"
cp "$SRC/dos-synth.vhd" "$DEST/"
cp -r "$SRC/nvr" "$DEST/"

echo "VM copied to $DEST"
