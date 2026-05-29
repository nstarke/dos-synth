# MIDI CC Map — ANALOGIC v1.1 & AXS202 v2.02

Both synths are by NewStyle/Resolution and share a common CC numbering scheme.
They read the MPU-401 port directly — do **not** run `midi_inject.com` alongside them.

Value ranges: all CCs accept 0–127. Boolean/switch parameters treat 0–63 as **off**, 64–127 as **on**.
Enum parameters (shapes, types, destinations) are divided evenly across 0–127 by the number of options.

---

## ANALOGIC v1.1

Channels 1–4 (A/B/C/D slots). Program change 0–127 selects presets.
No pitch bend. No velocity on note-off.

### Oscillators

| CC | Parameter | Notes |
|----|-----------|-------|
| 30 | OSC1 wave shape | 0–127 selects: sine · triangle · saw · block (pulse) · variable trisaw |
| 31 | OSC2 wave shape | same options as OSC1 |
| 78 | OSC1 pulse width | active when block shape selected; also morphs trisaw |
| 79 | OSC2 pulse width | same |
| 8  | OSC1/2 mix | 0 = full OSC1, 127 = full OSC2 |
| 33 | OSC2 finetune | 0 = –1 semitone, 64 = center, 127 = +1 semitone |
| 77 | OSC2 semitones | 0 = –3 oct, 64 = unison, 127 = +3 oct |
| 34 | Oscillator keyboard tracking | switch; off = both OSCs fixed at last note pitch |
| 35 | OSC2 sync to OSC1 | switch; OSC2 restarts when OSC1 completes a cycle |
| 44 | Base note (when KBT = 0) | MIDI note number used when keyboard tracking is off |

### Amplitude Envelope (AMP ENV)

| CC | Parameter |
|----|-----------|
| 73 | Attack time |
| 36 | Decay time |
| 37 | Sustain level |
| 72 | Release time |
| 7  | Envelope gain (channel volume) |

### Filter

| CC | Parameter | Notes |
|----|-----------|-------|
| 74 | Cutoff frequency | |
| 71 | Resonance / bandwidth | bandwidth when BP or BR type selected |
| 75 | Filter type | 0–31 = LP (resonant) · 32–63 = HP (resonant) · 64–95 = BP · 96–127 = BR |
| 42 | Velocity → filter switch | switch; scales filter envelope gain by note-on velocity |

### Filter Envelope (FLT ENV)

| CC | Parameter |
|----|-----------|
| 38 | Attack time |
| 39 | Decay time |
| 40 | Sustain level |
| 41 | Release time |
| 43 | Envelope gain (positive = opens filter, negative not supported) |

### Pitch Envelope (PIT ENV)

| CC | Parameter | Notes |
|----|-----------|-------|
| 50 | Attack time | |
| 51 | Decay time | |
| 52 | Sustain level | |
| 53 | Release time | |
| 54 | Envelope gain | 0 = –3 oct, 64 = center, 127 = +3 oct |

### LFO 1

| CC | Parameter | Notes |
|----|-----------|-------|
| 19 | LFO1 speed (rate) | |
| 20 | LFO1 shape | evenly divided: sine · triangle · saw · block · noise |
| 21 | LFO1 destination | evenly divided: none · filter · amplitude · osc1 pitch · osc2 pitch · osc1 PW · osc2 PW |
| 22 | LFO1 amount | |
| 23 | LFO1 pulse width | active when block or trisaw shape selected |
| 18 | LFO1 sync on/off | switch; restarts LFO shape on each new note |

### LFO 2

| CC | Parameter | Notes |
|----|-----------|-------|
| 24 | LFO2 speed (rate) | |
| 25 | LFO2 shape | evenly divided: block · noise · trisaw · sine |
| 26 | LFO2 destination | evenly divided: none · filter · amplitude · osc1 pitch · osc2 pitch · osc2 PW · pitch (both OSCs) · LFO2 rate |
| 27 | LFO2 amount | |
| 28 | LFO2 pulse width | |
| 29 | LFO2 sync on/off | switch |

### Effects & Articulation

| CC | Parameter | Notes |
|----|-----------|-------|
| 9  | Distortion amount | |
| 13 | Ring modulation switch | switch; enables ring mod |
| 11 | Output effect type | 0–5 selects global FX type (6 steps, ~21 values each) |
| 94 | FX send level | how much signal goes into effect |
| 5  | Portamento time | |
| 65 | Portamento on/off | switch |
| 12 | Legato switch | switch; monophonic legato mode |
| 123 | All notes off | value ignored |

---

## AXS202 v2.02

Channels 1–8 (7 synth parts + sampler). Program change 0–127.
**Pitch bend recognized**: ±12 semitones, 7-bit resolution.
MIDI clock / start / stop / continue recognized (sequencer sync).

### Oscillators

| CC | Parameter | Notes |
|----|-----------|-------|
| 30 | OSC1 wave shape | 0–127: sine · triangle · saw · block · variable trisaw |
| 31 | OSC2 wave shape | same |
| 78 | OSC1 pulse width | active when block or trisaw selected |
| 79 | OSC2 pulse width | same |
| 8  | OSC1/2 mix | 0 = full OSC1, 127 = full OSC2 |
| 33 | OSC2 finetune | 0 = –1 semitone, 64 = center, 127 = +1 semitone |
| 77 | OSC2 semitones | 0 = –3 oct, 64 = unison, 127 = +3 oct |
| 34 | Oscillator keyboard tracking | switch |
| 35 | OSC2 sync to OSC1 | switch |

### Amplitude Envelope (AMP ENV)

| CC | Parameter |
|----|-----------|
| 73 | Attack time |
| 36 | Decay time |
| 37 | Sustain level |
| 72 | Release time |
| 70 | Envelope gain |
| 45 | Velocity → amplitude | switch; when off all notes play at maximum volume |

### Filter

| CC | Parameter | Notes |
|----|-----------|-------|
| 74 | Cutoff frequency | |
| 71 | Resonance / bandwidth | bandwidth for BP and BR types |
| 75 | Filter type | 0–25 = LP12 · 26–51 = LP24 · 52–76 = HP · 77–101 = BP · 102–127 = BR |
| 76 | Filter keyboard tracking amount | 0–31 = 0/3 · 32–63 = 1/3 · 64–95 = 2/3 · 96–127 = 3/3 |
| 42 | Velocity → filter switch | switch |

### Filter Envelope (FLT ENV)

| CC | Parameter |
|----|-----------|
| 38 | Attack time |
| 39 | Decay time |
| 40 | Sustain level |
| 41 | Release time |
| 43 | Envelope gain |

### Pitch Envelope (PIT ENV)

| CC | Parameter | Notes |
|----|-----------|-------|
| 50 | Attack time | |
| 51 | Decay time | |
| 52 | Sustain level | |
| 53 | Release time | |
| 54 | Envelope gain | 0 = –3 oct, 64 = center, 127 = +3 oct |
| 55 | Pitch envelope destination | 0–31 = none · 32–63 = OSC1 · 64–95 = OSC2 · 96–127 = OSC1+OSC2 |

### LFO 1

| CC | Parameter | Notes |
|----|-----------|-------|
| 19 | LFO1 speed (rate) | |
| 20 | LFO1 shape | evenly divided: sine · triangle · saw · block · noise |
| 21 | LFO1 destination | none · filter · amplitude · osc1 pitch · osc1 PW · osc2 pitch · osc2 PW · LFO2 rate |
| 22 | LFO1 amount | |
| 23 | LFO1 pulse width | |
| 18 | LFO1 sync on/off | switch |

### LFO 2

| CC | Parameter | Notes |
|----|-----------|-------|
| 24 | LFO2 speed (rate) | |
| 25 | LFO2 shape | block · noise · trisaw · sine |
| 26 | LFO2 destination | none · filter · amplitude · osc1 pitch · osc2 pitch · osc2 PW · pitch (both) · LFO2 rate |
| 27 | LFO2 amount | |
| 28 | LFO2 pulse width | morphs between triangle and saw when trisaw selected |
| 29 | LFO2 sync on/off | switch |

### Effects & Articulation

| CC | Parameter | Notes |
|----|-----------|-------|
| 9  | Distortion amount | |
| 17 | Distortion type | 0–63 = loud (hard clip) · 64–127 = soft clip |
| 13 | Ring modulation amount | 0 = dry mix only, 127 = full ring mod |
| 80 | Ring modulation type | 0–63 = classic (analog) · 64–127 = digital |
| 90 | FX type | 0 = off · 1–25 = R01 (short reverb) · 26–51 = R02 · 52–76 = R03 · 77–101 = R04 · 102–127 = delay |
| 94 | FX send level | |
| 5  | Portamento time | |
| 65 | Portamento on/off | switch |
| 12 | Legato switch | switch; monophonic mode |

---

## Quick Reference — CC Numbers Used by Both Synths

| CC | ANALOGIC | AXS202 |
|----|----------|--------|
| 5  | Portamento time | Portamento time |
| 8  | OSC mix | OSC mix |
| 9  | Distortion | Distortion amount |
| 12 | Legato | Legato |
| 13 | Ring mod switch | Ring mod amount |
| 18 | LFO1 sync | LFO1 sync |
| 19 | LFO1 speed | LFO1 speed |
| 20 | LFO1 shape | LFO1 shape |
| 21 | LFO1 dest | LFO1 dest |
| 22 | LFO1 amount | LFO1 amount |
| 23 | LFO1 PW | LFO1 PW |
| 24 | LFO2 speed | LFO2 speed |
| 25 | LFO2 shape | LFO2 shape |
| 26 | LFO2 dest | LFO2 dest |
| 27 | LFO2 amount | LFO2 amount |
| 28 | LFO2 PW | LFO2 PW |
| 29 | LFO2 sync | LFO2 sync |
| 30 | OSC1 shape | OSC1 shape |
| 31 | OSC2 shape | OSC2 shape |
| 33 | OSC2 fine | OSC2 fine |
| 34 | KBT | KBT |
| 35 | OSC2 sync | OSC2 sync |
| 36 | AEG decay | AEG decay |
| 37 | AEG sustain | AEG sustain |
| 38 | FEG attack | FEG attack |
| 39 | FEG decay | FEG decay |
| 40 | FEG sustain | FEG sustain |
| 41 | FEG release | FEG release |
| 42 | Vel→filter | Vel→filter |
| 43 | FEG gain | FEG gain |
| 50 | PEG attack | PEG attack |
| 51 | PEG decay | PEG decay |
| 52 | PEG sustain | PEG sustain |
| 53 | PEG release | PEG release |
| 54 | PEG gain | PEG gain |
| 65 | Portamento sw | Portamento sw |
| 71 | Resonance | Resonance |
| 72 | AEG release | AEG release |
| 73 | AEG attack | AEG attack |
| 74 | Filter cutoff | Filter cutoff |
| 75 | Filter type | Filter type |
| 77 | OSC2 semitones | OSC2 semitones |
| 78 | OSC1 PW | OSC1 PW |
| 79 | OSC2 PW | OSC2 PW |
| 94 | FX send | FX send |

CCs present in **AXS202 only**: 17 (distortion type), 45 (vel→amp), 55 (PEG dest), 70 (AEG gain), 76 (filter KBT amt), 80 (ring type), 90 (FX type).
CCs present in **ANALOGIC only**: 7 (AEG gain/vol), 11 (global FX type), 44 (base note), 123 (all notes off).
