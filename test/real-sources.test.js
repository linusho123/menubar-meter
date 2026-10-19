'use strict';
// The installed build against the real Mac: each number the menu bar shows,
// read through Accessibility, beside what macOS's own tools and Activity
// Monitor's own window report at the same moment. These are the real-system
// witnesses for the readings the feature outlines pin through the test
// source; nothing here reads the meter's own output except the menu bar.
const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const meter = require('./support/meter');
const menubar = require('./support/menubar');
const probes = require('./support/probes');
const procs = require('./support/procs');
const { busyTask } = require('./support/load');
const { releaseApp, testApp, binaryOf, harness } = require('./support/paths');

/** node:test's cleanup in the feature world's shape. */
function worldFor(t) {
  const fns = [];
  t.after(async () => { for (const fn of fns.reverse()) await fn(); });
  return { defer: (fn) => fns.push(fn) };
}

async function shown(pid) {
  const it = await menubar.item(pid);
  const p = it && menubar.parse(it.title);
  assert.ok(p, `the item's text has another shape: ${JSON.stringify(it)}`);
  return Object.fromEntries(Object.entries(p.value).map(([k, v]) => [k, v.includes('–') ? null : parseInt(v, 10)]));
}

test('the installed build has no test reading source compiled in', () => {
  const symbols = (app) => execFileSync('nm', [binaryOf(app)], { encoding: 'utf8', maxBuffer: 64 << 20 });
  const strings = (app) => execFileSync('strings', ['-a', binaryOf(app)], { encoding: 'utf8', maxBuffer: 64 << 20 });
  // The check can see the source where it is compiled in…
  assert.match(symbols(testApp), /TestInputs/);
  assert.match(strings(testApp), /METER_TEST_SOURCE/);
  // …and the installed build has none of it.
  assert.doesNotMatch(symbols(releaseApp), /TestInputs/);
  assert.doesNotMatch(strings(releaseApp), /METER_TEST_SOURCE/);
});

test('RAM matches Activity Monitor\'s Memory Used on the real Mac', async (t) => {
  const w = worldFor(t);
  const m = await meter.launch(w);
  const amPid = await activityMonitorOnMemoryTab(w);
  // Activity Monitor refreshes every few seconds: compare several moments.
  const diffs = [];
  for (let i = 0; i < 4; i++) {
    const am = JSON.parse(execFileSync(harness, ['am-memory', String(amPid)], { encoding: 'utf8' }));
    const ram = (await shown(m.pid)).RAM;
    const amUsed = toBytes(am['Memory Used:']);
    const amPct = Math.round(amUsed * 100 / probes.physicalBytes());
    const vmPct = Math.round(probes.memoryUsedBytes() * 100 / probes.physicalBytes());
    diffs.push({ ram, amPct, vmPct, amUsed: am['Memory Used:'] });
    await procs.sleep(1500);
  }
  t.diagnostic(JSON.stringify(diffs));
  for (const d of diffs) {
    assert.ok(Math.abs(d.ram - d.amPct) <= 1, `menu bar RAM ${d.ram}% vs Activity Monitor ${d.amUsed} (${d.amPct}%)`);
    assert.ok(Math.abs(d.ram - d.vmPct) <= 1, `menu bar RAM ${d.ram}% vs vm_stat ${d.vmPct}%`);
  }
});

test('CPU follows a known load on the real Mac, as top counts it', async (t) => {
  const w = worldFor(t);
  const m = await meter.launch(w);
  const cores = probes.cores();
  const busy = Math.floor(cores / 2);
  busyTask(w, busy);
  await procs.sleep(3000);
  const pairs = [];
  for (let i = 0; i < 3; i++) {
    const [top, a] = await Promise.all([probes.topCpu(), procs.sleep(700).then(() => shown(m.pid))]);
    pairs.push({ meter: a.CPU, top: Math.round(top.user + top.sys) });
  }
  t.diagnostic(JSON.stringify({ busy, cores, pairs }));
  for (const p of pairs) {
    assert.ok(p.meter >= busy * 100 / cores - 5, `menu bar CPU ${p.meter}% with ${busy} of ${cores} cores busy`);
    assert.ok(Math.abs(p.meter - p.top) <= 10, `menu bar CPU ${p.meter}% vs top ${p.top}%`);
  }
});

test('GPU is the utilization macOS reports (ioreg) on the real Mac', async (t) => {
  const w = worldFor(t);
  const m = await meter.launch(w);
  const pairs = [];
  for (let i = 0; i < 6; i++) {
    const before = probes.gpuUtilization();
    const gpu = (await shown(m.pid)).GPU;
    const after = probes.gpuUtilization();
    pairs.push({ before, gpu, after });
    await procs.sleep(1100);
  }
  t.diagnostic(JSON.stringify(pairs));
  // The menu bar shows the last pass's reading (up to a second old), so it is
  // checked against ioreg's figures on either side of the read.
  const close = pairs.filter((p) => Math.min(Math.abs(p.gpu - p.before), Math.abs(p.gpu - p.after)) <= 10);
  assert.ok(close.length >= 4, `menu bar GPU strays from ioreg's Device Utilization %: ${JSON.stringify(pairs)}`);
});

function toBytes(text) {
  const m = /^([\d.,]+) (bytes|KB|MB|GB|TB)$/.exec(text || '');
  assert.ok(m, `not a memory figure: ${JSON.stringify(text)}`);
  const scale = { bytes: 1, KB: 2 ** 10, MB: 2 ** 20, GB: 2 ** 30, TB: 2 ** 40 }[m[2]];
  return Number(m[1].replace(/,/g, '')) * scale;
}

/**
 * Activity Monitor showing its Memory tab. Opened in the background when it
 * is not running, and then asked to quit afterwards, but only if it is still
 * the very process this test opened (pid and start time).
 */
async function activityMonitorOnMemoryTab(w) {
  const pidOf = () => {
    try { return Number(execFileSync('pgrep', ['-x', 'Activity Monitor'], { encoding: 'utf8' }).trim().split('\n')[0]); } catch { return null; }
  };
  let pid = pidOf();
  if (!pid) {
    execFileSync('open', ['-g', '-a', 'Activity Monitor']);
    for (let i = 0; i < 100 && !(pid = pidOf()); i++) await procs.sleep(100);
    assert.ok(pid, 'Activity Monitor did not start');
    const started = procs.startTimeOf(pid);
    w.defer(async () => {
      if (procs.startTimeOf(pid) === started) {
        execFileSync('osascript', ['-e', 'tell application id "com.apple.ActivityMonitor" to quit']);
      }
    });
    await procs.sleep(2000);
  }
  const hasSummary = () => 'Memory Used:' in JSON.parse(execFileSync(harness, ['am-memory', String(pid)], { encoding: 'utf8' }));
  if (!hasSummary()) {
    execFileSync('osascript', ['-e',
      'tell application "System Events" to tell process "Activity Monitor" to click radio button 2 of radio group 1 of group 1 of toolbar 1 of window 1']);
    await procs.sleep(2000);
  }
  assert.ok(hasSummary(), 'Activity Monitor is not showing its Memory tab');
  return pid;
}
