'use strict';
// The two checks that run on the user's own installed meter (docs/P7-SOAK-AND-ENERGY.md), checked
// here on a meter the harness runs: the soak script reads what ps and footprint read, and writes
// its report once the process is old enough; the battery-menu read refuses to run off battery.
// These check the checks; they never stand in for the scenarios their reports bind.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync, execFileSync } = require('node:child_process');
const paths = require('./support/paths');
const procs = require('./support/procs');
const menubar = require('./support/menubar');
const cost = require('./support/cost');
const checks = require('./support/checks');

const soakScript = path.join(paths.root, 'scripts', 'checks', 'soak.sh');
const energyScript = path.join(paths.root, 'scripts', 'checks', 'energy-check.js');
/** The version the app is built with (app/Info.plist). */
const appVersion = () => execFileSync('plutil', ['-extract', 'CFBundleShortVersionString', 'raw', path.join(paths.root, 'app', 'Info.plist')], { encoding: 'utf8' }).trim();
const lines = (file) => (fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);

function soak(dir, env) {
  const r = spawnSync('/bin/sh', [soakScript], { encoding: 'utf8', env: { HOME: os.homedir(), METER_CHECKS_DIR: dir, ...env } });
  assert.strictEqual(r.status, 0, r.stderr);
}

test('the soak reads the meter as ps and footprint do, and reports once the process is old enough', async () => {
  const foreign = procs.foreignMeters();
  assert.deepStrictEqual(foreign, [], 'no meter the harness did not start is running');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-soak-'));
  const meter = procs.start(paths.releaseApp);
  try {
    await menubar.waitForItem(meter.pid, () => true, 10000, 'the meter');
    // Not old enough: a sample, no report.
    soak(dir, { METER_SOAK_PROGRAM: paths.releaseApp, METER_SOAK_SECONDS: '3600' });
    const memory = cost.memory(meter.pid);
    let samples = lines(path.join(dir, 'soak.ndjson'));
    assert.strictEqual(samples.length, 1);
    const [s] = samples;
    assert.strictEqual(s.program, paths.releaseApp);
    assert.strictEqual(s.pid, meter.pid);
    assert.strictEqual(s.started, meter.started.replace(/\s+/g, ' '), 'ps lstart, spaces squeezed');
    assert.ok(Math.abs(s.footprint - memory.bytes) <= 0.1 * memory.bytes, `soak ${s.footprint} bytes, footprint ${memory.bytes}`);
    assert.ok(Math.abs(s.at - Date.now() / 1000) < 30);
    assert.match(s.cpu, /^\d+:\d{2}\.\d{2}$/);
    assert.match(s.stat, /^[A-Z]/, 'the process state is recorded');
    assert.match(s.sha, /^[0-9a-f]{64}$/, 'the executable\'s sha256 is recorded');
    assert.ok(Number.isInteger(s.sleeptime) && Number.isInteger(s.waketime), 'kern.sleeptime and kern.waketime are recorded');
    assert.strictEqual(s.version, appVersion(), 'the version of the app read');
    assert.ok(!fs.existsSync(path.join(dir, 'soak-report.ndjson')), 'no report before the process is old enough');
    assert.ok(Math.abs(checks.lstartSeconds(s.started) - Date.now() / 1000) < 120, 'the start time reads back as now');
    // Old enough: the report holds every sample of that process, and the soak stops reading.
    soak(dir, { METER_SOAK_PROGRAM: paths.releaseApp, METER_SOAK_SECONDS: '0' });
    const report = lines(path.join(dir, 'soak-report.ndjson'));
    assert.strictEqual(report.length, 2);
    assert.ok(report.every((r) => r.pid === meter.pid && r.started === s.started));
    soak(dir, { METER_SOAK_PROGRAM: paths.releaseApp, METER_SOAK_SECONDS: '0' });
    samples = lines(path.join(dir, 'soak.ndjson'));
    assert.strictEqual(samples.length, 2, 'once reported, the soak reads no more');
  } finally {
    await procs.end(meter);
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('a restart mid-soak gives no report for the old process: the report starts at the new process\'s first reading', async () => {
  const foreign = procs.foreignMeters();
  assert.deepStrictEqual(foreign, [], 'no meter the harness did not start is running');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-soak-'));
  const env = { METER_SOAK_PROGRAM: paths.releaseApp, METER_SOAK_SECONDS: '0' };
  const first = procs.start(paths.releaseApp);
  let second;
  try {
    await menubar.waitForItem(first.pid, () => true, 10000, 'the first meter');
    // One reading of the first process, not yet old enough (the check needs 1 h), then it ends.
    soak(dir, { ...env, METER_SOAK_SECONDS: '3600' });
    await procs.end(first);
    soak(dir, env); // no meter running: a null line
    second = procs.start(paths.releaseApp);
    await menubar.waitForItem(second.pid, () => true, 10000, 'the second meter');
    soak(dir, env);
    const report = lines(path.join(dir, 'soak-report.ndjson'));
    assert.strictEqual(report.length, 1, `the report holds the new process only: ${JSON.stringify(report)}`);
    assert.strictEqual(report[0].pid, second.pid);
    assert.ok(!fs.readFileSync(path.join(dir, 'soak-report.ndjson'), 'utf8').includes(`"pid":${first.pid},`), 'nothing of the old process');
    assert.strictEqual(lines(path.join(dir, 'soak.ndjson')).length, 3, 'the log keeps the old reading, the gap and the new one');
  } finally {
    await procs.end(first);
    if (second) await procs.end(second);
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('the soak leaves an error line, never a silent exit, when it cannot take a reading', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-soak-'));
  try {
    // logd runs as root, and footprint may not read another user's process: no reading, so an error line.
    soak(dir, { METER_SOAK_PROGRAM: '/usr/libexec/logd', METER_SOAK_SECONDS: '0' });
    const samples = lines(path.join(dir, 'soak.ndjson'));
    assert.strictEqual(samples.length, 1, 'a run that reads nothing still leaves a line');
    assert.match(samples[0].error, /footprint/);
    assert.ok(!fs.existsSync(path.join(dir, 'soak-report.ndjson')));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('with no installed meter running, the soak records the gap and reports nothing', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-soak-'));
  try {
    soak(dir, { METER_SOAK_PROGRAM: path.join(dir, 'Meter.app', 'Contents', 'MacOS', 'Meter'), METER_SOAK_SECONDS: '0' });
    const samples = lines(path.join(dir, 'soak.ndjson'));
    assert.strictEqual(samples.length, 1);
    assert.strictEqual(samples[0].program, null);
    assert.ok(!fs.existsSync(path.join(dir, 'soak-report.ndjson')));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('the battery-menu read refuses to run off battery and writes nothing', (t) => {
  const power = execFileSync('pmset', ['-g', 'batt'], { encoding: 'utf8' }).split('\n')[0];
  if (/'Battery Power'/.test(power)) {
    t.skip('on battery: the gate runs plugged in');
    return;
  }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-energy-'));
  try {
    const r = spawnSync(process.execPath, [energyScript], { encoding: 'utf8', env: { ...process.env, METER_CHECKS_DIR: dir } });
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr, /not on battery/);
    assert.deepStrictEqual(fs.readdirSync(dir), []);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('the reports\' times read as the system writes them', () => {
  const epoch = Number(execFileSync('date', ['-j', '-f', '%Y-%m-%d %H:%M:%S %z', '2026-10-21 21:39:37 -0700', '+%s'], { encoding: 'utf8' }));
  assert.strictEqual(checks.pmsetSeconds('2026-10-21 21:39:37 -0700 Assertions  Summary- [System: PrevIdle] Using AC(Charge: 100)'), epoch);
  const local = Number(execFileSync('date', ['-j', '-f', '%a %b %d %T %Y', 'Thu Oct 2 00:42:30 2026', '+%s'], { encoding: 'utf8' }));
  assert.strictEqual(checks.lstartSeconds('Thu Oct  2 00:42:30 2026'), local);
  assert.strictEqual(checks.lstartSeconds('Thu Oct 2 00:42:30 2026'), local);
});
