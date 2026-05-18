# MIDI Agent

DOS-side tools that run inside the 86Box VM. The agent receives MIDI from the emulated MPU-401 (I/O 0x330) and feeds it to DOS synthesizers as keyboard scancodes.

See the [project README](../../README.md) for the full host → VM signal path.

## Tools

### `midi_inject.asm` → `MIDI_INJ.COM`

The main agent. A TSR (Terminate and Stay Resident) program that:

1. Resets the MPU-401 into UART passthrough mode.
2. Hooks the system timer interrupt (INT 8, ~18.2 Hz).
3. On each tick, polls the MPU-401 for incoming MIDI bytes and injects mapped XT Set-1 scancodes through the 8042 keyboard controller (command `0xD2`), firing IRQ1/INT 9.

Note On → make code (key down). Note Off → break code (key up). The key is held for the full MIDI note duration so synthesizers sustain correctly.

**Usage (inside the VM):**
```
C:\AGENT\MIDI_INJ.COM [/VR | /FMS4 | /DEFAULT | /H]
```

| Flag        | Layout                        | Range            | Use for                         |
|-------------|-------------------------------|------------------|---------------------------------|
| *(none)*    | `zsxdcvgbhnjm` / `q2w3er5t6y7u` | MIDI 48–71 (2 octaves) | Default; most synths      |
| `/FMS4`     | `zsxdcvgbhnjm`                | MIDI 48–59 (1 octave) | FMS4 and synths without q-row |
| `/VR`       | `awsdefyhujik`                | MIDI 48–59 (1 octave) | `VR_DEMO.EXE`                  |
| `/DEFAULT`  | restores default              | MIDI 48–71       | Switch back after `/VR` or `/FMS4` |
| `/H`        | —                             | —                | Print usage help and exit (no install / hot-swap) |

Re-running with a flag while installed hot-swaps the layout without rebooting. Running with no flag prints the current active mode.

### `midi_mon.asm` → `MIDI_MON.COM`

A foreground MIDI monitor. Initializes the MPU-401 and prints every complete MIDI message to stdout. Press any key to quit. Use this to verify the bridge → 86Box → MPU-401 chain is working before loading the TSR with a synthesizer.

**Usage (inside the VM):**
```
C:\AGENT\MIDI_MON.COM
```

Example output:
```
NoteOn   ch:1  note:60(C4)   vel:127
NoteOff  ch:1  note:60(C4)   vel:0
CC       ch:1  ctrl:7  val:100
```

## Building

Requires [NASM](https://nasm.us).

**Linux / macOS:**
```sh
make
```

**Windows:**
```bat
compile.bat
```

Both produce `midi_inject.com` and `midi_mon.com`. Copy them into the VM at `C:\AGENT\` (the install scripts in `../../tools/` mount the VHD and copy the `.com` files in place).
