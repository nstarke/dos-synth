#!/bin/bash
REPO="$(cd "$(dirname "$0")/.." && pwd)"

sudo qemu-nbd --connect=/dev/nbd0 "$REPO/dos-synth.vhd"
sudo partprobe /dev/nbd0
sudo mount /dev/nbd0p1 /mnt

find /mnt -mindepth 1 | sed 's|^/mnt|C:|; s|/|\\|g' > "$REPO/FILES.TXT"

sudo umount /mnt
sudo qemu-nbd --disconnect /dev/nbd0
