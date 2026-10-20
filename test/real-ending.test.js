'use strict';
// End and Force Quit in the release app, reading the real Mac: the list holds every task the
// user runs, and the only ones a click may land on are the harness's own stand-ins, busy enough
// to rank first. Checked by the stand-ins' own records and by how macOS reports they exited.
// This backs the ending-tasks scenarios, which rank their stand-ins through the test reading
// source; it never stands in for one.
const test = require('node:test');
const assert = require('node:assert');
const paths = require('./support/paths');
const procs = require('./support/procs');
const menubar = require('./support/menubar');
const standins = require('./support/standins');
const tasks = require('./support/tasks');

/** A scope whose cleanups run last-first, as a scenario's world runs them. */
async function withWorld(body) {
  const cleanups = [];
  const world = { defer: (fn) => cleanups.push(fn) };
  try {
    await body(world);
  } finally {
    for (const fn of cleanups.reverse()) await fn();
  }
}

const buttonOf = (meterPid, name) => {
  const rows = tasks.rowsNamed(tasks.listNow(meterPid), name);
  return rows.length === 1 && rows[0].buttons[0] ? rows[0].buttons[0].text : null;
};

async function until(predicate, timeoutMs, what) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      if (predicate()) return;
    } catch {
      // An Accessibility read that failed: try again.
    }
    await procs.sleep(100);
  }
  throw new Error(`timed out waiting for ${what}`);
}

test('End and Force Quit end real stand-ins, and only them, in the release app (D60, D62)', async () => {
  await withWorld(async (w) => {
    // A windowless task that ignores the terminate signal, on four cores; the stand-in app
    // named Xcode on three, which quits 1.5 s after it is asked.
    const stubborn = await standins.start(w, 'stubborn', { busy: 4 });
    const xcode = await standins.start(w, 'Xcode', { app: true, busy: 3, quitAfterMs: 1500 });
    const meter = procs.start(paths.releaseApp);
    w.defer(() => procs.end(meter));
    await menubar.waitForItem(meter.pid, (i) => !!menubar.fields(i.title), 10000, 'the meter');
    await tasks.openAndRead(meter.pid, 5);
    await until(() => buttonOf(meter.pid, 'stubborn') === 'End' && buttonOf(meter.pid, 'Xcode') === 'End', 8000,
      'both stand-ins listed with End');

    // End on the app: its own quit request, then it quits and its row leaves.
    const appClick = await standins.clickButton(w, meter.pid, xcode, 'End');
    await until(() => standins.requests(xcode).length > 0, 3000, 'the quit request');
    assert.deepStrictEqual(standins.requests(xcode).map((e) => `${e.kind} ${e.detail}`), ['QUIT aevt/quit']);
    assert.ok(standins.requests(xcode)[0].at - appClick <= 1000, 'it came at once');
    assert.strictEqual(buttonOf(meter.pid, 'Xcode'), 'Ending…');
    await until(() => !standins.isRunning(xcode), 5000, 'Xcode to quit');
    assert.deepStrictEqual([xcode.owned.exit.code, xcode.owned.exit.signal], [0, null], 'it quit by itself');
    await until(() => tasks.rowsNamed(tasks.listNow(meter.pid), 'Xcode').length === 0, 3000, 'its row to leave');

    // End on the windowless task: the terminate signal; Ending… then Force Quit at five
    // seconds; Force Quit kills it.
    const endAt = await standins.clickButton(w, meter.pid, stubborn, 'End');
    await until(() => standins.requests(stubborn).length > 0, 3000, 'the terminate signal');
    assert.deepStrictEqual(standins.requests(stubborn).map((e) => e.kind), ['TERM']);
    assert.strictEqual(buttonOf(meter.pid, 'stubborn'), 'Ending…');
    await until(() => buttonOf(meter.pid, 'stubborn') === 'Force Quit', 7000, 'Force Quit');
    assert.ok(Date.now() - endAt >= 5000, 'not before five seconds');
    assert.ok(standins.isRunning(stubborn), 'ps: it still runs');
    const killAt = await standins.clickButton(w, meter.pid, stubborn, 'Force Quit');
    await until(() => !standins.isRunning(stubborn), 1000, 'the task to end');
    assert.strictEqual(stubborn.owned.exit.signal, 'SIGKILL');
    assert.ok(stubborn.owned.exit.at - killAt <= 1000, 'at once');
    assert.deepStrictEqual(standins.requests(stubborn).map((e) => e.kind), ['TERM'], 'asked nothing more');
    await until(() => tasks.rowsNamed(tasks.listNow(meter.pid), 'stubborn').length === 0, 3000, 'its row to leave');
  });
});
