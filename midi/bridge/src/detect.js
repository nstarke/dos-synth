/**
 * detect.js — helpers for listing and resolving MIDI ports.
 *
 * The bridge does not attempt to auto-detect 86Box's MIDI port because 86Box
 * uses whatever system MIDI device was selected in its own settings.  The user
 * must configure both sides to use the same shared virtual MIDI port:
 *
 *   Linux  : "MIDI Through"  (built into ALSA — no extra software needed)
 *   Windows: a loopMIDI virtual port  https://tobias-erichsen.de/software/loopmidi.html
 *   macOS  : an IAC Driver bus  (Audio MIDI Setup → IAC Driver → enable)
 *
 * In 86Box MPU-401 settings, select that shared port.
 * In the bridge, set --out (or midi.output in config.json) to the same port name.
 */

/**
 * Resolve a port specifier to an index into a JZZ port list.
 *
 * @param {Array<{name: string}>} ports   JZZ info.inputs or info.outputs
 * @param {string|number|null}    spec    Name substring, numeric index, or null/'auto'
 * @param {string}                label   Label used in error messages
 * @returns {number|null}  Resolved 0-based index, or null if spec was null/'auto'
 */
export function resolvePort(ports, spec, label) {
  if (spec == null || spec === 'auto') return null;

  if (/^\d+$/.test(String(spec))) {
    const idx = parseInt(spec, 10);
    if (idx < 0 || idx >= ports.length) {
      console.error(`${label} index ${idx} is out of range (${ports.length} port(s) available).`);
      process.exit(1);
    }
    return idx;
  }

  const idx = ports.findIndex(
    p => p.name.toLowerCase().includes(String(spec).toLowerCase())
  );
  if (idx === -1) {
    console.error(`${label} "${spec}" not found.`);
    ports.forEach((p, i) => console.error(`  [${i}] ${p.name}`));
    process.exit(1);
  }
  return idx;
}
