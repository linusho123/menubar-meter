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
/**
 * A 20 s slice must show at least one tick of ps's 10 ms CPU time: the real meter uses about 1.5 ms
 * a second (0.015% of the Mac), so 20 s is 0.02 to 0.04 s and a stricter slice line would fail a
 * healthy meter, while a stopped one reads exactly 0.
 */
const SLICE_ADVANCE = 0.01;
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
    if (samples[to].at - samples[from].at >= SLICE_SECONDS * 500 && samples[to].cpu - samples[from].cpu < SLICE_ADVANCE) {
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
 * The objects a program was linked from, as `nm -ap` records them (the debug-map "OSO" lines): every
 * path under a .build folder, whatever its target (Meter, MeterCore), and those among them not
 * compiled in the release configuration.
 */
function releaseObjects(nmOutput) {
  const objects = nmOutput.split('\n').filter((l) => / OSO /.test(l)).map((l) => l.replace(/^.* OSO /, '')).filter((o) => /\/\.build\//.test(o));
  return { objects, debug: objects.filter((o) => !/\/release\//.test(o)) };
}

const MB = 1048576;
/** A footprint as Activity Monitor's Memory column shows it: megabytes of 1,048,576 bytes, one decimal. */
const shownMB = (bytes) => `${(Math.round((bytes / MB) * 10) / 10).toFixed(1)} MB`;
const underLine = (bytes, megabytes = 50) => Number(shownMB(bytes).replace(' MB', '')) < megabytes;
const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

/**
 * Judges the memory hour: `samples` are { at (ms), bytes, panel ('open'|'closed'), stat, cpu (s),
 * ax (whether Accessibility answered) }, oldest first, over `hourMs`. Every sample must be shown
 * under 50.0 MB (not just the end readings), the closed-panel readings of the last ten minutes must
 * be no more than 5 MB above those of minutes 2 to 11 (no sustained growth), no two samples may be
 * more than 1.5 sample intervals (90 s) apart, and the meter must be alive at every sample (state,
 * CPU time advancing, Accessibility answering). Returns { problems, max, first, last }.
 */
function judgeHour(samples, { hourMs = 3600 * 1000 } = {}) {
  const problems = [];
  if (samples.length < 2) return { problems: ['fewer than two samples'], max: null };
  const unit = hourMs / 60;
  const start = samples[0].at;
  const maxBytes = Math.max(...samples.map((s) => s.bytes));
  const max = shownMB(maxBytes);
  const over = samples.filter((s) => !underLine(s.bytes));
  if (over.length) {
    problems.push(`${over.length} reading(s) at or over 50.0 MB, the highest ${max} (at minute ${(((over[0].at - start) / unit)).toFixed(0)}, panel ${over[0].panel})`);
  }
  const closed = (from, to) => samples.filter((s) => s.panel === 'closed' && s.at - start >= from * unit && s.at - start < to * unit).map((s) => s.bytes);
  const early = closed(2, 12);
  const late = closed(50, 61);
  if (!early.length || !late.length) {
    problems.push('no closed-panel readings in minutes 2 to 11 or 50 to 59: growth cannot be judged');
  } else if (mean(late) - mean(early) > 5 * MB) {
    problems.push(`memory grew: the closed-panel mean was ${shownMB(mean(early))} in minutes 2 to 11 and ${shownMB(mean(late))} in minutes 50 to 59 (more than 5 MB up)`);
  }
  // 90 s for the real hour; a shortened hour (checking the row itself) keeps 15 s for the click's reading.
  const gapMs = Math.max(1.5 * unit, unit + 15000);
  for (let i = 1; i < samples.length; i++) {
    if (samples[i].at - samples[i - 1].at > gapMs) {
      problems.push(`gap of ${((samples[i].at - samples[i - 1].at) / 1000).toFixed(0)} s between samples at minute ${((samples[i - 1].at - start) / unit).toFixed(0)} (more than ${(gapMs / 1000).toFixed(0)} s)`);
      break;
    }
  }
  if (samples.at(-1).at - start < hourMs - gapMs) problems.push('the samples stop before the hour is out');
  const dead = samples.find((s) => /^[TZ]/.test(s.stat));
  if (dead) problems.push(`the meter was in state ${dead.stat} at minute ${((dead.at - start) / unit).toFixed(0)}`);
  const silent = samples.find((s) => s.ax === false);
  if (silent) problems.push(`the meter did not answer Accessibility at minute ${((silent.at - start) / unit).toFixed(0)}`);
  // CPU time must advance over every 60 s of the hour (the meter uses about 0.09 s a minute; ps reads
  // it in 10 ms ticks, so a shorter window would read zero on a healthy meter).
  for (let i = 0; i < samples.length; i++) {
    const j = samples.findIndex((s, k) => k > i && s.at - samples[i].at >= 57000);
    if (j < 0) break;
    if (samples[j].cpu - samples[i].cpu < MIN_ADVANCE) {
      problems.push(`its CPU time did not advance over the minute from minute ${((samples[i].at - start) / unit).toFixed(0)}: a stopped or hung meter`);
      break;
    }
  }
  return { problems, max, first: shownMB(samples[0].bytes), last: shownMB(samples.at(-1).bytes) };
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

module.exports = { cpuOver, memory, psTime, psStatTime, cpuSeconds, liveness, axAlive, judgeHour, releaseObjects, shownMB, underLine };
