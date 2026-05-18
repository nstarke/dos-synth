# Tools

Helper scripts for installing, mounting, and updating the dos-synth VM.

The mount/list scripts are Linux-only — they use `qemu-nbd` to expose `dos-synth.vhd` as a block device and mount the FAT partition at `/mnt`. The install scripts work cross-platform.

## Install scripts

### `copy-vm.bat` (Windows) / `copy-vm.sh` (Linux/macOS)

Copies the VM artifacts (`86box.cfg`, `dos-synth.vhd`, `nvr/`) into a `dos-synth/` subdirectory of your 86Box VMs folder. Use this so 86Box's NVR/CMOS writes don't dirty the repo. See the [project README](../README.md#installing-the-vm) for the rationale.

**Arguments:**

| Position | Description | Default |
|----------|-------------|---------|
| `$1` / `%1` | Path to your 86Box VMs root directory | Windows: `%USERPROFILE%\86Box Vms` &nbsp; Linux/macOS: `~/.config/86Box` |

**Examples:**

```bat
REM Windows — use the default %USERPROFILE%\86Box Vms
tools\copy-vm.bat

REM Windows — custom 86Box VMs folder
tools\copy-vm.bat "D:\Emulators\86Box Vms"
```

```sh
# Linux/macOS — use the default ~/.config/86Box
tools/copy-vm.sh

# Linux/macOS — custom path
tools/copy-vm.sh ~/Emulation/86Box
```

After running, the VM lives at `<dest>/dos-synth/` and can be opened from 86Box's VM list.

## VHD scripts (Linux only)

These require `qemu-nbd` (`apt install qemu-utils` on Debian/Ubuntu) and use `sudo` to load the `nbd` kernel module, mount, and copy. They assume `/dev/nbd0` is free and `/mnt` is an available mount point.

### `mount.sh`

Connects `dos-synth.vhd` to `/dev/nbd0` and mounts partition 1 at `/mnt`. Inspect, copy files in, or browse the DOS filesystem from the host.

**Arguments:** none.

**Example:**
```sh
tools/mount.sh
ls /mnt/SYNTHS
# ... do work ...
tools/umount.sh
```

### `umount.sh`

Unmounts `/mnt` and disconnects `/dev/nbd0`. Always run after `mount.sh` — leaving the nbd device connected can prevent re-mounting in the same session.

**Arguments:** none.

### `mount-and-copy.sh`

One-shot: mounts the VHD, copies freshly built `midi/agent/midi_inject.com` and `midi/agent/midi_mon.com` into `C:\AGENT\` (i.e. `/mnt/AGENT/`), then unmounts.

Use this after rebuilding the agent with `make` in `midi/agent/`.

**Arguments:** none. Paths are hard-coded.

**Example:**
```sh
cd midi/agent && make && cd -
tools/mount-and-copy.sh
```

### `list-vhd.sh`

Mounts the VHD and regenerates `FILES.TXT` at the repo root — a recursive listing of every file inside the VM, with paths converted to DOS form (e.g. `/mnt/SYNTHS/SONIC/SONIC.EXE` → `C:\SYNTHS\SONIC\SONIC.EXE`). Useful for diffing what changed inside the VM between commits.

**Arguments:** none.

**Example:**
```sh
tools/list-vhd.sh
git diff FILES.TXT
```
