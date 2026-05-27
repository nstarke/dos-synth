#!/bin/bash
set -e

SRC="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(uname)" == "Darwin" ]]; then
    DEST_ROOT="${HOME}/Library/Application Support/86Box/Virtual Machines"
else
    DEST_ROOT="${HOME}/.config/86Box"
fi

VM_NAME="dos-synth"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        *)
            DEST_ROOT="$1"
            shift
            ;;
    esac
done

DEST="${DEST_ROOT}/${VM_NAME}"

if [ ! -d "$DEST_ROOT" ]; then
    echo "Error: 86Box installation directory does not exist: $DEST_ROOT" >&2
    exit 1
fi

mkdir -p "$DEST"

cp "$SRC/86box.cfg" "$DEST/"
cp "$SRC/dos-synth.vhd" "$DEST/"
cp -r "$SRC/nvr" "$DEST/"

echo "VM copied to $DEST"
