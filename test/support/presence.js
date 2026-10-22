'use strict';
// The meter as installed: the real installer (`installer`) puts the harness's package in the
// user's own Applications folder (~/Applications, never /Applications), under an identifier of
// its own (never the installed meter's), and its postinstall opens it, which loads its login
// job. What the tests read is what macOS itself knows: launchd's job (`launchctl print`), the
// login-item registry (`sfltool dumpbtm`, through the one sudoers rule that allows it), `ps`,
// and the menu bar and panel through Accessibility. Every test takes back what it installed:
// the job, its LaunchAgent, the app, the package receipt, then checks the registry's record, if
// any, names no existing file (the record itself clears by itself, about 70 s after the
// LaunchAgent is gone, so an install waits for the previous one's record to clear first).
// Signals go only to a meter process this install started, checked
// by pid, start time and program before each one.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');
const paths = require('./paths');
const procs = require('./procs');
const menubar = require('./menubar');

const LABEL = 'local.menubar-meter.Meter.presencetest';
const HOME = os.homedir();
const APP = path.join(HOME, 'Applications', 'Meter.app');
const PROGRAM = path.join(APP, 'Contents', 'MacOS', 'Meter');
const AGENT = path.join(HOME, 'Library', 'LaunchAgents', `${LABEL}.plist`);
const DOMAIN = `gui/${process.getuid()}`;
const JOB = `${DOMAIN}/${LABEL}`;
const STATE = path.join(os.tmpdir(), LABEL);
const LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister';

/** How long the registry may take to drop the record of a removed LaunchAgent (measured: ~70 s). */
const REGISTRY_CLEAR_MS = 120000;

const pkg = (version) => path.join(paths.root, 'build', 'test', 'pkg', `Meter-${version}.pkg`);

const run = (file, args) => spawnSync(file, args, { encoding: 'utf8' });

/** The identifier of the app at ~/Applications/Meter.app, or null when there is none. */
function installedId() {
  if (!fs.existsSync(APP)) return null;
  return execFileSync('plutil', ['-extract', 'CFBundleIdentifier', 'raw', path.join(APP, 'Contents', 'Info.plist')],
    { encoding: 'utf8' }).trim();
}

/** The version of the installed copy, as its bundle says. */
function installedVersion() {
  return execFileSync('plutil', ['-extract', 'CFBundleShortVersionString', 'raw',
    path.join(APP, 'Contents', 'Info.plist')], { encoding: 'utf8' }).trim();
}

/** Refuses to go on when ~/Applications/Meter.app is some other app than the harness's own. */
function assertOurs() {
  const id = installedId();
  if (id !== null && id !== LABEL) throw new Error(`${APP} is ${id}, not the harness's own; refusing to touch it`);
}

/** launchd's job: { loaded, pid, runs, lastExit, program } (pid null when not running). */
function job() {
  const r = run('/bin/launchctl', ['print', JOB]);
  if (r.status !== 0) return { loaded: false, pid: null, runs: 0, lastExit: null, program: null };
  const field = (name) => {
    const m = new RegExp(`^\\t${name} = (.+)$`, 'm').exec(r.stdout);
    return m ? m[1] : null;
  };
  const pid = field('pid');
  return { loaded: true, pid: pid ? Number(pid) : null, runs: Number(field('runs') || 0), lastExit: field('last exit code'),
    program: field('program') };
}

/** What `ps` shows for a process: { ppid, started, program }, or null when it is gone. */
function proc(pid) {
  const r = run('/bin/ps', ['-o', 'ppid=', '-o', 'lstart=', '-o', 'comm=', '-p', String(pid)]);
  const m = /^\s*(\d+)\s+(\w{3} \w{3}\s+\d+ [\d:]+ \d{4})\s+(.+)$/.exec(r.stdout.trim());
  return m ? { ppid: Number(m[1]), started: m[2], program: m[3] } : null;
}

/** Every running process whose program is the installed meter's. */
function meterPids() {
  const r = run('/bin/ps', ['-axo', 'pid=,comm=']);
  return r.stdout.split('\n').map((l) => /^\s*(\d+)\s+(.+)$/.exec(l)).filter((m) => m && m[2] === PROGRAM)
    .map((m) => Number(m[1]));
}

/** The status items of processes running the installed meter. */
function meterItems() {
  const pids = new Set(meterPids());
  return menubar.allItems().filter((i) => pids.has(i.pid));
}

/**
 * The login-item registry's record of the job, as `sfltool dumpbtm` prints it: the record whose
 * URL is the job's LaunchAgent. Null when the registry has none.
 */
function registryRecord() {
  const out = execFileSync('/usr/bin/sudo', ['-n', '/usr/bin/sfltool', 'dumpbtm'], { encoding: 'utf8' });
  const url = `file://${AGENT}`;
  const records = out.split(/\n\s*#\d+:\n/);
  const mine = records.filter((r) => r.split('\n').some((l) => l.trim() === `URL: ${url}`));
  if (mine.length === 0) return null;
  if (mine.length > 1) throw new Error(`the registry holds ${mine.length} records for ${url}`);
  const field = (name) => {
    const m = new RegExp(`^\\s*${name}: (.+)$`, 'm').exec(mine[0]);
    return m ? m[1].trim() : null;
  };
  return { type: field('Type'), disposition: field('Disposition'), executable: field('Executable Path'), raw: mine[0] };
}

const enabled = (record) => record !== null && /^\[enabled\b/.test(record.disposition || '');

/** Refuses to go on when a meter the harness did not start runs (it would hold the shortcut). */
function assertNoForeignMeter(what) {
  const foreign = procs.foreignMeters(meterPids());
  if (foreign.length > 0) {
    throw new Error(`before ${what}: a meter the harness did not start is running (pid ${foreign.join(', ')}): click Quit Meter first`);
  }
}

/** Polls `fn` until it returns a truthy value; returns it, or throws after `ms`. */
async function until(fn, ms, what) {
  const deadline = Date.now() + ms;
  for (;;) {
    const value = fn();
    if (value) return value;
    if (Date.now() > deadline) throw new Error(`timed out after ${ms} ms waiting for ${what}`);
    await procs.sleep(100);
  }
}

/** Takes back everything an install made: the job, its LaunchAgent, the app, the receipt. */
async function uninstall(installedAt = null) {
  assertOurs();
  run('/bin/launchctl', ['bootout', JOB]);
  // A copy the installer opened that runs outside the job (it could not load it) is the
  // install's own too: ended only if it runs the installed program and started after the
  // harness's install began.
  await procs.sleep(200);
  for (const pid of meterPids()) {
    const seen = proc(pid);
    if (installedAt !== null && seen && new Date(seen.started).getTime() >= Math.floor(installedAt / 1000) * 1000
      && seen.program === PROGRAM) {
      process.kill(pid, 'SIGTERM');
    }
  }
  await until(() => meterPids().length === 0, 10000, 'the installed meter to end');
  fs.rmSync(AGENT, { force: true });
  if (installedId() === LABEL) {
    run(LSREGISTER, ['-u', APP]);
    fs.rmSync(APP, { recursive: true, force: true });
  }
  run('/usr/sbin/pkgutil', ['--volume', HOME, '--forget', `${LABEL}.pkg`]);
  fs.rmSync(STATE, { recursive: true, force: true });
}

/** After a test: nothing of the install is left loaded, running or enabled at login. */
async function assertGone() {
  if (job().loaded) throw new Error(`launchd still holds ${LABEL}`);
  if (fs.existsSync(AGENT)) throw new Error(`${AGENT} is still there`);
  if (meterPids().length > 0) throw new Error('an installed meter still runs');
  // macOS's registry keeps its record of a LaunchAgent after the file is gone, still marked
  // enabled, and drops it by itself about 70 s later (measured twice; `sfltool resetbtm` is not
  // needed). Such a record starts nothing: launchd loads only the LaunchAgent files there are.
  // So the check is that the record, if any, names only files that no longer exist.
  const record = registryRecord();
  if (record && record.executable && fs.existsSync(record.executable)) {
    throw new Error(`the registry's record of ${LABEL} still names ${record.executable}`);
  }
}

/**
 * The one install step, as the user does it: the real installer with the harness's package,
 * into the user's home folder. Registers the clean-up for the scenario. Returns when it is done.
 */
async function install(world, version) {
  assertOurs();
  if (!world.presenceCleanup) {
    // The registry's record of an earlier install outlives it by about 70 s, and a re-install
    // inside that window keeps the same record (same identifier, same generation), so the
    // registry part of "starts at login" would be read off the previous install. Wait for it to
    // clear; a record that stays is a leftover the harness cannot tell from this install's.
    await until(() => registryRecord() === null, REGISTRY_CLEAR_MS, `the registry's record of ${LABEL} to clear`);
    assertNoForeignMeter(`${LABEL} install`);
  }
  const startedAt = Date.now();
  if (!world.presenceCleanup) {
    world.presenceCleanup = true;
    world.defer(async () => {
      await uninstall(startedAt);
      await assertGone();
    });
  }
  const r = run('/usr/sbin/installer', ['-pkg', pkg(version), '-target', 'CurrentUserHomeDirectory']);
  if (r.status !== 0) throw new Error(`installer failed (${r.status}): ${r.stdout}${r.stderr}`);
  return { startedAt, endedAt: Date.now() };
}

/** Waits for launchd to run the job, with its item in the menu bar; returns the meter. */
async function running(ms = 10000, notPid = null) {
  const pid = await until(() => {
    const { pid: p } = job();
    return p && p !== notPid && menubar.itemsOf(p).length === 1 ? p : null;
  }, ms, 'the login job to run the meter with its item in the menu bar');
  const seen = proc(pid);
  if (!seen || seen.program !== PROGRAM) throw new Error(`job pid ${pid} runs ${seen && seen.program}, not ${PROGRAM}`);
  return { pid, started: seen.started, ppid: seen.ppid };
}

/** Sends `signal` to the installed meter `meter`, only if it is still that very process. */
function signal(meter, sig) {
  const seen = proc(meter.pid);
  if (!seen || seen.started !== meter.started || seen.program !== PROGRAM || job().pid !== meter.pid) {
    throw new Error(`refusing to signal pid ${meter.pid}: no longer the installed meter the harness started`);
  }
  process.kill(meter.pid, sig);
}

/** Unloads the job, as logging out does. */
function logOut() {
  run('/bin/launchctl', ['bootout', JOB]);
}

/** Loads the user's LaunchAgent as launchd does at login. */
function logInLoad() {
  const r = run('/bin/launchctl', ['bootstrap', DOMAIN, AGENT]);
  if (r.status !== 0) throw new Error(`launchctl bootstrap failed (${r.status}): ${r.stderr}`);
}

/** The LaunchAgent the job is loaded from, as plutil reads it. */
function agentPlist() {
  return JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', AGENT], { encoding: 'utf8' }));
}

module.exports = {
  LABEL, APP, PROGRAM, AGENT, REGISTRY_CLEAR_MS, install, assertNoForeignMeter, uninstall, assertGone, running, signal, job, proc, meterPids,
  meterItems, registryRecord, enabled, until, logOut, logInLoad, agentPlist, installedVersion, installedId,
};
