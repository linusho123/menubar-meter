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
