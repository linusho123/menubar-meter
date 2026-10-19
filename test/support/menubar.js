'use strict';
// What the user sees in the menu bar, read through the Accessibility API by the meter-ax
// helper, the same tree any assistive app reads. Never anything the meter writes for tests.
const { execFileSync, spawn } = require('node:child_process');
const readline = require('node:readline');
const paths = require('./paths');
const { sleep } = require('./procs');

function ax(args) {
  return JSON.parse(execFileSync(paths.meterAx, args, { encoding: 'utf8' }));
}

/** The status items of one app. */
function itemsOf(pid) {
  return ax(['item', String(pid)]);
}

/** Every visible status item in the menu bar, of every app. */
function allItems() {
  return ax(['items']).filter((i) => i.width > 0 && i.height > 0);
}

const FIELDS = /^CPU (.{3})%  GPU (.{3})%  RAM (.{3})%  (.{3})°C$/u;

/** Splits the readout text into its four values as the user reads them ("80%", "70°C", "–%"). */
function fields(title) {
  const m = FIELDS.exec(title);
  if (!m) return null;
  return {
    CPU: `${m[1].trim()}%`,
    GPU: `${m[2].trim()}%`,
    RAM: `${m[3].trim()}%`,
    temperature: `${m[4].trim()}°C`,
  };
}

/** Polls the meter's item until `predicate(item)` holds; returns the item or throws. */
async function waitForItem(pid, predicate, timeoutMs, what) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() < deadline) {
    const items = itemsOf(pid);
    if (items.length === 1) {
      last = items[0];
      if (predicate(last)) return last;
    }
    await sleep(50);
  }
  throw new Error(`timed out after ${timeoutMs} ms waiting for ${what}; last item: ${JSON.stringify(last)}`);
}

/**
 * Watches the item's title through Accessibility, recording each change with its time.
 * Resolves once the watcher has seen the current title.
 */
async function watch(pid, durationMs) {
  const child = spawn(paths.meterAx, ['watch', String(pid), String(durationMs)], {
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const seen = [];
  const lines = readline.createInterface({ input: child.stdout });
  lines.on('line', (line) => {
    const [stamp, ...rest] = line.split('\t');
    seen.push({ at: Number(stamp), title: rest.join('\t') });
  });
  const done = new Promise((resolve) => child.on('exit', resolve));
  const deadline = Date.now() + 3000;
  while (seen.length === 0 && Date.now() < deadline) await sleep(10);
  if (seen.length === 0) throw new Error('the Accessibility watcher saw no status item');
  return { seen, done, stop: () => child.kill('SIGTERM') };
}

module.exports = { itemsOf, allItems, fields, waitForItem, watch };
