# MIDI Bridge

Host-side Node.js tools that forward MIDI from an external source (keyboard, DAW, etc.) to the shared virtual MIDI port that 86Box reads from. The agent inside the VM (`../agent/MIDI_INJ.COM`) converts the MIDI to keyboard scancodes for DOS synthesizers.

See the [project README](../../README.md) for the full signal path and setup.

## Requirements

- Node.js 18+
- A shared virtual MIDI port (loopback) that both this bridge and 86Box connect to:
  - **Linux** — `MIDI Through` is built into ALSA
  - **Windows** — install [loopMIDI](https://tobias-erichsen.de/software/loopmidi.html) and create a port
  - **macOS** — enable IAC Driver in Audio MIDI Setup
- In **86Box → Settings → Sound → MPU-401**, select that same virtual port

Install dependencies once:
```sh
npm install
```

## Tools

### `index.js` — the bridge

The main router. Opens a MIDI input (your keyboard / DAW) and a MIDI output (the shared virtual port that 86Box listens on), and forwards messages between them. Optionally filters to a single MIDI channel.

**Usage:**
```sh
node index.js [--in <name|idx>] [--out <name|idx>] [--channel <1-16>] [--name <label>]
node index.js --list      # list all MIDI inputs and outputs
node index.js --help
```

Ports can be specified by name substring (e.g. `"Arturia"`) or numeric index. Defaults come from `config.json`.

npm scripts:
```sh
npm start         # node index.js
npm run list      # node index.js --list
```

### `test.js` — end-to-end test

Plays "Mary Had a Little Lamb" through the shared virtual MIDI port. Verifies the full chain: `test.js → shared port → 86Box MPU-401 → MIDI_INJ.COM → synthesizer`. Notes are within MIDI 48–71 so they map cleanly under any layout.

**Usage:**
```sh
node test.js [--out <name|idx>] [--channel <1-16>] [--bpm <n>]
```

`--out` must match the port selected in 86Box MPU-401 settings (or be set in `config.json` under `midi.output`). Default BPM is 120.

npm script:
```sh
npm test
```

### `src/detect.js`

Internal helper used by `index.js` and `test.js` to resolve a port specifier (name substring, numeric index, or `"auto"`) into a JZZ port index. Not a standalone tool.

### `config.json`

Default `--in`, `--out`, and channel filter so you don't need to pass flags every run:

```json
{
  "midi": {
    "input":   "Arturia",
    "output":  "MIDI Through",
    "channel": "all"
  }
}
```

| Key            | Values                              | Description                                                                  |
|----------------|-------------------------------------|------------------------------------------------------------------------------|
| `midi.input`   | `"auto"`, name substring, or index  | MIDI source. `"auto"` uses the first available input.                        |
| `midi.output`  | name substring or index             | **Required.** Shared virtual port — must match 86Box MPU-401 settings.       |
| `midi.channel` | `"all"` or `1`–`16`                 | Filter input to one channel, or pass all.                                    |

CLI flags override `config.json` values.

## Connecting a source after the bridge is running (Linux)

Leave `midi.input` as `"auto"` and use `aconnect` to wire any source into the bridge after it starts:

```sh
aconnect "Arturia KeyStep 32" "DOS-Synth Bridge"
```
