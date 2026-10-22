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

/** `ps -o time=` text ("0:09.08", "1:02:03.50", "12:05") as seconds. */
function cpuSeconds(text) {
  const m = /^(?:(\d+):)?(\d+):(\d+(?:\.\d+)?)$/.exec(String(text).trim());
  if (!m) throw new Error(`not a ps CPU time: "${text}"`);
  return Number(m[1] || 0) * 3600 + Number(m[2]) * 60 + Number(m[3]);
}

/** The process's state and CPU time in one `ps` read: { stat: "S", time: "0:09.08" }. */
function psStatTime(pid) {
  const text = run('ps', ['-o', 'stat=,time=', '-p', String(pid)]).trim();
  const m = /^(\S+)\s+(\S+)$/.exec(text);
  if (!m) throw new Error(`ps reads no state and CPU time for ${pid}`);
  return { stat: m[1], time: m[2] };
}

/** How little CPU time a running meter can use in a slice and still be called alive. */
const MIN_ADVANCE = 0.02;
const SLICE_SECONDS = 20;

/**
 * Whether the samples ({ at (ms), stat, cpu (s) }, in order) show a meter alive and running: never
 * in the stopped (T) or zombie (Z) state, its CPU time advancing over the whole window and in every
 * 20 s slice of it. A SIGSTOPped or hung meter uses no CPU, so a CPU line alone passes it (P7 head
 * review, B-M1). Returns the list of reasons it is not; empty when it is.
 */
function liveness(samples) {
  const problems = [];
  if (samples.length < 2) return ['fewer than two samples: liveness cannot be judged'];
  for (const s of samples) {
    if (/^[TZ]/.test(s.stat)) {
      problems.push(`the process was in state ${s.stat} (${s.stat[0] === 'T' ? 'stopped' : 'zombie'}) at ${new Date(s.at).toISOString()}`);
      break;
    }
  }
  const first = samples[0];
  const last = samples.at(-1);
  if (last.cpu - first.cpu < MIN_ADVANCE) {
    problems.push(`its CPU time did not advance (${first.cpu} s to ${last.cpu} s over ${((last.at - first.at) / 1000).toFixed(0)} s): a stopped or hung meter`);
  }
  for (let from = 0; from < samples.length - 1; ) {
    let to = from;
    while (to + 1 < samples.length && samples[to].at - samples[from].at < SLICE_SECONDS * 1000) to++;
    // A last slice shorter than half a slice is not judged.
    if (samples[to].at - samples[from].at >= SLICE_SECONDS * 500 && samples[to].cpu - samples[from].cpu < MIN_ADVANCE) {
      problems.push(`its CPU time did not advance in the 20 s slice from second ${((samples[from].at - first.at) / 1000).toFixed(0)}`);
      break;
    }
    if (to === from) break;
    from = to;
  }
  return problems;
}

/**
 * Whether the meter answers Accessibility with its status item and a non-empty title. A hung main
 * thread cannot answer, so this holds where a CPU line cannot.
 */
function axAlive(pid) {
  try {
    const items = JSON.parse(execFileSync(paths.meterAx, ['item', String(pid)], { encoding: 'utf8', timeout: 15000 }));
    return items.length === 1 && typeof items[0].title === 'string' && items[0].title.length > 0;
  } catch {
    return false;
  }
}

/**
 * Samples the process's CPU time once a second for `seconds`, then works out its CPU use as a
 * share of the whole Mac: { mean, peak, seconds, samples }. `stillOk(pid)` is checked at every
 * sample, so a process replaced under its pid ends the measurement.
 */
async function cpuOver(pid, seconds, stillOk = () => true) {
  const samples = [];
  const live = [];
  const axProblems = [];
  const start = Date.now();
  for (let i = 0; i <= seconds; i++) {
    const due = start + i * 1000;
    if (Date.now() < due) await sleep(due - Date.now());
    if (!stillOk(pid)) throw new Error(`the meter (pid ${pid}) is no longer the one measured`);
    const before = Date.now();
    const { stat, time } = psStatTime(pid);
    const at = (before + Date.now()) / 2;
    samples.push(`${at}\t${time}`);
    live.push({ at, stat, cpu: cpuSeconds(time) });
    // Accessibility must answer at the start of the minute and again at its end.
    if ((i === 0 || i === seconds) && !axAlive(pid)) {
      axProblems.push(`the meter did not answer Accessibility with its status item at second ${i}`);
    }
  }
  const cores = Number(run('sysctl', ['-n', 'hw.ncpu']).trim());
  const result = JSON.parse(run(paths.meterCost, ['cpu', String(cores)], samples.join('\n')));
  return { ...result, samples, alive: [...axProblems, ...liveness(live)] };
}

/** The process's memory as Activity Monitor's Memory column shows it: { bytes, shown, under50 }. */
function memory(pid) {
  const out = run('footprint', ['-f', 'bytes', '--noCategories', '-p', String(pid)]);
  return JSON.parse(run(paths.meterCost, ['footprint'], out));
}

module.exports = { cpuOver, memory, psTime, psStatTime, cpuSeconds, liveness, axAlive };
