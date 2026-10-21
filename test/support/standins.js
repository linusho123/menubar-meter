'use strict';
// Stand-ins: the only tasks a test may ever end. Each is a process the harness itself starts,
// known by its pid AND its start time, running a program file no other process runs (a copy of
// the stand-in program under its own name in a folder of its own, or the stand-in app named
// Xcode the build makes; never the real Xcode). Each records what it receives in a file the
// harness reads: the app's quit request, the terminate signal; the kill shows as the signal its
// exit reports. Before any click on End or Force Quit the harness checks that the row it is about
// to click is its own stand-in, by the name the row reads through Accessibility, and that the
// task under that name is the one it started: same pid, same start time, same program file, and
// the only process of that name on the Mac. The pointer is rested on the button, the row read
// again under it (a row under the pointer's End button holds, D100) and checked again, and only
// then is the button clicked where the pointer already is. Anything else is refused.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const paths = require('./paths');
const procs = require('./procs');
const tasks = require('./tasks');

const program = path.join(paths.root, '.build', 'release', 'meter-standin');
const xcodeApp = path.join(paths.root, 'build', 'test', 'standins', 'Xcode.app', 'Contents', 'MacOS', 'Xcode');

const ax = (args) => execFileSync(paths.meterAx, args, { encoding: 'utf8' });

/** What a stand-in has recorded receiving: [{ kind: READY|QUIT|TERM, at, detail }]. */
function received(standIn) {
  let text = '';
  try {
    text = fs.readFileSync(standIn.record, 'utf8');
  } catch {
    return [];
  }
  return text.split('\n').filter(Boolean).map((line) => {
    const [kind, at, detail] = line.split(' ');
    return { kind, at: Number(at), detail };
  });
}

/** The requests it has received: quit requests and terminate signals, in order. */
const requests = (standIn) => received(standIn).filter((e) => e.kind !== 'READY');

/**
 * Starts a stand-in named `name`: the app named Xcode when `app`, else a windowless task.
 * `quitAfterMs`: once asked, it quits that long after; without it, only when the harness lets
 * it (`letQuit`). It never quits unasked.
 */
async function start(world, name, { app = false, busy = 0, quitAfterMs } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-standin-'));
  const record = path.join(dir, 'record');
  const control = path.join(dir, 'control');
  let file;
  if (app) {
    if (name !== 'Xcode') throw new Error('the stand-in app is named Xcode');
    file = xcodeApp;
  } else {
    file = path.join(dir, name);
    fs.copyFileSync(program, file);
    fs.chmodSync(file, 0o755);
  }
  const args = [record, control, String(busy)];
  if (quitAfterMs !== undefined) args.push(String(quitAfterMs));
  const owned = procs.start(file, args);
  owned.exit = null;
  owned.child.on('exit', (code, signal) => { owned.exit = { code, signal, at: Date.now() }; });
  const standIn = { name, file, dir, record, control, owned, pid: owned.pid, app };
  world.defer(async () => {
    // Let it quit, then ask it (it ignores nothing once let): only ever the harness's own.
    fs.writeFileSync(control, 'exit');
    await procs.end(owned);
    fs.rmSync(dir, { recursive: true, force: true });
  });
  const deadline = Date.now() + 10000;
  while (!received(standIn).some((e) => e.kind === 'READY')) {
    if (Date.now() > deadline || owned.exited) throw new Error(`the stand-in ${name} never got ready`);
    await procs.sleep(50);
  }
  return standIn;
}

/** Lets a stand-in that has been asked to quit finish quitting now. */
function letQuit(standIn) {
  fs.writeFileSync(standIn.control, 'exit');
}

const isRunning = (standIn) => procs.isRunning(standIn.owned);

/** The pids of every process on the Mac whose name is exactly `name`. */
function pidsNamed(name) {
  try {
    return execFileSync('pgrep', ['-x', name], { encoding: 'utf8' }).trim().split('\n').filter(Boolean).map(Number);
  } catch {
    return [];
  }
}

/**
 * Throws unless the row the user sees named `row.name` is this stand-in's: the name is the
 * stand-in's, the process the harness started still runs with the same pid and start time and
 * the same program file, and it is the only process of that name on the Mac.
 */
function assertOwn(standIn, row) {
  const refuse = (why) => { throw new Error(`refusing to click: ${why}`); };
  if (!row || row.name !== standIn.name) refuse(`the row reads "${row && row.name}", not the stand-in ${standIn.name}`);
  if (!isRunning(standIn)) refuse(`the stand-in ${standIn.name} (pid ${standIn.pid}) no longer runs as started`);
  const comm = execFileSync('ps', ['-o', 'comm=', '-p', String(standIn.pid)], { encoding: 'utf8' }).trim();
  if (comm !== standIn.file) refuse(`pid ${standIn.pid} runs ${comm}, not ${standIn.file}`);
  const named = pidsNamed(standIn.name);
  if (named.length !== 1 || named[0] !== standIn.pid) refuse(`processes named ${standIn.name}: ${named}`);
}

/** The row under the pointer's height, and the pointer. */
function rowUnderPointer(meterPid) {
  const shown = tasks.listNow(meterPid);
  const pointer = JSON.parse(ax(['pointer']));
  const under = shown.rows.filter((r) => pointer.y >= r.box.y && pointer.y <= r.box.y + r.box.height);
  return { shown, pointer, row: under.length === 1 ? under[0] : null };
}

const centre = (box) => ({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
const inside = (point, box) => point.x >= box.x && point.x <= box.x + box.width
  && point.y >= box.y && point.y <= box.y + box.height;

/** Moves the pointer as the mouse does; the scenario puts it back where it was. */
function movePointer(world, x, y) {
  if (!world.pointerWas) {
    world.pointerWas = JSON.parse(ax(['pointer']));
    world.defer(() => ax(['move', String(world.pointerWas.x), String(world.pointerWas.y)]));
  }
  ax(['move', String(x), String(y)]);
}

/**
 * Clicks the button reading `title` on the stand-in's row, as the user does: the pointer rests
 * on it, then the mouse button goes down and up. Checked before the pointer moves and again
 * under the pointer just before the click. Returns the moment just before the click.
 */
async function clickButton(world, meterPid, standIn, title) {
  const before = tasks.rowsNamed(tasks.listNow(meterPid), standIn.name);
  if (before.length !== 1) throw new Error(`refusing to click: ${before.length} rows read ${standIn.name}`);
  assertOwn(standIn, before[0]);
  const button = before[0].buttons.find((b) => b.text === title);
  if (!button) throw new Error(`${standIn.name}'s row has no "${title}" button: ${before[0].buttons.map((b) => b.text)}`);
  const at = centre(button);
  movePointer(world, at.x, at.y);
  // The row under the End button holds within a quarter second (D100).
  await procs.sleep(400);
  const { row, pointer } = rowUnderPointer(meterPid);
  assertOwn(standIn, row);
  const under = row.buttons.find((b) => inside(pointer, b));
  if (!under || under.text !== title) throw new Error(`refusing to click: the pointer is on ${under ? `"${under.text}"` : 'no button'}, not "${title}"`);
  const clickedAt = Date.now();
  ax(['click', String(pointer.x), String(pointer.y)]);
  return clickedAt;
}

/**
 * Samples what the user sees and what runs, from now until stopped: every row's name and
 * button, read through Accessibility, and whether each stand-in still runs (`ps`).
 */
function timeline(world, meterPid, standIns) {
  const samples = [];
  let stopped = false;
  const loop = (async () => {
    while (!stopped) {
      try {
        const shown = tasks.listNow(meterPid);
        samples.push({
          at: Date.now(),
          rows: shown.rows.map((r) => ({
            name: r.name, button: r.buttons[0] ? r.buttons[0].text : null, enabled: r.buttons[0] ? r.buttons[0].enabled : null,
          })),
          running: Object.fromEntries(standIns.map((s) => [s.name, isRunning(s)])),
        });
      } catch {
        // A read that failed is no sample.
      }
      await procs.sleep(80);
    }
  })();
  const stop = async () => { stopped = true; await loop; };
  world.defer(stop);
  return { samples, stop };
}

module.exports = {
  start, letQuit, received, requests, isRunning, assertOwn, rowUnderPointer, clickButton, movePointer, timeline, centre, inside,
};
