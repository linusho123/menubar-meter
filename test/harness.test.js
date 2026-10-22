'use strict';
// The harness itself: it refuses to run beside a meter it did not start. A real meter in the
// menu bar (the one the manual log-in check leaves installed) holds Control-Option-Command-M
// and would make every count of meters wrong.
const test = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const paths = require('./support/paths');
const procs = require('./support/procs');
const meter = require('./support/meter');

test('launchReal throws beside a meter the harness did not start, and starts beside its own', async () => {
  // A meter started outside the harness, as a user's launch would.
  const foreign = spawn(paths.releaseApp, [], { stdio: 'ignore' });
  const started = procs.startTimeOf(foreign.pid);
  const cleanups = [];
  const world = { defer: (fn) => cleanups.push(fn) };
  try {
    await procs.sleep(500);
    await assert.rejects(() => meter.launchReal(world), /a meter the harness did not start is running \(pid \d+\)/);
    assert.deepStrictEqual(procs.foreignMeters(), [foreign.pid]);
  } finally {
    for (const fn of cleanups.reverse()) await fn();
    if (procs.startTimeOf(foreign.pid) === started) foreign.kill('SIGTERM');
    await procs.sleep(1000);
  }
  assert.deepStrictEqual(procs.foreignMeters(), [], 'the foreign meter has ended');
  const own = {};
  const cleanup2 = [];
  try {
    await meter.launchReal({ defer: (fn) => cleanup2.push(fn), ...own });
    assert.deepStrictEqual(procs.foreignMeters(), [], 'a meter the harness started is its own');
  } finally {
    for (const fn of cleanup2.reverse()) await fn();
  }
});
