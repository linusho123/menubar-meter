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
