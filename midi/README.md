# MIDI CC Support

This document lists which synths in `/SYNTHS` respond to MIDI Control Change (CC) messages.

## Summary

| Synth | MIDI CC | MIDI Notes | Channels |
|-------|---------|------------|----------|
| ANALOGIC | Yes | Yes | 1–4 |
| AXS202 | Yes | Yes | 1–8 |
| VR (AudioSim) | No | Yes | 1 |
| FMS4 | No | No | — |
| GB303V7 | No | No | — |
| SNARRL16 | No | No | — |
| SONIC | No | No | — |
| VM110 | No | No | — |

---

## Using ANALOGIC / AXS202 with this stack

Both synths poll the MPU-401 data port (I/O 0x330) directly and handle all
incoming MIDI — notes and CC — without any help from `midi_inject.com`.

**Do not run `midi_inject.com` alongside ANALOGIC or AXS202.** The TSR drains
the MPU-401 ring buffer inside its INT 8 handler (~18 Hz). Every byte it reads
is gone; the synth will never see it. Running the TSR starves these synths of
both note and CC data.

The bridge (`midi/bridge`) already forwards all MIDI message types unchanged.
The working chain is simply:

```
Host MIDI controller
       │
       ▼
midi/bridge  (node index.js)
       │  passes all MIDI verbatim
       ▼
86Box MPU-401 (I/O 0x330)
       │
       ▼
ANALOGIC.EXE / AXS.EXE  ← reads notes + CC directly from hardware
```

No TSR. No keyboard injection. Program changes (Cx) are also accepted — both
synths support 0–127 preset selection.

---

## ANALOGIC v1.1 (NewStyle)

Responds to MIDI CC on channels 1–4. Full range 0–127 for all controllers. Switches use 0–63 = off, 64–127 = on.

| CC | Parameter |
|----|-----------|
| 5 | Portamento time |
| 7 | Amplitude envelope gain (channel volume) |
| 8 | Oscillator mix |
| 9 | Distortion |
| 11 | Output effect (0–5, global) |
| 12 | Legato switch |
| 13 | Ring modulation switch |
| 18 | LFO1 sync on/off |
| 19 | LFO1 speed |
| 20 | LFO1 shape |
| 21 | LFO1 destination |
| 22 | LFO1 amount |
| 23 | LFO1 pulsewidth |
| 24 | LFO2 speed |
| 25 | LFO2 shape |
| 26 | LFO2 destination |
| 27 | LFO2 amount |
| 28 | LFO2 pulsewidth |
| 29 | LFO2 sync on/off |
| 30 | OSC1 wave shape |
| 31 | OSC2 wave shape |
| 33 | OSC2 finetune |
| 34 | Oscillator keyboard tracking |
| 35 | OSC2 sync on/off |
| 36 | Amplitude envelope decay |
| 37 | Amplitude envelope sustain |
| 38 | Filter envelope attack |
| 39 | Filter envelope decay |
| 40 | Filter envelope sustain |
| 41 | Filter envelope release |
| 42 | Velocity to filter switch |
| 43 | Filter envelope gain |
| 44 | Base note (when KBT = 0) |
| 50 | Pitch envelope attack |
| 51 | Pitch envelope decay |
| 52 | Pitch envelope sustain |
| 53 | Pitch envelope release |
| 54 | Pitch envelope gain |
| 65 | Portamento on/off switch |
| 71 | Filter resonance/bandwidth |
| 72 | Amplitude envelope release |
| 73 | Amplitude envelope attack |
| 74 | Filter cutoff |
| 75 | Filter type |
| 77 | OSC2 semitones |
| 78 | OSC1 pulsewidth |
| 79 | OSC2 pulsewidth |
| 94 | FX send |
| 123 | All notes off |

---

## AXS202 v2.02 (NewStyle/Resolution)

Same developers as ANALOGIC; shares most of the same CC map with additions. Responds on channels 1–8.

| CC | Parameter |
|----|-----------|
| 5 | Portamento time |
| 8 | OSC1/2 mix |
| 9 | Distortion amount |
| 12 | Legato switch |
| 13 | Ring modulation amount |
| 17 | Distortion type |
| 18 | LFO1 sync on/off |
| 19 | LFO1 speed |
| 20 | LFO1 shape |
| 21 | LFO1 destination |
| 22 | LFO1 amount |
| 23 | LFO1 pulsewidth |
| 24 | LFO2 speed |
| 25 | LFO2 shape |
| 26 | LFO2 destination |
| 27 | LFO2 amount |
| 28 | LFO2 pulsewidth |
| 29 | LFO2 sync on/off |
| 30 | OSC1 wave shape |
| 31 | OSC2 wave shape |
| 33 | OSC2 finetune |
| 34 | Oscillator keyboard tracking |
| 35 | OSC2 sync on/off |
| 36 | Amplitude envelope decay |
| 37 | Amplitude envelope sustain |
| 38 | Filter envelope attack |
| 39 | Filter envelope decay |
| 40 | Filter envelope sustain |
| 41 | Filter envelope release |
| 42 | Velocity to filter switch |
| 43 | Filter envelope gain |
| 45 | Velocity to amplitude |
| 50 | Pitch envelope attack |
| 51 | Pitch envelope decay |
| 52 | Pitch envelope sustain |
| 53 | Pitch envelope release |
| 54 | Pitch envelope gain |
| 55 | Pitch envelope destination |
| 65 | Portamento on/off switch |
| 70 | Amplitude envelope gain |
| 71 | Filter resonance |
| 72 | Amplitude envelope release |
| 73 | Amplitude envelope attack |
| 74 | Filter cutoff |
| 75 | Filter type |
| 76 | Filter keyboard tracking amount |
| 77 | OSC2 semitones |
| 78 | OSC1 pulsewidth |
| 79 | OSC2 pulsewidth |
| 80 | Ring modulation type |
| 90 | FX type |
| 94 | FX send |

---

## VR (AudioSim v2, Audio Simulation)

Responds to MIDI note on/off on channel 1 only. No CC support documented.

---

## No MIDI CC — FMS4, GB303V7, SNARRL16, SONIC, VM110

These programs have no real-time MIDI input:

- **FMS4** — offline FM sample renderer (GUS output)
- **GB303V7** — acid bass sample renderer with internal step sequencer
- **SNARRL16** — acid sample generator, outputs 8-bit raw
- **SONIC** (Sonic Sequence v1.0) — FM workstation with built-in sequencer; MIDI file export only
- **VM110** (Voicemaker v1.1) — text-to-speech utility, not a synthesizer
