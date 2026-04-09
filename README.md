# DOS-SYNTH

A collection of Music, Sound, and Synthesizer programs for MS-DOS 6.22, running in an [86Box](https://github.com/86Box/86Box) virtual machine, with a MIDI bridge that lets you play the DOS synthesizers from a real MIDI keyboard or any DAW.

## How to Use

1. Install [86Box](https://github.com/86Box/86Box).
2. Open the VM using the `86box.cfg` in this repository.
3. Load the `dos-synth.vhd` disk image.
4. Start a synthesizer (see **Synths** below).
5. Run `C:\AGENT\MIDI_INJ.COM` inside the VM to activate the MIDI agent.
6. Start the MIDI bridge on the host (see **MIDI Bridge** below).
7. Route your MIDI keyboard or DAW to the bridge and play.

## Synths

The primary feature of this VM are the synths in `C:\SYNTHS`.

### SONIC
[![MS-DOS SONIC](https://img.youtube.com/vi/WiQw1udnA00/0.jpg)](https://www.youtube.com/watch?v=WiQw1udnA00)

### GB303v7
[![MS-DOS GB303V7](https://img.youtube.com/vi/XsqOJpLWcZs/0.jpg)](https://www.youtube.com/watch?v=XsqOJpLWcZs)

### FMS4
[![MS-DOS FMS4](https://img.youtube.com/vi/TjDKSwumGG0/0.jpg)](https://www.youtube.com/watch?v=TjDKSwumGG0)

### AUDIOSIM2
[![MS-DOS AUDIOSIM2](https://img.youtube.com/vi/I2p8hbXqg2o/0.jpg)](https://www.youtube.com/watch?v=I2p8hbXqg2o)

### AXS202
[![MS-DOS AXS202](https://img.youtube.com/vi/DyZD3MkmoRQ/0.jpg)](https://www.youtube.com/watch?v=DyZD3MkmoRQ)

## TRACKERS

The VM also has a collection of DOS trackers in `C:\TRACKERS`.

## SIMTEL

The VM also contains the MUSIC and SOUND directories from the SIMTEL archive at `C:\SIMTEL`.

## Linux: Mouse Movement

On Linux, 86Box must be launched with two environment variables to enable mouse capture inside the VM:

```sh
QT_QPA_PLATFORM=xcb SDL_VIDEODRIVER=x11 86box
```

Without these, Qt and SDL use the native Wayland backend, where `SDL_SetRelativeMouseMode` does not deliver relative motion events to the VM. Setting `QT_QPA_PLATFORM=xcb` forces Qt onto XWayland, and `SDL_VIDEODRIVER=x11` forces SDL to match.

## VM Configuration

The 86Box VM has two soundcards:

1. SoundBlaster 16
2. Gravis UltraSound

Additionally:

- CuteMouse driver is installed
- MS-DOS CDROM driver is installed

---

## MIDI Agent (`midi/agent/midi_inject.asm`)

The MIDI agent is a DOS TSR (Terminate and Stay Resident) program that bridges the Roland MPU-401 MIDI interface inside the VM to the synthesizer programs.

### How it works

DOS synthesizers respond to keypresses by hooking the hardware keyboard interrupt (INT 9 / IRQ1).  They read raw XT Set-1 scancodes directly from I/O port 0x60, bypassing the BIOS keyboard buffer entirely.

The agent works as follows:

1. **MPU-401 init** — On startup it resets the MPU-401 at I/O 0x330 and puts it into UART (passthrough) mode so raw MIDI bytes flow through without sequencer processing.

2. **INT 8 hook** — It hooks the system timer interrupt (INT 8, ~18.2 Hz).  On every timer tick it:
   - Dequeues one pending scancode and injects it into the 8042 keyboard controller using command `0xD2` (Write Keyboard Output Buffer).  This places the scancode into the 8042's output buffer exactly as if a real key were pressed, firing IRQ1/INT 9 and triggering the synthesizer.
   - Polls the MPU-401 data port (0x330) for up to 8 incoming MIDI bytes and runs each through the MIDI parser.

3. **MIDI parser** — A state machine that handles:
   - Note On (velocity > 0): enqueues the **make code** (key down) for the mapped key.
   - Note Off or Note On with velocity 0: enqueues the **break code** (make | 0x80, key up).
   - Running status, SysEx, and all other MIDI message types.

   Sending make-only on note-on and break-only on note-off means the key is held for the full duration of the MIDI note, so the synthesizer sustains correctly.

4. **Note mapping** — MIDI notes are mapped to keyboard keys depending on the active mode (see **Flags** below).

   **Default** — two octaves, MIDI 48–71 (C3–B4):

   | MIDI | Note | Key | | MIDI | Note | Key |
   |------|------|-----|-|------|------|-----|
   | 48   | C3   | z   | | 60   | C4   | q   |
   | 49   | C#3  | s   | | 61   | C#4  | 2   |
   | 50   | D3   | x   | | 62   | D4   | w   |
   | 51   | D#3  | d   | | 63   | D#4  | 3   |
   | 52   | E3   | c   | | 64   | E4   | e   |
   | 53   | F3   | v   | | 65   | F4   | r   |
   | 54   | F#3  | g   | | 66   | F#4  | 5   |
   | 55   | G3   | b   | | 67   | G4   | t   |
   | 56   | G#3  | h   | | 68   | G#4  | 6   |
   | 57   | A3   | n   | | 69   | A4   | y   |
   | 58   | A#3  | j   | | 70   | A#4  | 7   |
   | 59   | B3   | m   | | 71   | B4   | u   |

   Notes outside MIDI 48–71 are transposed by octaves until they fall within range.  All MIDI channels are accepted.

### Flags

```
MIDI_INJ [/VR | /FMS4 | /DEFAULT]
```

The flags select the key layout and note range.  They are mutually exclusive.

| Flag | Layout | Notes | Use for |
|------|--------|-------|---------|
| *(none)* | `zsxdcvgbhnjm` / `q2w3er5t6y7u` | MIDI 48–71 (C3–B4), two octaves | Default; most synths |
| `/FMS4` | `zsxdcvgbhnjm` | MIDI 48–59 (C3–B3), one octave | FMS4 and synths that don't use the `q`-row |
| `/VR` | `awsdefyhujik` | MIDI 48–59 (C3–B3), one octave | `VR_DEMO.EXE` |
| `/DEFAULT` | *(restores default)* | MIDI 48–71 (C3–B4), two octaves | Switch back after `/VR` or `/FMS4` |

**Hot-swapping** — if the TSR is already installed, re-running it with a flag switches the active layout immediately without rebooting the VM:

```
C:\AGENT\MIDI_INJ.COM /VR       ← switch to VR layout
C:\AGENT\MIDI_INJ.COM /FMS4     ← switch to FMS4 layout
C:\AGENT\MIDI_INJ.COM /DEFAULT  ← switch back to default
C:\AGENT\MIDI_INJ.COM           ← print current active mode
```

### Compiling

Requires [NASM](https://nasm.us).

**Linux / macOS:**
```sh
cd midi/agent
make
```

**Windows:**
```bat
cd midi\agent
compile.bat
```

### Running (inside the VM)

```
C:\AGENT\MIDI_INJ.COM [/VR | /FMS4 | /DEFAULT]
```

Run once before starting a synthesizer.  The TSR prints a confirmation message and stays resident.  See **Flags** above for layout options.

---

## MIDI Bridge (`midi/bridge/`)

The MIDI bridge is a Node.js application that routes MIDI from an external source (keyboard, DAW, etc.) to 86Box's MIDI input port.  86Box passes the MIDI data to the MPU-401 inside the VM, where the MIDI agent converts it to synthesizer keypresses.

### Signal path

```
External MIDI source (keyboard / DAW)
        |
        |  aconnect (Linux) / Audio MIDI Setup (macOS) / DAW routing (Windows)
        v
  DOS-Synth Bridge  [host: midi/bridge/]
        |
        |  MIDI output → 86Box MIDI input port
        v
  MPU-401 (emulated, I/O 0x330)
        |
        v
  midi_inject.asm TSR  [inside VM]
        |
        v
  DOS Synthesizer (INT 9 / IRQ1)
```

### Requirements

- Node.js 18 or later
- 86Box configured with a MIDI output device (e.g. the built-in ALSA/WinMM output)

### Setup

```sh
cd midi/bridge
npm install
```

### Setup

The bridge needs a **shared virtual MIDI port** — a loopback device that both the bridge and 86Box connect to.  Create one for your OS before running the bridge:

| OS | How |
|----|-----|
| Linux | "MIDI Through" is built into ALSA — nothing to install |
| Windows | Install [loopMIDI](https://tobias-erichsen.de/software/loopmidi.html) and create a port |
| macOS | Open **Audio MIDI Setup → IAC Driver**, check "Device is online" |

Then in **86Box → Settings → Sound → MPU-401**, select that same virtual port as the MIDI device.

### Finding your port names

Run `--list` to see every MIDI input and output available on your system:

```sh
node index.js --list
# MIDI inputs (2):
#   [0] Midi Through Port-0
#   [1] Arturia KeyStep 32
#
# MIDI outputs (2):
#   [0] Midi Through Port-0
#   [1] Timidity port 0
```

### Configuration (`midi/bridge/config.json`)

Set your ports once in `config.json` so you don't need flags every time:

```json
{
  "midi": {
    "input":   "Arturia",
    "output":  "MIDI Through",
    "channel": "all"
  }
}
```

| Key | Values | Description |
|-----|--------|-------------|
| `midi.input` | `"auto"`, name substring, or index | MIDI source device. `"auto"` uses the first available input. |
| `midi.output` | Name substring or index | Shared virtual MIDI port. **Required** — must match the port selected in 86Box MPU-401 settings. |
| `midi.channel` | `"all"` or `1`–`16` | Filter input to one MIDI channel, or pass all. |

### Running

```sh
# Start the bridge (uses config.json):
node index.js

# Override ports on the command line:
node index.js --in "Arturia KeyStep" --out "MIDI Through"

# Filter to MIDI channel 1 only:
node index.js --channel 1
```

### Options

| Flag | Description |
|------|-------------|
| `--in <name\|idx>` | MIDI input device (name substring or index). Defaults to `midi.input` in config, then first available. |
| `--out <name\|idx>` | Shared virtual MIDI port (name substring or index). Defaults to `midi.output` in config. Required. |
| `--name <label>` | ALSA/CoreMIDI client name for this bridge instance. |
| `--channel <1-16>` | Filter to one MIDI channel; pass all channels by default. |
| `--list` | Print all available MIDI inputs and outputs and exit. |
| `--help` | Show help. |

### Connecting a MIDI source after the bridge is running (Linux)

On Linux you can also leave `midi.input` as `"auto"` and connect any source to the bridge after it starts using `aconnect`:

```sh
aconnect "Arturia KeyStep 32" "DOS-Synth Bridge"
```

---

## Serial Keystroke Agent (`serial/agent/serial_inject.asm`)

An earlier approach that injects keystrokes received over COM1 (serial port) into the 8042 keyboard controller.  Works for CLI commands but does not support MIDI note sustain.  The MIDI agent above is preferred for playing synthesizers.

### Running (inside the VM)

```
C:\AGENT\SERIAL_I.COM
```

### Compiling

**Linux / macOS:**
```sh
cd serial/agent
make
```

**Windows:**
```bat
cd serial\agent
compile.bat
```
