/**
 * dos-synth-midi-bridge
 *
 * Routes MIDI from an external source to the shared virtual MIDI port that
 * 86Box is configured to use in its MPU-401 settings.  The dos-synth TSR
 * (midi/agent/midi_inject.asm) running inside the VM reads MIDI from the
 * MPU-401 and injects the corresponding XT Set-1 scancodes via the 8042,
 * firing IRQ1/INT 9 so synthesizer programs detect the notes.
 *
 * Routing:
 *   [External MIDI source]
 *        │  (connect via aconnect / DAW / OS MIDI routing)
 *        ▼
 *   [Bridge MIDI input]  ←── this process
 *        │
 *        ▼
 *   [Shared virtual MIDI port]  ←── also selected in 86Box MPU-401 settings
 *        │
 *        ▼
 *   MPU-401 (emulated)  ──→  midi_inject.asm TSR  ──→  DOS synthesizer
 *
 * The shared virtual MIDI port must be created separately:
 *   Linux  : "MIDI Through" (built into ALSA, no setup needed)
 *   Windows: loopMIDI  https://tobias-erichsen.de/software/loopmidi.html
 *   macOS  : IAC Driver (Audio MIDI Setup → IAC Driver → enable)
 *
 * Usage:
 *   node index.js [options]
 *
 * Options:
 *   --in  <name|idx>  MIDI input device to receive from
 *   --out <name|idx>  Shared virtual MIDI port (must match 86Box MPU-401 setting)
 *   --name <label>    ALSA/CoreMIDI client name for this bridge instance
 *   --channel <n>     Filter to MIDI channel 1-16 (default: all)
 *   --list            List available MIDI inputs and outputs and exit
 *   --help            Show this help
 */

import { createRequire } from 'module';
import { readFileSync }  from 'fs';
import { fileURLToPath } from 'url';
import path              from 'path';

import { resolvePort } from './src/detect.js';

const require   = createRequire(import.meta.url);
const JZZ       = require('jzz');
const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------------
// Config / args
// ---------------------------------------------------------------------------

function loadConfig() {
  try {
    return JSON.parse(readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
  } catch (err) {
    console.error('Could not read config.json:', err.message);
    process.exit(1);
  }
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--in':      args.in      = argv[++i]; break;
      case '--out':     args.out     = argv[++i]; break;
      case '--name':    args.name    = argv[++i]; break;
      case '--channel': args.channel = parseInt(argv[++i], 10) - 1; break;
      case '--list':    args.list    = true; break;
      case '--help':    args.help    = true; break;
    }
  }
  return args;
}

function showHelp() {
  console.log(`
dos-synth-midi-bridge — route MIDI to the shared virtual port that 86Box reads from

Usage:
  node index.js [options]

Options:
  --in  <name|idx>   MIDI input device (name substring or index).
                     Defaults to the config value or first available device.
  --out <name|idx>   Shared virtual MIDI port (name substring or index).
                     Must match what is selected in 86Box MPU-401 settings.
                     Set once in config.json to avoid passing it every time.
  --name <label>     ALSA/CoreMIDI client name for this bridge instance.
  --channel <1-16>   Filter input to one MIDI channel (default: pass all).
  --list             Print all available MIDI inputs and outputs, then exit.
  --help             Show this help.

Shared virtual MIDI port (create once, select in both bridge and 86Box):
  Linux  : "MIDI Through"  — built into ALSA, already available
  Windows: loopMIDI        — https://tobias-erichsen.de/software/loopmidi.html
  macOS  : IAC Driver      — Audio MIDI Setup → IAC Driver → check "Device is online"
`.trim());
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function run() {
  const cfg  = loadConfig();
  const args = parseArgs(process.argv.slice(2));

  if (args.help) { showHelp(); process.exit(0); }

  const instanceName = args.name ?? cfg.midi?.name ?? 'DOS-Synth Bridge';

  const channelFilter = args.channel !== undefined
    ? args.channel
    : (cfg.midi?.channel === 'all' ? null : (cfg.midi?.channel != null ? cfg.midi.channel - 1 : null));

  // ---- Start JZZ engine -----------------------------------------------------
  const engine = await JZZ({ client: instanceName });
  const info   = await engine.info();
  const inputs  = info.inputs  ?? [];
  const outputs = info.outputs ?? [];

  // ---- --list ---------------------------------------------------------------
  if (args.list) {
    console.log(`MIDI inputs (${inputs.length}):`);
    inputs.forEach((p, i)  => console.log(`  [${i}] ${p.name}`));
    console.log(`\nMIDI outputs (${outputs.length}):`);
    outputs.forEach((p, i) => console.log(`  [${i}] ${p.name}`));
    await engine.close();
    process.exit(0);
  }

  // ---- Resolve MIDI input port ----------------------------------------------
  const inSpec    = args.in ?? cfg.midi?.input ?? 'auto';
  let   inPortIdx = resolvePort(inputs, inSpec, 'MIDI input');

  if (inPortIdx === null) {
    if (inputs.length === 0) {
      console.error('No MIDI input devices found.');
      await engine.close();
      process.exit(1);
    }
    inPortIdx = 0;
  }

  // ---- Resolve MIDI output port (shared virtual port) ----------------------
  const outSpec = args.out ?? cfg.midi?.output ?? null;

  if (!outSpec || outSpec === 'auto') {
    console.error(
      'No MIDI output port specified.\n' +
      'Set --out <name|index> or set midi.output in config.json.\n' +
      '\nAvailable outputs:'
    );
    outputs.forEach((p, i) => console.error(`  [${i}] ${p.name}`));
    console.error(
      '\nThis must match the port selected in 86Box MPU-401 settings.\n' +
      'Run "node index.js --help" for setup instructions.'
    );
    await engine.close();
    process.exit(1);
  }

  const outPortIdx = resolvePort(outputs, outSpec, 'MIDI output');

  // ---- Open ports -----------------------------------------------------------
  const midiIn  = await engine.openMidiIn(inPortIdx);
  const midiOut = await engine.openMidiOut(outPortIdx);

  // ---- Print startup info ---------------------------------------------------
  console.log(`\n=== DOS-Synth MIDI Bridge ===`);
  console.log(`Client   : ${instanceName}`);
  console.log(`MIDI in  : [${inPortIdx}] ${inputs[inPortIdx].name}`);
  console.log(`MIDI out : [${outPortIdx}] ${outputs[outPortIdx].name}`);
  console.log(`Channel  : ${channelFilter === null ? 'all' : channelFilter + 1}`);
  console.log('');

  // ---- Route MIDI: input → shared virtual port → 86Box --------------------
  if (channelFilter === null) {
    midiIn.connect(midiOut);
  } else {
    midiIn.connect((msg) => {
      if (msg[0] >= 0xF0) { midiOut.send(msg); return; }
      if ((msg[0] & 0x0F) === channelFilter) midiOut.send(msg);
    });
  }

  console.log('Bridge running.  Press Ctrl+C to stop.\n');

  async function shutdown() {
    console.log(`\n[${instanceName}] Shutting down...`);
    try { await midiIn.close();  } catch {}
    try { await midiOut.close(); } catch {}
    try { await engine.close();  } catch {}
    process.exit(0);
  }

  process.on('SIGINT',  shutdown);
  process.on('SIGTERM', shutdown);
}

run().catch(err => {
  console.error('Fatal:', err.message);
  process.exit(1);
});
