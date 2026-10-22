'use strict';
// The pure judgement of the seven-day soak report (checks.judgeSoak), on reports that stand for a
// sound week and for each way a week can be wrong: a memory peak in the middle, a hole, a restart,
// a younger process, a sleeping-and-waking Mac, a frozen meter, an older build.
const test = require('node:test');
const assert = require('node:assert');
const checks = require('./support/checks');

const MB = 1048576;
const DAY = 86400;
const VERSION = '0.7.0';
const SHA = 'a'.repeat(64);

/** `ps -o lstart=` text for epoch seconds, local time ("Thu Oct 22 00:42:30 2026"). */
function lstart(sec) {
  const d = new Date(sec * 1000);
  const wd = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getDay()];
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.getMonth()];
  const p = (n) => String(n).padStart(2, '0');
  return `${wd} ${mon} ${d.getDate()} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())} ${d.getFullYear()}`;
}
const cpuText = (s) => `${Math.floor(s / 60)}:${(s % 60).toFixed(2).padStart(5, '0')}`;

/** A sound week: one process started 7 days and 2 hours before the last of its samples, one every 10 minutes. */
function week(over = {}) {
  const t0 = Math.floor(Date.now() / 1000) - 8 * DAY;
  const started = lstart(t0);
  const out = [];
  for (let at = t0 + 600, i = 0; at <= t0 + 7 * DAY + 7200; at += 600, i++) {
    out.push({
      at, program: checks.INSTALLED, pid: 4242, started, stat: 'S', cpu: cpuText(10 + i * 3), footprint: 22 * MB,
      version: VERSION, sha: SHA, sleeptime: t0 - 1000, waketime: t0 - 999,
    });
  }
  return typeof over === 'function' ? over(out, t0) : out;
}
const judge = (samples) => checks.judgeSoak(samples, { version: VERSION });
const all = (r) => [...r.given, ...r.then].join('; ');

test('judgeSoak: a sound week of one process passes and reports its max and day-7 reading', () => {
  const r = judge(week());
  assert.deepStrictEqual([r.given, r.then], [[], []]);
  assert.strictEqual(r.stats.max, '22.0 MB');
});

test('judgeSoak: 69 MB at day 3 fails even when day 7 reads 45 MB (the max is judged, not only day 7)', () => {
  const r = judge(week((s, t0) => s.map((x) => (x.at >= t0 + 3 * DAY && x.at < t0 + 3 * DAY + 600 ? { ...x, footprint: 69 * MB } : x))));
  assert.match(all(r), /69\.0 MB/);
});

test('judgeSoak: a 4-day hole fails (a soak that recorded nothing for days)', () => {
  const r = judge(week((s, t0) => s.filter((x) => x.at < t0 + 2 * DAY || x.at > t0 + 6 * DAY)));
  assert.match(all(r), /gap/);
});

test('judgeSoak: a sample 45 minutes after the last, with no sleep between, fails', () => {
  const r = judge(week((s) => s.filter((x, i) => i % 5 === 0 || i === s.length - 1)));
  assert.match(all(r), /gap/);
});

test('judgeSoak: the same gap across a sleep is not a hole (sleep is not awake time)', () => {
  const r = judge(week((s, t0) => {
    const from = s.findIndex((x) => x.at > t0 + 2 * DAY);
    const slept = s.slice(from, from + 54); // 9 hours of samples gone
    const gone = new Set(slept);
    const sleptAt = slept[0].at;
    const wokeAt = slept.at(-1).at + 600;
    return s.filter((x) => !gone.has(x)).map((x) => (x.at >= wokeAt ? { ...x, sleeptime: sleptAt + 30, waketime: wokeAt - 30 } : x));
  }));
  assert.deepStrictEqual([r.given, r.then], [[], []], all(r));
});

test('judgeSoak: two processes fail (a restart resets the count)', () => {
  const r = judge(week((s) => s.map((x, i) => (i > 500 ? { ...x, pid: 5000, started: lstart(x.at - 100) } : x))));
  assert.match(all(r), /one meter process|different process/);
});

test('judgeSoak: a meter-not-running line inside the window fails', () => {
  const r = judge(week((s) => [...s.slice(0, 300), { at: s[300].at + 1, program: null }, ...s.slice(300)]));
  assert.match(all(r), /not running/);
});

test('judgeSoak: a process under 7 days old fails', () => {
  const r = judge(week((s) => s.slice(0, 900)));
  assert.match(all(r), /7 days/);
});

test('judgeSoak: CPU time that does not advance across awake samples fails (a frozen meter)', () => {
  const r = judge(week((s) => s.map((x, i) => (i > 200 && i < 260 ? { ...x, cpu: s[200].cpu } : x))));
  assert.match(all(r), /CPU time/);
});

test('judgeSoak: a stopped process (state T) fails', () => {
  const r = judge(week((s) => s.map((x, i) => (i === 400 ? { ...x, stat: 'T' } : x))));
  assert.match(all(r), /state T/);
});

test('judgeSoak: an older build (version 0.1.0) fails as not the P7 build', () => {
  const r = judge(week((s) => s.map((x) => ({ ...x, version: '0.1.0' }))));
  assert.match(all(r), /not the P7 build/);
});

test('judgeSoak: a changed executable (sha) fails', () => {
  const r = judge(week((s) => s.map((x, i) => (i > 800 ? { ...x, sha: 'b'.repeat(64) } : x))));
  assert.match(all(r), /sha/);
});

test('judgeSoak: sustained growth (day-7 max more than 5 MB above day 1) fails even under 50 MB', () => {
  const r = judge(week((s, t0) => s.map((x) => ({ ...x, footprint: (22 + ((x.at - t0) / DAY) * 1.5) * MB }))));
  assert.match(all(r), /grew|growth/);
});

test('judgeSoak: error lines are kept visible and do not hide a hole', () => {
  const r = judge(week((s, t0) => [{ at: t0 + 100, error: 'empty footprint' }, ...s.filter((x) => x.at < t0 + 3 * DAY || x.at > t0 + 5 * DAY)]));
  assert.match(all(r), /gap/);
  assert.strictEqual(r.stats.errors, 1);
});

test('the build ships as the P7 version the reports are held to (0.7.0)', () => {
  assert.strictEqual(checks.appVersion(), '0.7.0');
});

// --- F4: the energy read sees a listed app, and an unreadable menu is unreadable ----------

const fs = require('node:fs');
const path = require('node:path');
const fixture = (name) => JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', `battery-menu-${name}.json`), 'utf8'));

test('energySection: "No Apps Using Significant Energy" is none', () => {
  assert.strictEqual(checks.energySection(fixture('none')).state, 'none');
});

test('energySection: app names carried as buttons and menu items are read, and Meter is found', () => {
  const r = checks.energySection(fixture('listed-meter'));
  assert.strictEqual(r.state, 'listed');
  assert.deepStrictEqual(r.apps, ['Safari', 'Meter']);
});

test('energySection: only "Meter Pro" listed is not Meter (the match is exact)', () => {
  const r = checks.energySection(fixture('listed-meter-pro'));
  assert.strictEqual(r.state, 'listed');
  assert.ok(!r.apps.includes('Meter'));
});

test('energySection: a heading with no rows readable is unreadable, never "Meter not listed"', () => {
  assert.strictEqual(checks.energySection(fixture('unreadable-no-rows')).state, 'unreadable');
});

test('energySection: no energy heading at all is unreadable', () => {
  assert.strictEqual(checks.energySection(fixture('unreadable-no-section')).state, 'unreadable');
});

test('energySection: the menu macOS really showed (captured here, on AC) lists its app and not Meter', () => {
  const r = checks.energySection(fixture('real-ac-listed'));
  assert.strictEqual(r.state, 'listed');
  assert.ok(r.apps.length >= 1 && !r.apps.includes('Meter'), JSON.stringify(r));
});

const pmDate = (sec) => {
  const x = new Date(sec * 1000);
  const p = (n) => String(n).padStart(2, '0');
  const off = -x.getTimezoneOffset();
  return `${x.getFullYear()}-${p(x.getMonth() + 1)}-${p(x.getDate())} ${p(x.getHours())}:${p(x.getMinutes())}:${p(x.getSeconds())} ${off < 0 ? '-' : '+'}${p(Math.floor(Math.abs(off) / 60))}${p(Math.abs(off) % 60)}`;
};
const ASSERT = (sec, src) => `${pmDate(sec)} Assertions          \tSummary- [System: PrevIdle] Using ${src} (Charge:80)`;
const SLEEP = (sec) => `${pmDate(sec)} Sleep               \tEntering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:90%) 3 secs`;
const WAKE = (sec) => `${pmDate(sec)} Wake                \tWake from Deep Idle [CDNVAP] : due to EC.LidOpen Using BATT (Charge:50%)`;
const DARK = (sec) => `${pmDate(sec)} DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake Using BATT (Charge:50)`;
const H = 3600;

test('batteryDay: 450 power lines after the switch are read whole (a 400-line window lost the AC line)', () => {
  const at = Math.floor(Date.now() / 1000);
  const lines = [ASSERT(at - 8 * H, 'AC'), ...Array.from({ length: 450 }, (_, i) => ASSERT(at - 8 * H + 60 + i * 60, 'Batt'))];
  const r = checks.batteryDay(lines, at);
  assert.strictEqual(r.state, 'ok');
  assert.ok(Math.abs(r.hours - 7.98) < 0.05, r.hours);
});

test('batteryDay: 8 hours of sleep on battery are wall time, not awake time', () => {
  const at = Math.floor(Date.now() / 1000);
  const lines = [ASSERT(at - 10 * H, 'AC'), ASSERT(at - 9.5 * H, 'Batt'), SLEEP(at - 9 * H), DARK(at - 5 * H), WAKE(at - 1 * H), ASSERT(at - 0.5 * H, 'BATT')];
  const r = checks.batteryDay(lines, at);
  assert.ok(Math.abs(r.hours - 9.5) < 0.01);
  assert.ok(Math.abs(r.sleptHours - 8) < 0.01, `slept ${r.sleptHours}`);
  assert.ok(Math.abs(r.awakeHours - 1.5) < 0.01);
});

test('batteryDay: no AC line at all is unreadable (the switch cannot be dated)', () => {
  const at = Math.floor(Date.now() / 1000);
  assert.strictEqual(checks.batteryDay([ASSERT(at - 8 * H, 'Batt')], at).state, 'unreadable');
});

test('batteryDay: a Mac that never went on battery after the last AC line is unreadable', () => {
  const at = Math.floor(Date.now() / 1000);
  assert.strictEqual(checks.batteryDay([ASSERT(at - 8 * H, 'AC')], at).state, 'unreadable');
});

// --- F4/F6: the energy report's Given ---------------------------------------------------

function energyReport(over = {}) {
  const at = Math.floor(Date.now() / 1000);
  const started = lstart(at - 20 * H);
  return {
    at,
    power: "Now drawing from 'Battery Power'",
    powerLog: [ASSERT(at - 10 * H, 'AC'), ASSERT(at - 9 * H, 'Batt')],
    meter: {
      program: checks.INSTALLED, pid: 4242, started, version: VERSION, sha: SHA,
      live: { stat1: 'S', time1: '1:00.00', stat2: 'S', time2: '1:00.30', ax: 'CPU 10%  GPU  2%  RAM 50%  45°C' },
    },
    meterAfter: { pid: 4242, started },
    menu: fixture('listed-meter-pro'),
    control: { seen: true, name: 'EnergyControl' },
    ...over,
  };
}
const energyJudge = (r) => checks.judgeEnergy(r, { version: VERSION }).problems.join('; ');

test('judgeEnergy: a sound report passes', () => {
  assert.strictEqual(energyJudge(energyReport()), '');
});

test('judgeEnergy: version 0.1.0 is not the P7 build', () => {
  const r = energyReport();
  r.meter.version = '0.1.0';
  assert.match(energyJudge(r), /not the P7 build/);
});

test('judgeEnergy: a frozen meter (CPU time not advancing, no Accessibility title) fails', () => {
  const frozen = energyReport();
  frozen.meter.live.time2 = frozen.meter.live.time1;
  assert.match(energyJudge(frozen), /CPU time/);
  const silent = energyReport();
  silent.meter.live.ax = '';
  assert.match(energyJudge(silent), /Accessibility/);
});

test('judgeEnergy: a day mostly asleep fails the 6 awake hours', () => {
  const r = energyReport();
  const at = r.at;
  r.powerLog = [ASSERT(at - 10 * H, 'AC'), ASSERT(at - 9.5 * H, 'Batt'), SLEEP(at - 9 * H), WAKE(at - 1 * H)];
  assert.match(energyJudge(r), /awake/);
});

test('judgeEnergy (ruling): no control needed; Ghostty listed and Meter not passes', () => {
  assert.strictEqual(energyJudge(energyReport({ control: undefined, menu: fixture('real-ac-listed') })), '');
});

test('judgeEnergy (ruling): the explicit "No Apps Using Significant Energy" passes', () => {
  assert.strictEqual(energyJudge(energyReport({ control: undefined, menu: fixture('none') })), '');
});

test('judgeEnergy (ruling): Meter listed fails; heading with no rows and an empty menu are unreadable and fail', () => {
  assert.match(energyJudge(energyReport({ control: undefined, menu: fixture('listed-meter') })), /Meter among them/);
  assert.match(energyJudge(energyReport({ control: undefined, menu: fixture('unreadable-no-rows') })), /unreadable/);
  assert.match(energyJudge(energyReport({ control: undefined, menu: fixture('empty') })), /unreadable/);
});

test('judgeEnergy: an unreadable menu fails plainly, distinct from Meter listed', () => {
  const r = energyReport({ menu: fixture('unreadable-no-rows') });
  assert.match(energyJudge(r), /unreadable/);
  const listed = energyReport({ menu: fixture('listed-meter') });
  assert.match(checks.judgeEnergy(listed, { version: VERSION }).meterListed ? 'listed' : '', /listed/);
});

test('judgeEnergy: a restart during the day fails (the meter started after the switch to battery)', () => {
  const r = energyReport();
  r.meter.started = lstart(r.at - 2 * H);
  r.meterAfter.started = r.meter.started;
  assert.match(energyJudge(r), /since before/);
});
