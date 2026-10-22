'use strict';
// The meter as installed, against the real system (launchd, ps, the menu bar): behaviour that
// presence.feature does not state but the visionary ruled or the review found. Uses the same
// harness install as the presence scenarios (the real installer, ~/Applications, an identifier
// of its own) and takes everything back afterwards. Signals go only to the meter this test
// installed, checked by pid and start time.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');
const presence = require('./support/presence');
const procs = require('./support/procs');

const NEWER = '0.0.2';

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

test('a terminate request is a quit: the meter stays away; a crash still brings it back; the next login starts it',
  { timeout: 400000 }, async () => {
    await withWorld(async (world) => {
      await presence.install(world, NEWER);
      const m = await presence.running();
      const runs = presence.job().runs;
      // Activity Monitor's Quit and `kill` send SIGTERM.
      presence.signal(m, 'SIGTERM');
      await presence.until(() => presence.proc(m.pid) === null, 5000, 'the meter to end');
      const end = Date.now() + 15000;
      while (Date.now() < end) {
        assert.deepStrictEqual(presence.meterPids(), [], 'no meter comes back after a terminate request');
        await procs.sleep(500);
      }
      const job = presence.job();
      assert.strictEqual(job.pid, null, 'launchd is not running it');
      assert.strictEqual(job.runs, runs, 'launchd never started it again');
      assert.strictEqual(job.lastExit, '0', 'it ended as a quit, not a crash');

      // Log-out and shutdown also send SIGTERM; the next login still starts it (D42).
      presence.logOut();
      presence.logInLoad();
      const back = await presence.running(15000);
      assert.notStrictEqual(back.pid, m.pid);
      assert.strictEqual(back.ppid, 1, 'launchd started it');

      // A crash is still relaunched (D77).
      const crashed = Date.now();
      presence.signal(back, 'SIGSEGV');
      const again = await presence.running(10000, back.pid);
      assert.ok(Date.now() - crashed <= 10000, 'back within ten seconds');
      assert.notStrictEqual(again.pid, back.pid);
    });
  });

test('opening the installed copy takes the job back from another copy of the same version',
  { timeout: 400000 }, async () => {
    await withWorld(async (world) => {
      await presence.install(world, NEWER);
      const first = await presence.running();
      // Another copy of the same version, opened while the job is off (as after a Login Items
      // switch), takes the job over: it names the copy.
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-samever-'));
      const copy = path.join(dir, 'Meter.app');
      const copyProgram = path.join(copy, 'Contents', 'MacOS', 'Meter');
      execFileSync('ditto', [presence.APP, copy]);
      world.defer(() => fs.rmSync(dir, { recursive: true, force: true }));
      presence.logOut();
      await presence.until(() => presence.proc(first.pid) === null, 10000, 'the first meter to end');
      spawnSync('/usr/bin/open', ['-n', copy]);
      await presence.until(() => presence.job().program === copyProgram && presence.job().pid, 15000,
        'the job to run the other copy');
      // The installed copy is opened (what the postinstall does): the job comes back to it.
      spawnSync('/usr/bin/open', ['-n', presence.APP]);
      await presence.until(() => {
        const j = presence.job();
        return j.program === presence.PROGRAM && j.pid && (presence.proc(j.pid) || {}).program === presence.PROGRAM;
      }, 15000, 'the job to run the installed copy again');
      assert.strictEqual(presence.agentPlist().ProgramArguments[0], presence.PROGRAM, 'the LaunchAgent names the installed copy');
      // The other copy goes (a rebuild's rm -rf); the next login still starts the meter.
      presence.logOut();
      await presence.until(() => presence.meterPids().length === 0, 10000, 'the meter to end');
      fs.rmSync(dir, { recursive: true, force: true });
      presence.logInLoad();
      const back = await presence.running(15000);
      assert.strictEqual(back.ppid, 1);
      assert.notStrictEqual(presence.job().lastExit, '78: EX_CONFIG');
    });
  });
