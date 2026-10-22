'use strict';
// The pure judgements the own-cost steps and the P7 reports use (test/support/cost.js,
// test/support/checks.js), checked on series that stand for a frozen meter, a leaking one, a
// restarted one. No meter runs here.
const test = require('node:test');
const assert = require('node:assert');
const cost = require('./support/cost');

const t0 = Date.parse('2026-10-22T10:00:00Z');
/** `n+1` once-a-second samples whose CPU time follows `cpuAt(i)` seconds. */
const series = (n, cpuAt, stat = 'S') => Array.from({ length: n + 1 }, (_, i) => ({ at: t0 + i * 1000, stat, cpu: cpuAt(i) }));

test('liveness: a meter whose CPU time never moves is not alive (a SIGSTOPped or hung meter passes a CPU line)', () => {
  const problems = cost.liveness(series(60, () => 0.42));
  assert.ok(problems.length > 0, 'a frozen series is refused');
  assert.match(problems.join('; '), /CPU time/);
});

test('liveness: a stopped or zombie process is refused whatever its CPU time did', () => {
  const s = series(60, (i) => i * 0.01);
  s[7].stat = 'T';
  assert.match(cost.liveness(s).join('; '), /stopped|zombie|state T/);
  const z = series(60, (i) => i * 0.01);
  z[9].stat = 'Z';
  assert.ok(cost.liveness(z).length > 0);
});

test('liveness: a meter that stops moving part of the way through the minute is refused (every 20 s slice must advance)', () => {
  const s = series(60, (i) => (i < 30 ? i * 0.01 : 0.3));
  assert.match(cost.liveness(s).join('; '), /20 s/);
});

test('liveness: a meter running normally is alive', () => {
  assert.deepStrictEqual(cost.liveness(series(60, (i) => i * 0.01)), []);
});

test('ps CPU time text reads as seconds', () => {
  assert.strictEqual(cost.cpuSeconds('0:09.08'), 9.08);
  assert.strictEqual(cost.cpuSeconds('1:02.50'), 62.5);
  assert.strictEqual(cost.cpuSeconds('1:02:03.50'), 3723.5);
  assert.strictEqual(cost.cpuSeconds('12:05'), 725);
  assert.throws(() => cost.cpuSeconds('nonsense'));
});

// --- F2: the hour judges every sample ---------------------------------------------------

const MB = 1048576;
/** One closed-panel sample a minute for an hour (open at minutes 5, 6 of every ten), at `mb(minute)` MB. */
function hour(mb, { skip = () => false } = {}) {
  const out = [];
  for (let m = 0; m < 60; m++) {
    if (skip(m)) continue;
    const open = m % 10 === 5 || m % 10 === 6;
    out.push({ at: t0 + m * 60000, bytes: Math.round(mb(m) * MB), panel: open ? 'open' : 'closed', stat: 'S', cpu: m * 0.5, ax: true });
  }
  return out;
}

test('judgeHour: a steady 20 MB hour passes and prints its max', () => {
  const r = cost.judgeHour(hour(() => 20));
  assert.deepStrictEqual(r.problems, []);
  assert.strictEqual(r.max, '20.0 MB');
});

test('judgeHour: one 69 MB sample mid-hour fails even if the end readings are 21 and 18 MB (P5)', () => {
  const r = cost.judgeHour(hour((m) => (m === 30 ? 69 : 18)));
  assert.match(r.problems.join('; '), /69\.0 MB/);
});

test('judgeHour: a steady climb of 0.2 MB a minute fails (sustained growth)', () => {
  const r = cost.judgeHour(hour((m) => 20 + 0.2 * m));
  assert.match(r.problems.join('; '), /grew|growth/);
});

test('judgeHour: an 8-minute hole between samples fails', () => {
  const r = cost.judgeHour(hour(() => 20, { skip: (m) => m >= 20 && m < 28 }));
  assert.match(r.problems.join('; '), /gap/);
});

test('judgeHour: a frozen meter (CPU time not advancing, or Accessibility not answering) fails', () => {
  const frozen = hour(() => 20).map((s) => ({ ...s, cpu: 5 }));
  assert.match(cost.judgeHour(frozen).problems.join('; '), /CPU time/);
  const silent = hour(() => 20);
  silent[30].ax = false;
  assert.match(cost.judgeHour(silent).problems.join('; '), /Accessibility/);
  const stopped = hour(() => 20);
  stopped[12].stat = 'T';
  assert.match(cost.judgeHour(stopped).problems.join('; '), /state T/);
});

test('judgeHour: a shortened hour scales the windows with it', () => {
  const unit = 2000;
  const short = Array.from({ length: 60 }, (_, m) => ({ at: t0 + m * unit, bytes: 20 * MB, panel: 'closed', stat: 'S', cpu: m, ax: true }));
  assert.deepStrictEqual(cost.judgeHour(short, { hourMs: 60 * unit }).problems, []);
});

// --- S3: the release check covers MeterCore, not only the Meter target ----------------------

test('debugObjects: a MeterCore object compiled for debug is found (the check read only Meter.build)', () => {
  const nm = [
    '0000000000000000 - 00 0000    OSO /Users/x/repo/.build/arm64-apple-macosx/release/Meter.build/main.swift.o',
    '0000000000000000 - 00 0000    OSO /Users/x/repo/.build/arm64-apple-macosx/debug/MeterCore.build/Sampler.swift.o',
    '0000000000000000 - 00 0000    OSO /Users/x/repo/.build/arm64-apple-macosx/release/MeterCore.build/Share.swift.o',
    '0000000000000000 - 00 0000    OSO /usr/lib/other.o',
  ].join('\n');
  const r = cost.releaseObjects(nm);
  assert.strictEqual(r.objects.length, 3);
  assert.deepStrictEqual(r.debug, ['/Users/x/repo/.build/arm64-apple-macosx/debug/MeterCore.build/Sampler.swift.o']);
});
