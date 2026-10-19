'use strict';
// The far side: what macOS's Accessibility API says the menu bar shows,
// read through the harness helper (build/meter-harness).
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { harness } = require('./paths');

const run = promisify(execFile);

async function helper(args) {
  try {
    const { stdout } = await run(harness, args, { encoding: 'utf8' });
    return JSON.parse(stdout);
  } catch (e) {
    if (e.code === 3) {
      throw new Error('Accessibility permission is needed: System Settings → Privacy & Security → Accessibility, for the terminal running the tests');
    }
    if (e.stdout) return JSON.parse(e.stdout);
    throw e;
  }
}

/** The status item of the app with this pid: {title, x, y, w, h} or null. */
async function item(pid) {
  const r = await helper(['item', String(pid)]);
  return r.error ? null : r;
}

/** Every status item of the app with this pid. */
async function items(pid) {
  const r = await helper(['items', String(pid)]);
  return r.items || [];
}

/**
 * Poll the item's title until it matches `re` or the deadline passes.
 * Resolves {matched, seenAtEpochMs, title}.
 */
async function watch(pid, re, deadlineEpochMs) {
  return helper(['watch', String(pid), re.source, String(Math.round(deadlineEpochMs))]);
}

// `CPU 100%  GPU   7%  RAM  93%   98°C`: four fixed-width fields.
const LAYOUT = /^(CPU (.{3})%)  (GPU (.{3})%)  (RAM (.{3})%)  ((.{3})°C)$/u;
const READINGS = ['CPU', 'GPU', 'RAM', 'temperature'];

/** Split the item's text into its fields; null if the text has another shape. */
function parse(title) {
  const m = LAYOUT.exec(title ?? '');
  if (!m) return null;
  return {
    segment: { CPU: m[1], GPU: m[3], RAM: m[5], temperature: m[7] },
    value: {
      CPU: m[2].trim() + '%', GPU: m[4].trim() + '%', RAM: m[6].trim() + '%', temperature: m[8].trim() + '°C',
    },
  };
}

function escape(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

/** A regex matching an item title whose `reading` value shows `shown` (e.g. "80%"). */
function valueRegex(reading, shown) {
  const n = shown.replace(/%|°C$/u, '');
  if (n.length > 3) throw new Error(`"${shown}" cannot fit a three-character slot`);
  const slot = ' '.repeat(3 - n.length) + n;
  const any = '.{3}';
  const f = { CPU: any, GPU: any, RAM: any, temperature: any };
  f[reading] = escape(slot);
  return new RegExp(`^CPU ${f.CPU}%  GPU ${f.GPU}%  RAM ${f.RAM}%  ${f.temperature}°C$`, 'u');
}

module.exports = { item, items, watch, parse, valueRegex, READINGS };
