/**
 * test.js — play "Mary Had a Little Lamb" through the shared virtual MIDI port.
 *
 * Verifies the full chain:
 *   test.js → shared virtual port → 86Box MPU-401 → midi_inject.asm → synthesizer
 *
 * Usage:
 *   node test.js [--out <name|idx>] [--channel <1-16>] [--bpm <n>]
 *
 * --out must match what is selected in 86Box MPU-401 settings, or be set in
 * config.json under midi.output.
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
// "Mary Had a Little Lamb" in C major
// All notes within MIDI 48-71 (C3-B4) — no octave clamping in midi_inject.asm
// ---------------------------------------------------------------------------
const C4 = 60, D4 = 62, E4 = 64, G4 = 67;

// [note, beats]  (1 = quarter note, 2 = half note)
const MELODY = [
  // Ma- ry  had  a   lit- tle  lamb,
  [E4, 1], [D4, 1], [C4, 1], [D4, 1], [E4, 1], [E4, 1], [E4, 2],
  // lit- tle  lamb,   lit- tle  lamb,
  [D4, 1], [D4, 1], [D4, 2], [E4, 1], [G4, 1], [G4, 2],
  // Ma- ry  had  a   lit- tle  lamb, its
  [E4, 1], [D4, 1], [C4, 1], [D4, 1], [E4, 1], [E4, 1], [E4, 1], [E4, 1],
  // fleece was white  as    snow.
  [D4, 1], [D4, 1], [E4, 1], [D4, 1], [C4, 2],
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--out':     args.out     = argv[++i]; break;
      case '--channel': args.channel = parseInt(argv[++i], 10) - 1; break;
      case '--bpm':     args.bpm     = parseInt(argv[++i], 10); break;
    }
  }
  return args;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function run() {
  const args = parseArgs(process.argv.slice(2));

  let cfg = {};
  try {
    cfg = JSON.parse(readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
  } catch {}

  const bpm     = args.bpm ?? 120;
  const beatMs  = Math.round(60_000 / bpm);
  const gapMs   = Math.min(30, beatMs * 0.08); // brief gap between note-off and next note-on
  const channel = args.channel ?? 0;

  const engine  = await JZZ({ client: 'DOS-Synth Test' });
  const info    = await engine.info();
  const outputs = info.outputs ?? [];

  // ---- Resolve output port --------------------------------------------------
  const outSpec = args.out ?? cfg.midi?.output ?? null;

  if (!outSpec || outSpec === 'auto') {
    console.error(
      'No MIDI output port specified.\n' +
      'Use --out <name|index> or set midi.output in config.json.\n' +
      '\nAvailable outputs:'
    );
    outputs.forEach((p, i) => console.error(`  [${i}] ${p.name}`));
    await engine.close();
    process.exit(1);
  }

  const outPortIdx = resolvePort(outputs, outSpec, 'MIDI output');
  const midiOut    = await engine.openMidiOut(outPortIdx);

  console.log(`Playing "Mary Had a Little Lamb" at ${bpm} BPM`);
  console.log(`MIDI out : [${outPortIdx}] ${outputs[outPortIdx].name}`);
  console.log(`Channel  : ${channel + 1}`);
  console.log('');

  // ---- Play -----------------------------------------------------------------
  for (const [note, beats] of MELODY) {
    const noteDur = beatMs * beats;
    midiOut.noteOn(channel, note, 100);   // Note On
    await sleep(noteDur - gapMs);
    midiOut.noteOff(channel, note, 0);    // Note Off
    await sleep(gapMs);
  }

  await sleep(beatMs); // let last note finish inside the VM
  await midiOut.close();
  await engine.close();
  console.log('Done.');
}

run().catch(err => {
  console.error('Fatal:', err.message);
  process.exit(1);
});
