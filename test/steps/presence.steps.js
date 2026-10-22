'use strict';
// presence.feature. The meter is installed by the real installer from the harness's package
// into the user's own Applications folder (support/presence.js), so launchd's own job starts it,
// relaunches it, and keeps it down after Quit Meter. Every Then reads what macOS shows or knows:
// the menu bar and the panel through Accessibility, `ps`, launchd's job, the login-item registry
// (`sfltool dumpbtm`) and the panel's pixels. The login steps are bound, as the visionary ruled
// (Q1, 2026-10-21), to the registry listing the job as enabled, with launchd then loading the
// LaunchAgent as it does at login; one real log-in is checked by hand (docs/P6-LOGIN-CHECK.md).
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const paths = require('../support/paths');
const presence = require('../support/presence');
const procs = require('../support/procs');
const menubar = require('../support/menubar');
const panel = require('../support/panel');
const meter = require('../support/meter');

const NEWER = '0.0.2';
const OLDER = '0.0.1';
const frontApp = path.join(paths.root, 'build', 'test', 'standins', 'Front.app', 'Contents', 'MacOS', 'Front');

const required = (value, what) => {
  if (value === undefined || value === null) throw new Error(`world.${what} read before any step set it`);
  return value;
};

const ax = (args) => JSON.parse(execFileSync(paths.meterAx, args, { encoding: 'utf8' }));
const windowsOf = (pid) => ax(['windows', String(pid)]);
const pressKey = (code, modifiers) => {
  const using = modifiers.length ? ` using {${modifiers.map((m) => `${m} down`).join(', ')}}` : '';
  execFileSync('osascript', ['-e', `tell application "System Events" to key code ${code}${using}`]);
};
const CONTROL_OPTION_COMMAND_M = () => pressKey(46, ['control', 'option', 'command']);
const ESC = () => pressKey(53, []);

/** Waits for the panel of `pid` to be open (true) or closed (false); returns its windows. */
async function panelBecomes(pid, open, ms) {
  return presence.until(() => {
    const w = windowsOf(pid);
    return (open ? w.length === 1 : w.length === 0) ? w : null;
  }, ms, `the panel to ${open ? 'open' : 'close'}`);
}

/** Clicks Quit Meter, the panel's last row, through Accessibility. */
function clickQuit(pid) {
  const [window] = windowsOf(pid);
  const lowest = window.elements.reduce((a, b) => (b.y > a.y ? b : a));
  assert.strictEqual(lowest.text, 'Quit Meter', 'Quit Meter is the panel\'s last row');
  assert.strictEqual(lowest.role, 'AXButton');
  try {
    execFileSync(paths.meterAx, ['press-button', String(pid), 'Quit Meter'], { stdio: 'pipe' });
  } catch (e) {
    // The meter is gone before the press returns: Accessibility reports it could not complete.
    if (!/AXPress failed \(-25204\)/.test(String(e.stderr))) throw e;
  }
}

/** The registry lists the job, enabled, for the installed program; the LaunchAgent starts it at load. */
function assertStartsAtLogin() {
  const record = presence.registryRecord();
  assert.ok(record, `the login-item registry lists ${presence.AGENT}`);
  assert.ok(presence.enabled(record), `the registry has it enabled: ${record.disposition}`);
  assert.strictEqual(record.executable, presence.PROGRAM, 'the registry names the installed program');
  const plist = presence.agentPlist();
  assert.strictEqual(plist.RunAtLoad, true, 'launchd starts it when it loads it at login');
  assert.strictEqual(plist.ProgramArguments[0], presence.PROGRAM);
  assert.ok(fs.existsSync(presence.PROGRAM), 'the program it names is installed');
}

/** Logs out and in as far as launchd goes: the job unloaded, then loaded from the LaunchAgent. */
async function nextLogin(w) {
  assertStartsAtLogin();
  presence.logOut();
  await presence.until(() => presence.meterPids().length === 0, 10000, 'the meter to end at log-out');
  const before = Date.now();
  presence.logInLoad();
  const m = await presence.running(15000);
  w.loginMeter = m;
  // Started by launchd, not by the harness or the user.
  assert.strictEqual(m.ppid, 1, 'launchd started it');
  return { m, before };
}

module.exports = (reg) => {
  // --- D42 ---------------------------------------------------------------------------------------

  reg.define(/^the user has not opened the meter themselves$/, async (w) => {
    // Installed by the one install step (the installer opens it, not the user), then logged out.
    presence.install(w, NEWER);
    await presence.running();
    presence.logOut();
    await presence.until(() => presence.meterPids().length === 0, 10000, 'the meter to end at log-out');
    assert.deepStrictEqual(presence.meterItems(), [], 'no meter in the menu bar before the login');
  });

  reg.define(/^the user logs in to the Mac after a restart$/, async (w) => {
    // Q1: the registry lists the job as enabled, and launchd loads the LaunchAgent as at login.
    assertStartsAtLogin();
    presence.logInLoad();
    w.meter = await presence.running(15000);
  });

  reg.define(/^the user sees the meter's item in the menu bar$/, async (w) => {
    const m = required(w.meter, 'meter');
    const items = menubar.itemsOf(m.pid);
    assert.strictEqual(items.length, 1, 'one item in the menu bar');
    assert.match(items[0].title, /^CPU .+%  GPU .+%  RAM .+%  .+°C$/u);
    assert.strictEqual(m.ppid, 1, 'launchd started it, not the user');
    assert.deepStrictEqual(presence.meterPids(), [m.pid], 'one meter runs');
  });

  // --- D65 and D104 ------------------------------------------------------------------------------

  reg.define(/^the meter is in the menu bar and its panel is open$/, async (w) => {
    presence.install(w, NEWER);
    w.meter = await presence.running();
    await panel.click(w.meter.pid);
  });

  reg.define(/^the user clicks "Quit Meter", the last row of the panel$/, async (w) => {
    const m = required(w.meter, 'meter');
    w.runsBefore = presence.job().runs;
    clickQuit(m.pid);
    w.quitAt = Date.now();
  });

  reg.define(/^the user sees the meter leave the menu bar at once$/, async (w) => {
    const m = required(w.meter, 'meter');
    await presence.until(() => menubar.itemsOf(m.pid).length === 0 && presence.proc(m.pid) === null,
      1000, 'the item and the meter to be gone within a second');
    assert.deepStrictEqual(presence.meterItems(), [], 'no meter item in the menu bar');
  });

  reg.define(/^the user clicked "Quit Meter"$/, async (w) => {
    presence.install(w, NEWER);
    w.meter = await presence.running();
    await panel.click(w.meter.pid);
    w.runsBefore = presence.job().runs;
    clickQuit(w.meter.pid);
    w.quitAt = Date.now();
    await presence.until(() => presence.proc(w.meter.pid) === null, 2000, 'the meter to quit');
  });

  reg.define(/^(\d+) seconds pass$/, async (w, seconds) => {
    const quitAt = required(w.quitAt, 'quitAt');
    const end = quitAt + Number(seconds) * 1000;
    // Watched all the while: no meter comes back at any moment.
    while (Date.now() < end) {
      assert.deepStrictEqual(presence.meterPids(), [], `no meter runs ${Math.round((Date.now() - quitAt) / 1000)} s after Quit`);
      await procs.sleep(500);
    }
  });

  reg.define(/^the user sees no meter in the menu bar$/, async (w) => {
    assert.deepStrictEqual(presence.meterItems(), []);
    assert.deepStrictEqual(presence.meterPids(), [], 'ps shows no meter');
    const job = presence.job();
    assert.strictEqual(job.pid, null, 'launchd is not running it');
    assert.strictEqual(job.runs, required(w.runsBefore, 'runsBefore'), 'launchd never started it again');
    assert.strictEqual(job.lastExit, '0', 'it ended as a quit, not a crash');
  });

  reg.define(/^at the user's next login the user sees the meter in the menu bar again$/, async (w) => {
    const { m } = await nextLogin(w);
    assert.strictEqual(menubar.itemsOf(m.pid).length, 1);
    assert.deepStrictEqual(presence.meterPids(), [m.pid], 'one meter runs');
  });

  // --- D77 -------------------------------------------------------------------------------------

  reg.define(/^the meter is running with its panel (closed|open)$/, async (w, state) => {
    presence.install(w, NEWER);
    w.meter = await presence.running();
    // Long enough for the graph to hold a history worth losing.
    await procs.sleep(20000);
    if (state === 'open') await panel.click(w.meter.pid);
    assert.strictEqual(windowsOf(w.meter.pid).length, state === 'open' ? 1 : 0);
  });

  reg.define(/^the meter crashes and vanishes from the menu bar$/, async (w) => {
    const m = required(w.meter, 'meter');
    w.crashAt = Date.now();
    presence.signal(m, 'SIGSEGV');
    await presence.until(() => menubar.itemsOf(m.pid).length === 0, 5000, 'the crashed meter to vanish');
  });

  reg.define(/^within (\d+) seconds the user sees the meter back in the menu bar, without doing anything$/, async (w, seconds) => {
    const m = required(w.meter, 'meter');
    const crashAt = required(w.crashAt, 'crashAt');
    const back = await presence.running(Number(seconds) * 1000 - (Date.now() - crashAt), m.pid);
    w.backAt = Date.now();
    assert.ok(w.backAt - crashAt <= Number(seconds) * 1000, `back after ${w.backAt - crashAt} ms`);
    assert.strictEqual(back.ppid, 1, 'launchd started it again');
    assert.deepStrictEqual(presence.meterPids(), [back.pid], 'one meter runs');
    w.meter = back;
  });

  reg.define(/^its graph shows no history from before the crash$/, async (w) => {
    const m = required(w.meter, 'meter');
    const crashAt = required(w.crashAt, 'crashAt');
    const capture = await panel.clickAndCapture(m.pid);
    const pixels = panel.linePixels(capture).filter((p) => p.line !== null);
    assert.ok(pixels.length > 0, 'the graph draws the new readings');
    const oldest = Math.min(...pixels.map((p) => p.x));
    // No sample older than the crash: on the five-minute axis nothing lies further left than
    // the time since the crash (plus a pixel or two of line width).
    const sinceCrash = (capture.at - crashAt) / 1000;
    const limit = 1 - sinceCrash / 300 - 0.01;
    assert.ok(oldest >= limit, `the graph's oldest point is at ${oldest.toFixed(3)} of the axis; nothing from before the crash lies left of ${limit.toFixed(3)} (${sinceCrash.toFixed(1)} s ago)`);
  });

  // --- D98 -------------------------------------------------------------------------------------

  reg.define(/^the panel is closed and Safari is in front$/, async (w) => {
    await meter.launchReal(w);
    await panel.click(w.meter.pid);
    await panel.panelWindow(w.meter.pid);
    // The geometry a click gives, to compare the shortcut's with.
    w.clickedFrame = windowsOf(w.meter.pid)[0];
    w.item = menubar.itemsOf(w.meter.pid)[0];
    await panel.click(w.meter.pid).catch(() => {});
    await panelBecomes(w.meter.pid, false, 2000);
    await frontStandIn(w);
  });

  reg.define(/^the user presses Control-Option-Command-M$/, async (w) => {
    required(w.meter, 'meter');
    CONTROL_OPTION_COMMAND_M();
  });

  reg.define(/^the user sees the meter's panel open, as if the menu bar item had been clicked$/, async (w) => {
    const m = required(w.meter, 'meter');
    const [opened] = await panelBecomes(m.pid, true, 1000);
    const clicked = required(w.clickedFrame, 'clickedFrame');
    for (const k of ['x', 'y', 'width', 'height']) assert.strictEqual(opened[k], clicked[k], `the panel's ${k} as a click puts it`);
    assert.deepStrictEqual(opened.elements.map((e) => e.text).slice(-2), ['Open Activity Monitor…', 'Quit Meter']);
  });

  reg.define(/^when the user presses Control-Option-Command-M again, the user sees the panel close$/, async (w) => {
    const m = required(w.meter, 'meter');
    CONTROL_OPTION_COMMAND_M();
    await panelBecomes(m.pid, false, 1000);
  });

  reg.define(/^the user opened the panel with Control-Option-Command-M$/, async (w) => {
    await meter.launchReal(w);
    await frontStandIn(w);
    CONTROL_OPTION_COMMAND_M();
    await panelBecomes(w.meter.pid, true, 1000);
  });

  reg.define(/^the user presses Esc$/, async (w) => {
    required(w.meter, 'meter');
    ESC();
  });

  reg.define(/^the user sees the panel close$/, async (w) => {
    const m = required(w.meter, 'meter');
    await panelBecomes(m.pid, false, 1000);
    assert.strictEqual(menubar.itemsOf(m.pid).length, 1, 'the meter is still in the menu bar');
  });

  // --- D83 and D84 -----------------------------------------------------------------------------

  reg.define(/^the meter is not on this Mac$/, async () => {
    assert.strictEqual(presence.installedId(), null, `${presence.APP} is not there`);
    assert.ok(!fs.existsSync(presence.AGENT), 'no LaunchAgent');
    assert.strictEqual(presence.job().loaded, false, 'launchd holds no job');
    assert.deepStrictEqual(presence.meterPids(), []);
  });

  reg.define(/^the user does the one install step$/, async (w) => {
    w.install = presence.install(w, NEWER);
  });

  reg.define(/^the user sees the meter's item in the menu bar right away, with no settings to fill in$/, async (w) => {
    const install = required(w.install, 'install');
    const m = await presence.running(5000);
    assert.ok(Date.now() - install.endedAt <= 5000, 'in the menu bar within five seconds of the installer finishing');
    assert.deepStrictEqual(windowsOf(m.pid), [], 'no window to fill in: only the item');
    assert.deepStrictEqual(presence.meterPids(), [m.pid], 'one meter runs');
    w.meter = m;
  });

  reg.define(/^an older version of the meter is installed and starts at login$/, async (w) => {
    presence.install(w, OLDER);
    w.oldMeter = await presence.running();
    assert.strictEqual(presence.installedVersion(), OLDER);
    assertStartsAtLogin();
  });

  reg.define(/^the user does the one install step with a newer version$/, async (w) => {
    w.install = presence.install(w, NEWER);
  });

  reg.define(/^the user sees the newer version in the menu bar$/, async (w) => {
    const old = required(w.oldMeter, 'oldMeter');
    const install = required(w.install, 'install');
    const m = await presence.running(10000, old.pid);
    assert.strictEqual(presence.proc(old.pid), null, 'the older meter has gone');
    assert.strictEqual(presence.installedVersion(), NEWER, 'the installed copy is the newer version');
    // It started after the newer copy was put in place, from that copy's program.
    const started = new Date(m.started).getTime();
    assert.ok(started >= Math.floor(install.startedAt / 1000) * 1000, `started ${m.started}, after the install began`);
    assert.deepStrictEqual(presence.meterPids(), [m.pid], 'one meter runs');
    assert.deepStrictEqual(presence.meterItems().map((i) => i.pid), [m.pid], 'one meter item');
    assert.deepStrictEqual(copiesInApplications(), ['Meter.app'], 'one copy installed');
    w.meter = m;
  });

  reg.define(/^at the user's next login the user sees the newer version start$/, async (w) => {
    const { m, before } = await nextLogin(w);
    assert.strictEqual(presence.installedVersion(), NEWER);
    assert.ok(new Date(m.started).getTime() >= Math.floor(before / 1000) * 1000);
    w.meter = m;
  });

  reg.define(/^the meter never shows an offer to update itself$/, async (w) => {
    const m = required(w.meter, 'meter');
    assert.deepStrictEqual(windowsOf(m.pid), [], 'no window of its own');
    await panel.click(m.pid);
    const texts = panel.textsNow(m.pid).filter((t) => typeof t === 'string');
    const offers = texts.filter((t) => /update|upgrade|new version|download|install/i.test(t));
    assert.deepStrictEqual(offers, [], 'nothing in the panel offers an update');
    // It never asks anyone whether there is one: no network connection of its own.
    const sockets = spawnLsof(m.pid);
    assert.deepStrictEqual(sockets, [], 'the meter holds no network connection');
  });
};

/** The copies of the meter in ~/Applications (Meter.app, Meter 2.app…). */
function copiesInApplications() {
  return fs.readdirSync(path.dirname(presence.APP)).filter((n) => /^Meter( \d+)?\.app$/.test(n));
}

/** The meter's open internet sockets, as `lsof` reads them. */
function spawnLsof(pid) {
  const { spawnSync } = require('node:child_process');
  const r = spawnSync('/usr/sbin/lsof', ['-nP', '-a', '-i', '-p', String(pid), '-F', 'n'], { encoding: 'utf8' });
  return r.stdout.split('\n').filter((l) => l.startsWith('n'));
}

/** Starts the front-app stand-in (a regular app the harness owns) and brings it to the front. */
async function frontStandIn(w) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-front-'));
  const control = path.join(dir, 'control');
  const front = procs.start(frontApp, [path.join(dir, 'record'), control, '0']);
  w.defer(async () => {
    fs.writeFileSync(control, 'exit');
    await procs.end(front);
    fs.rmSync(dir, { recursive: true, force: true });
  });
  await presence.until(() => {
    try {
      execFileSync('osascript', ['-e',
        `tell application "System Events" to set frontmost of (first process whose unix id is ${front.pid}) to true`],
      { stdio: 'pipe' });
    } catch {
      return false; // not yet known to System Events
    }
    return ax(['front']).pid === front.pid;
  }, 10000, 'the stand-in app in front');
  w.front = front;
}
