'use strict';
// ending-tasks.feature. Every task a scenario can end is a stand-in the harness started (see
// support/standins.js): the stand-in app named Xcode, which records the quit request it
// receives, and windowless tasks, which record the terminate signal and ignore it until the
// harness lets them quit. Givens describe the tasks' CPU to the test reading source, so the list
// holds those tasks alone, in a known order; their start time, owner, program and name are the
// real system's, and each is listed only while its process runs. The meter's ender always acts on
// the real system. Every Then reads what macOS shows: the list through Accessibility, `ps` for
// which tasks run, the stand-ins' own records of what they received, and how each one exited.
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const feeds = require('../support/feed');
const meter = require('../support/meter');
const paths = require('../support/paths');
const probes = require('../support/probes');
const procs = require('../support/procs');
const standins = require('../support/standins');
const tasks = require('../support/tasks');

const ENDING = 'Ending…';
const FORCE_QUIT = 'Force Quit';

const required = (value, what) => {
  if (value === undefined || value === null) throw new Error(`world.${what} read before any step set it`);
  return value;
};
const describeRows = (shown) => shown.rows.map((r) => `${r.name} [${r.buttons.map((b) => `${b.text}${b.enabled === false ? ' (disabled)' : ''}`)}]`).join('; ');
const meterWindows = (m) => JSON.parse(execFileSync(paths.meterAx, ['windows', String(m.pid)], { encoding: 'utf8' }));
const sampleRows = (s) => s.rows.map((r) => `${r.name}:${r.button}`).join(', ');

/** The feed's entry for a stand-in at `cpu`% of the Mac: its rates only. */
function fedStandIn(standIn, cpu) {
  return {
    pid: standIn.pid,
    real: true,
    started: 1,
    name: standIn.name,
    uid: tasks.myUid(),
    path: null,
    busyCores: (cpu / 100) * probes.cpuCount(),
    gpuShare: 0,
    memory: Math.round(0.01 * feeds.physicalMemory()),
  };
}

/** The scenario's tasks fed to the meter: its stand-ins at their CPU, and quiet ones below. */
function taskFeed(w) {
  if (!w.quiet) w.quiet = tasks.quietTasks(4, { cpuFrom: 2 });
  return [...w.cpu.entries()].map(([name, cpu]) => fedStandIn(w.standIns.get(name), cpu)).concat(w.quiet);
}

/**
 * Starts the stand-ins `scene` names ([name, cpu, options]), the test meter fed their CPU, and
 * opens the panel; waits until the five CPU rows read the scene's top five, in order.
 */
async function setUp(w, scene) {
  w.standIns = new Map();
  w.cpu = new Map();
  for (const [name, cpu, options] of scene) {
    w.standIns.set(name, await standins.start(w, name, options));
    w.cpu.set(name, cpu);
  }
  const values = feeds.readings({ cpu: 40, gpu: 10, ram: 40, temp: 50 });
  values.tasks = taskFeed(w);
  const m = await meter.launchWithFeed(w, values);
  const top = scene.slice().sort((a, b) => b[1] - a[1]).slice(0, 5).map(([name]) => name);
  await tasks.openAndRead(m.pid, 5);
  await tasks.waitForList(m.pid, (l) => l.rows.map((r) => r.name).join() === top.join(), 5000, `the rows ${top}`);
  return m;
}

const others = (w, name) => [...w.standIns.values()].filter((s) => s.name !== name);

/** The scene for "a task": the stand-in in the second row among four others, all windowless. */
const taskScene = [['busy1', 30], ['standin', 25], ['busy2', 20], ['busy3', 15], ['busy4', 10]];

/** Clicks End on the stand-in "a task" names, and starts watching the list and the tasks. */
async function clickEndOnTask(w) {
  const m = await setUp(w, taskScene);
  w.task = w.standIns.get('standin');
  w.clickedAt = await standins.clickButton(w, m.pid, w.task, 'End');
  w.timeline = standins.timeline(w, m.pid, [...w.standIns.values()]);
}

/** Waits for the timeline to hold a sample `predicate` accepts; returns it. */
async function waitForSample(w, predicate, timeoutMs, what) {
  const { samples } = required(w.timeline, 'timeline');
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const found = samples.find(predicate);
    if (found) return found;
    if (Date.now() > deadline) {
      throw new Error(`timed out waiting for ${what}; last seen: ${samples.length ? sampleRows(samples[samples.length - 1]) : 'nothing'}`);
    }
    await procs.sleep(50);
  }
}

const buttonOf = (sample, name) => {
  const row = sample.rows.find((r) => r.name === name);
  return row ? row.button : undefined;
};

/** The stand-in's own record: exactly one terminate signal, nothing else, at the End click. */
function assertAskedOnce(task, clickedAt) {
  const got = standins.requests(task);
  assert.deepStrictEqual(got.map((e) => e.kind), ['TERM'], `${task.name} received ${JSON.stringify(got)}`);
  assert.ok(got[0].at >= clickedAt - 50 && got[0].at <= clickedAt + 1500, `the terminate signal came with the click (${got[0].at - clickedAt} ms)`);
}

module.exports = (reg) => {
  // --- Ending a task that quits (D60) ---

  reg.define(/^Xcode is in the heavy-tasks list$/, async (w) => {
    // Xcode, the stand-in app, second by CPU; it takes a moment to quit once asked, as an app
    // does that closes its windows. busy5 is the next-highest task, just outside the five.
    await setUp(w, [
      ['busy1', 30], ['Xcode', 25, { app: true, quitAfterMs: 2500 }], ['busy2', 20], ['busy3', 15], ['busy4', 10], ['busy5', 5],
    ]);
    w.xcode = w.standIns.get('Xcode');
    const shown = tasks.listNow(w.meter.pid);
    const row = tasks.rowsNamed(shown, 'Xcode')[0];
    assert.ok(row && row.buttons.map((b) => b.text).join() === 'End', `Xcode's row has End: ${describeRows(shown)}`);
    assert.deepStrictEqual(standins.requests(w.xcode), [], 'Xcode has been asked nothing yet');
  });

  reg.define(/^the user clicks End on Xcode's row$/, async (w) => {
    const m = required(w.meter, 'meter');
    w.clickedAt = await standins.clickButton(w, m.pid, required(w.xcode, 'xcode'), 'End');
    w.timeline = standins.timeline(w, m.pid, [...w.standIns.values()]);
  });

  reg.define(/^Xcode receives the same quit request its own Quit menu sends, with no confirmation shown by the meter first$/, async (w) => {
    const xcode = required(w.xcode, 'xcode');
    const clickedAt = required(w.clickedAt, 'clickedAt');
    const m = required(w.meter, 'meter');
    // The click alone sends it: nothing more is clicked, and it arrives at once.
    let got = [];
    const deadline = clickedAt + 3000;
    while (Date.now() < deadline) {
      got = standins.requests(xcode);
      if (got.length > 0) break;
      // The meter shows nothing but its panel while the request is on its way.
      const windows = meterWindows(m);
      assert.strictEqual(windows.length, 1, `the meter shows ${windows.length} windows: ${windows.map((x) => x.title)}`);
      await procs.sleep(50);
    }
    // The app's own quit handler was reached by the standard quit request (the Apple event an
    // app's Quit answers), not by a signal and not by a kill.
    assert.deepStrictEqual(got.map((e) => `${e.kind} ${e.detail}`), ['QUIT aevt/quit'], `Xcode received ${JSON.stringify(got)}`);
    assert.ok(got[0].at - clickedAt <= 1000, `the request came ${got[0].at - clickedAt} ms after the click`);
    // No confirmation: the panel is the meter's one window, holding no question.
    const windows = meterWindows(m);
    assert.strictEqual(windows.length, 1, 'the meter shows only its panel');
    const words = windows[0].elements.map((e) => e.text).join(' ');
    assert.ok(!/sure|confirm|cancel|\?/i.test(words), `the panel reads: ${words}`);
  });

  reg.define(/^the user sees Xcode's button read "Ending…" until Xcode is gone$/, async (w) => {
    const xcode = required(w.xcode, 'xcode');
    const gone = await waitForSample(w, (s) => !s.running.Xcode, 8000, 'Xcode gone');
    const { samples } = w.timeline;
    const whileRunning = samples.filter((s) => s.at < gone.at && s.running.Xcode);
    assert.ok(whileRunning.length >= 5, `${whileRunning.length} readings while Xcode ran`);
    for (const s of whileRunning) {
      const row = s.rows.find((r) => r.name === 'Xcode');
      assert.ok(row, `Xcode is listed while it runs: ${sampleRows(s)}`);
      assert.strictEqual(row.button, ENDING, `${s.at - w.clickedAt} ms after the click: ${sampleRows(s)}`);
      assert.strictEqual(row.enabled, false, 'Ending… cannot be clicked');
    }
    assert.ok(!standins.isRunning(xcode), 'ps: Xcode is gone');
    assert.deepStrictEqual(xcode.owned.exit, { ...xcode.owned.exit, code: 0, signal: null }, 'Xcode quit by itself, not killed');
  });

  reg.define(/^once Xcode is gone the user sees its row leave the list and the next-highest CPU task move up into the five CPU rows$/, async (w) => {
    const m = required(w.meter, 'meter');
    const expected = ['busy1', 'busy2', 'busy3', 'busy4', 'busy5'];
    const capture = await tasks.waitForList(m.pid, (l) => l.rows.map((r) => r.name).join() === expected.join(), 3000,
      'the list without Xcode, busy5 moved up');
    const shown = tasks.list(capture);
    assert.strictEqual(shown.rows.length, 5, describeRows(shown));
    for (const row of shown.rows) {
      assert.deepStrictEqual(row.tags, [], `${row.name} is a CPU row`);
      assert.deepStrictEqual(row.buttons.map((b) => b.text), ['End'], `${row.name} has an ordinary End`);
    }
    for (const other of others(w, 'Xcode')) {
      assert.ok(standins.isRunning(other), `ps: ${other.name} still runs`);
      assert.deepStrictEqual(standins.requests(other), [], `${other.name} was asked nothing`);
    }
  });

  // --- Force Quit only after five seconds (D62, D64) ---

  reg.define(/^the user clicked End on a task$/, async (w) => {
    await clickEndOnTask(w);
  });

  reg.define(/^the task quits 2 seconds later$/, async (w) => {
    const task = required(w.task, 'task');
    await procs.sleep(Math.max(0, w.clickedAt + 2000 - Date.now()));
    // It was asked, and still runs until it quits now.
    assert.ok(standins.isRunning(task), 'ps: the task still runs 2 seconds after the click');
    assertAskedOnce(task, w.clickedAt);
    standins.letQuit(task);
    for (let i = 0; i < 40 && standins.isRunning(task); i++) await procs.sleep(25);
    assert.ok(!standins.isRunning(task), 'ps: the task has quit');
    assert.strictEqual(task.owned.exit.signal, null, 'it quit by itself');
  });

  reg.define(/^the task is still running 5 seconds later$/, async (w) => {
    const task = required(w.task, 'task');
    await procs.sleep(Math.max(0, w.clickedAt + 5000 - Date.now()));
    assert.ok(standins.isRunning(task), 'ps: the task still runs 5 seconds after the click');
    assertAskedOnce(task, w.clickedAt);
  });

  reg.define(/^the user sees its row leave the list, with no Force Quit ever$/, async (w) => {
    const task = required(w.task, 'task');
    const left = await waitForSample(w, (s) => s.at > task.owned.exit.at && !s.rows.some((r) => r.name === task.name),
      3000, 'the row gone');
    // Watched until well past five seconds after the click: no Force Quit on any row, ever.
    await procs.sleep(Math.max(0, w.clickedAt + 6500 - Date.now()));
    const { samples } = w.timeline;
    assert.ok(samples.length >= 20, `${samples.length} readings`);
    for (const s of samples) {
      assert.ok(!s.rows.some((r) => r.button === FORCE_QUIT), `${s.at - w.clickedAt} ms after the click: ${sampleRows(s)}`);
    }
    assert.ok(left.at - task.owned.exit.at <= 2500, `the row left ${left.at - task.owned.exit.at} ms after the task quit`);
    for (const s of samples.filter((x) => x.at >= left.at)) {
      assert.ok(!s.rows.some((r) => r.name === task.name), `the row stays gone: ${sampleRows(s)}`);
    }
  });

  reg.define(/^the user sees its button turn into "Force Quit"$/, async (w) => {
    const task = required(w.task, 'task');
    const first = await waitForSample(w, (s) => buttonOf(s, task.name) === FORCE_QUIT, 3000, 'Force Quit');
    const after = first.at - w.clickedAt;
    assert.ok(after >= 5000 && after <= 6250, `Force Quit showed ${after} ms after the click`);
    const before = w.timeline.samples.filter((s) => s.at < first.at);
    assert.ok(before.length >= 20, `${before.length} readings before it`);
    for (const s of before) {
      assert.strictEqual(buttonOf(s, task.name), ENDING, `${s.at - w.clickedAt} ms after the click: ${sampleRows(s)}`);
    }
    const row = first.rows.find((r) => r.name === task.name);
    assert.strictEqual(row.enabled, true, 'Force Quit can be clicked');
    assert.ok(first.running[task.name], 'ps: the task still ran when it showed');
  });

  // --- Force Quit ends the task outright (D62) ---

  reg.define(/^a task's button reads "Force Quit"$/, async (w) => {
    await clickEndOnTask(w);
    await waitForSample(w, (s) => buttonOf(s, 'standin') === FORCE_QUIT, 7000, 'Force Quit');
    assert.ok(standins.isRunning(w.task), 'ps: the task still runs');
    assertAskedOnce(w.task, w.clickedAt);
  });

  reg.define(/^the user clicks "Force Quit"$/, async (w) => {
    const m = required(w.meter, 'meter');
    w.forceQuitAt = await standins.clickButton(w, m.pid, required(w.task, 'task'), FORCE_QUIT);
  });

  reg.define(/^Activity Monitor no longer lists the task, which was ended at once without being asked$/, async (w) => {
    const task = required(w.task, 'task');
    const at = required(w.forceQuitAt, 'forceQuitAt');
    for (let i = 0; i < 60 && standins.isRunning(task); i++) await procs.sleep(25);
    assert.ok(!standins.isRunning(task), 'ps no longer lists the task');
    // Ended outright: macOS reports it killed, at once, and it was asked nothing more.
    assert.strictEqual(task.owned.exit.signal, 'SIGKILL', `it exited by ${JSON.stringify(task.owned.exit)}`);
    assert.ok(task.owned.exit.at - at <= 1000, `it ended ${task.owned.exit.at - at} ms after the click`);
    assertAskedOnce(task, w.clickedAt);
    assert.ok(standins.requests(task).every((e) => e.at < at), 'nothing was asked of it at Force Quit');
  });

  reg.define(/^the user sees its row leave the list$/, async (w) => {
    const m = required(w.meter, 'meter');
    const task = required(w.task, 'task');
    assert.ok(!standins.isRunning(task), 'ps: the task is gone');
    const capture = await tasks.waitForList(m.pid, (l) => !l.rows.some((r) => r.name === task.name), 3000, 'its row gone');
    const shown = tasks.list(capture);
    assert.deepStrictEqual(shown.rows.map((r) => r.name), ['busy1', 'busy2', 'busy3', 'busy4', 'quiet1'], describeRows(shown));
  });

  // --- Clicking Ending… again (D63) ---

  reg.define(/^the user clicked End on a task and its button reads "Ending…"$/, async (w) => {
    await clickEndOnTask(w);
    const shown = tasks.listNow(w.meter.pid);
    const row = tasks.rowsNamed(shown, 'standin')[0];
    assert.ok(row && row.buttons.map((b) => b.text).join() === ENDING, `the task's row: ${describeRows(shown)}`);
  });

  reg.define(/^the user clicks the button again before 5 seconds have passed$/, async (w) => {
    const m = required(w.meter, 'meter');
    await procs.sleep(Math.max(0, w.clickedAt + 1500 - Date.now()));
    w.secondClickAt = await standins.clickButton(w, m.pid, required(w.task, 'task'), ENDING);
    assert.ok(w.secondClickAt - w.clickedAt < 4000, `clicked again ${w.secondClickAt - w.clickedAt} ms after End`);
  });

  reg.define(/^nothing more happens to the task$/, async (w) => {
    const task = required(w.task, 'task');
    await procs.sleep(1000);
    assertAskedOnce(task, w.clickedAt);
    assert.ok(standins.isRunning(task), 'ps: the task still runs');
    assert.strictEqual(task.owned.exit, null, 'it has not exited');
  });

  reg.define(/^the user sees the button still read "Ending…" until it becomes "Force Quit" at 5 seconds$/, async (w) => {
    const task = required(w.task, 'task');
    const first = await waitForSample(w, (s) => buttonOf(s, task.name) === FORCE_QUIT, 6000, 'Force Quit');
    const after = first.at - w.clickedAt;
    assert.ok(after >= 5000 && after <= 6250, `Force Quit showed ${after} ms after the first click`);
    const since = w.timeline.samples.filter((s) => s.at >= w.secondClickAt && s.at < first.at);
    assert.ok(since.length >= 15, `${since.length} readings between the second click and Force Quit`);
    for (const s of since) {
      assert.strictEqual(buttonOf(s, task.name), ENDING, `${s.at - w.clickedAt} ms after End: ${sampleRows(s)}`);
    }
    assertAskedOnce(task, w.clickedAt);
  });

  // --- A task that exits while showing Force Quit (D40) ---

  reg.define(/^the task exits by itself before the user clicks it$/, async (w) => {
    const task = required(w.task, 'task');
    standins.letQuit(task);
    for (let i = 0; i < 40 && standins.isRunning(task); i++) await procs.sleep(25);
    assert.ok(!standins.isRunning(task), 'ps: the task has exited');
    assert.deepStrictEqual([task.owned.exit.code, task.owned.exit.signal], [0, null], 'it exited by itself');
  });

  reg.define(/^no other task is ended$/, async (w) => {
    const m = required(w.meter, 'meter');
    // A while longer, then every other task: still running as started, asked nothing.
    await procs.sleep(1500);
    for (const other of others(w, 'standin')) {
      assert.ok(standins.isRunning(other), `ps: ${other.name} still runs`);
      assert.deepStrictEqual(standins.requests(other), [], `${other.name} was asked nothing`);
    }
    // And none is left one click from it: each other row offers its ordinary End.
    const shown = tasks.listNow(m.pid);
    for (const row of shown.rows) {
      assert.deepStrictEqual(row.buttons.map((b) => [b.text, b.enabled]), [['End', true]], describeRows(shown));
    }
  });

  // --- The ending state follows its task (D105) ---

  reg.define(/^the user clicked End on Xcode in the second row and moved the pointer away$/, async (w) => {
    const m = await setUp(w, [['busy1', 30], ['Xcode', 25, { app: true }], ['busy2', 20], ['busy3', 15], ['busy4', 10]]);
    w.xcode = w.standIns.get('Xcode');
    const shown = tasks.listNow(m.pid);
    assert.strictEqual(shown.rows[1].name, 'Xcode', `Xcode is second: ${describeRows(shown)}`);
    w.clickedAt = await standins.clickButton(w, m.pid, w.xcode, 'End');
    // Off the button, onto the list's heading.
    const heading = standins.centre(shown.heading);
    standins.movePointer(w, heading.x, heading.y);
    await procs.sleep(300);
    const got = standins.requests(w.xcode);
    assert.deepStrictEqual(got.map((e) => e.kind), ['QUIT'], `Xcode was asked to quit: ${JSON.stringify(got)}`);
  });

  reg.define(/^Xcode drops to the fourth row at the next refresh$/, async (w) => {
    const m = required(w.meter, 'meter');
    // Between busy3 (15%) and busy4 (10%).
    w.cpu.set('Xcode', 12);
    w.feed.set({ tasks: taskFeed(w) });
    w.capture = await tasks.waitForList(m.pid, (l) => l.rows[3] && l.rows[3].name === 'Xcode', 3000, 'Xcode in the fourth row');
    assert.ok(Date.now() - w.clickedAt < 5000, 'still within five seconds of the click');
  });

  reg.define(/^the user sees "Ending…" on Xcode's row in the fourth row$/, (w) => {
    const shown = tasks.list(required(w.capture, 'capture'));
    assert.strictEqual(shown.rows[3].name, 'Xcode', describeRows(shown));
    assert.deepStrictEqual(shown.rows[3].buttons.map((b) => b.text), [ENDING], describeRows(shown));
    assert.ok(standins.isRunning(w.xcode), 'ps: Xcode still runs');
  });

  reg.define(/^the user sees an ordinary End button on the task now in the second row$/, (w) => {
    const shown = tasks.list(required(w.capture, 'capture'));
    const second = shown.rows[1];
    assert.strictEqual(second.name, 'busy2', describeRows(shown));
    assert.deepStrictEqual(second.buttons.map((b) => [b.text, b.enabled]), [['End', true]], describeRows(shown));
    assert.deepStrictEqual(standins.requests(w.standIns.get('busy2')), [], 'busy2 was asked nothing');
  });
};
