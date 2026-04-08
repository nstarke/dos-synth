#!/bin/bash
sudo qemu-nbd --connect=/dev/nbd0 dos-synth.vhd
sudo partprobe /dev/nbd0
sudo mount /dev/nbd0p1 /mnt
sudo cp midi/agent/midi_mon.com /mnt/AGENT/MIDI_MON.COM
sudo cp midi/agent/midi_inject.com /mnt/AGENT/MIDI_INJ.COM
sudo umount /mnt
sudo qemu-nbd --disconnect /dev/nbd0
