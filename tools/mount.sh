#!/bin/bash
sudo qemu-nbd --connect=/dev/nbd0 dos-synth.vhd
sudo partprobe /dev/nbd0
sudo mount /dev/nbd0p1 /mnt
