'use strict';
// The meter's own cost, read from outside it with macOS's own tools: its CPU time from `ps`, and
// its memory from `footprint` (the physical footprint, which Activity Monitor's Memory column
// shows). The arithmetic is meter-cost's (OwnCost, unit-tested); nothing here asks the meter.
const { execFileSync } = require('node:child_process');
const paths = require('./paths');
const { sleep } = require('./procs');

const run = (file, args, input) => execFileSync(file, args, { encoding: 'utf8', input });

/** The process's CPU time so far, as `ps -o time=` prints it ("0:09.08"). */
function psTime(pid) {
  const text = run('ps', ['-o', 'time=', '-p', String(pid)]).trim();
  if (!text) throw new Error(`ps reads no CPU time for ${pid}`);
  return text;
}

/**
 * Samples the process's CPU time once a second for `seconds`, then works out its CPU use as a
 * share of the whole Mac: { mean, peak, seconds, samples }. `stillOk(pid)` is checked at every
 * sample, so a process replaced under its pid ends the measurement.
 */
async function cpuOver(pid, seconds, stillOk = () => true) {
  const samples = [];
  const start = Date.now();
  for (let i = 0; i <= seconds; i++) {
    const due = start + i * 1000;
    if (Date.now() < due) await sleep(due - Date.now());
    if (!stillOk(pid)) throw new Error(`the meter (pid ${pid}) is no longer the one measured`);
    const before = Date.now();
    const text = psTime(pid);
    samples.push(`${(before + Date.now()) / 2}\t${text}`);
  }
  const cores = Number(run('sysctl', ['-n', 'hw.ncpu']).trim());
  const result = JSON.parse(run(paths.meterCost, ['cpu', String(cores)], samples.join('\n')));
  return { ...result, samples };
}

/** The process's memory as Activity Monitor's Memory column shows it: { bytes, shown, under50 }. */
function memory(pid) {
  const out = run('footprint', ['-f', 'bytes', '--noCategories', '-p', String(pid)]);
  return JSON.parse(run(paths.meterCost, ['footprint'], out));
}

module.exports = { cpuOver, memory, psTime };
