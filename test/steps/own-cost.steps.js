'use strict';
// own-cost.feature. The meter's own cost, read from outside it: its CPU time from `ps` over a
// minute (mean and the busiest second, as shares of the whole Mac), its memory as Activity
// Monitor's Memory column shows it (the physical footprint, from `footprint`), and macOS's own
// battery menu read through Accessibility. Every meter measured here is the release build, never
// the test build and never a debug build: the Given checks the very program it runs.
//
// The seven-day memory row and the energy scenario run on the user's own installed meter in normal
// use (docs/P7-SOAK-AND-ENERGY.md). Their steps are bound only once that check's report exists;
// until then they stay unbound, and the register in features.test.js holds them in wip.
const assert = require('node:assert');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const paths = require('../support/paths');
const procs = require('../support/procs');
const meter = require('../support/meter');
const panel = require('../support/panel');
const cost = require('../support/cost');
const checks = require('../support/checks');

const run = (file, args) => execFileSync(file, args, { encoding: 'utf8' });
const required = (value, what) => {
  if (value === undefined || value === null) throw new Error(`world.${what} read before any step set it`);
  return value;
};

/** How long a day on battery must have lasted for the battery menu's read to count: "all day". */
const ALL_DAY_HOURS = 6;
const DAY = 86400;

/**
 * The meter being measured is the release build: the program the harness started is the bundled
 * release app, every object it was linked from was compiled in the release configuration (the
 * debug-map paths the linker records), and the test reading source is not compiled in.
 */
function assertReleaseBuild(pid) {
  const program = run('ps', ['-o', 'comm=', '-p', String(pid)]).trim();
  assert.strictEqual(program, paths.releaseApp, `ps: the meter measured runs ${program}`);
  const objects = run('nm', ['-ap', program]).split('\n').filter((l) => / OSO /.test(l))
    .map((l) => l.replace(/^.* OSO /, '')).filter((o) => /\/Meter\.build\//.test(o));
  assert.ok(objects.length > 0, 'the release program records the objects it was linked from');
  const debug = objects.filter((o) => !/\/release\/Meter\.build\//.test(o));
  assert.deepStrictEqual(debug, [], 'every object of the program measured was compiled for release');
  const bytes = fs.readFileSync(program);
  for (const marker of ['10TestInputs', 'feedPath']) {
    assert.ok(!bytes.includes(marker), `the program measured has no test reading source (${marker})`);
  }
}

function panelOpen(pid) {
  return JSON.parse(run(paths.meterAx, ['windows', String(pid)])).length === 1;
}

async function closePanel(pid) {
  if (!panelOpen(pid)) return;
  run(paths.meterAx, ['press', String(pid)]);
  const deadline = Date.now() + 3000;
  while (panelOpen(pid) && Date.now() < deadline) await procs.sleep(50);
  assert.ok(!panelOpen(pid), 'the panel closed');
}

/** Keeps the display awake (and so the screen unlocked) while the harness's meter runs. */
function keepAwake(w, pid) {
  const awake = procs.start('/usr/bin/caffeinate', ['-d', '-i', '-w', String(pid)]);
  w.defer(() => procs.end(awake));
}

module.exports = (reg) => {
  // --- D73: CPU over a minute -------------------------------------------------------------

  reg.define(/^the meter is running with its panel (closed|open), refreshing every second$/, async (w, state) => {
    const m = await meter.launchReal(w);
    assertReleaseBuild(m.pid);
    // Settled: the first passes and the status item placed.
    await procs.sleep(3000);
    if (state === 'open') {
      await panel.click(m.pid);
      await procs.sleep(3000);
    }
    assert.strictEqual(panelOpen(m.pid), state === 'open', `the panel is ${state}`);
    w.panelState = state;
  });

  reg.define(/^a minute passes$/, async (w) => {
    const m = required(w.meter, 'meter');
    w.cpu = await cost.cpuOver(m.pid, 60, () => procs.isRunning(m));
    // The panel stayed as it was for the whole minute.
    assert.strictEqual(panelOpen(m.pid), w.panelState === 'open', `the panel is still ${w.panelState}`);
  });

  reg.define(
    /^the meter's own CPU use over that minute, as a share of the whole Mac measured outside the meter, is under (\d+)%$/,
    (w, line) => {
      const c = required(w.cpu, 'cpu');
      const limit = Number(line);
      const said = `ps over ${c.seconds.toFixed(1)} s: mean ${c.mean.toFixed(3)}%, busiest second ${c.peak.toFixed(3)}% of the whole Mac`;
      assert.ok(c.seconds >= 59.5, `a whole minute was measured: ${said}`);
      // A stopped or hung meter uses no CPU: it must have been alive for the whole minute.
      assert.deepStrictEqual(c.alive, [], `the meter was alive and running through the minute: ${said}`);
      assert.ok(c.mean < limit, `the meter's CPU over the minute is under ${limit}%: ${said}`);
      // A spike is never averaged away: the busiest second is held to the same line.
      assert.ok(c.peak < limit, `the meter's busiest second is under ${limit}% too: ${said}`);
    });

  // --- D76: memory after an hour, and after seven days -----------------------------------

  reg.define(/^the meter has been running without a restart for 1 hour$/, async (w) => {
    const m = await meter.launchReal(w);
    assertReleaseBuild(m.pid);
    keepAwake(w, m.pid);
    // An hour of normal use: the panel opened for a minute every ten minutes, the meter read every
    // minute (memory, state, CPU time, Accessibility). METER_HOUR_SECONDS shortens the hour (and
    // every window with it) for checking the row itself; the gate runs the whole hour.
    const hourMs = (Number(process.env.METER_HOUR_SECONDS) || 3600) * 1000;
    const unit = hourMs / 60;
    const start = Date.now();
    w.memorySamples = [];
    w.hourMs = hourMs;
    const sample = (panelState) => {
      const { stat, time } = cost.psStatTime(m.pid);
      w.memorySamples.push({
        at: Date.now(), bytes: cost.memory(m.pid).bytes, panel: panelState, stat, cpu: cost.cpuSeconds(time), ax: cost.axAlive(m.pid),
      });
    };
    for (let minute = 0; Date.now() - start < hourMs; minute++) {
      const due = start + minute * unit;
      if (due > Date.now()) await procs.sleep(due - Date.now());
      if (minute % 10 === 5) {
        await panel.click(m.pid);
        // Read with the panel open 10 s after the click, not at the instant of it.
        await procs.sleep(Math.min(10000, unit / 2));
        sample('open');
      } else if (minute % 10 === 6) {
        // And again just before it is closed.
        sample('open');
        await closePanel(m.pid);
      } else {
        sample('closed');
      }
      assert.ok(procs.isRunning(m), 'the meter ran the whole hour without a restart');
    }
    w.ranFor = `${((Date.now() - start) / 60000).toFixed(1)} minutes`;
    w.hourMeter = m;
  });

  reg.define(/^the user looks at the meter's row in Activity Monitor's Memory tab$/, async (w) => {
    if (w.soak) {
      // The seven-day row: the soak's reading of the installed meter at seven days or later.
      w.looked = [{ panel: 'as the user left it', ...w.soak.atSevenDays }];
      return;
    }
    const m = required(w.hourMeter, 'hourMeter');
    // The value the user sees with the panel open (opened with a click on the status item) and
    // with it closed: both must be under the line.
    await panel.click(m.pid);
    await procs.sleep(2000);
    w.looked = [{ panel: 'open', ...cost.memory(m.pid) }];
    await closePanel(m.pid);
    await procs.sleep(2000);
    w.looked.push({ panel: 'closed', ...cost.memory(m.pid) });
  });

  reg.define(/^the user sees its Memory value under 50 MB, after (1 hour|7 days)$/, (w, time) => {
    const looked = required(w.looked, 'looked');
    if (time === '7 days') required(w.soak, 'soak');
    else required(w.hourMeter, 'hourMeter');
    if (time === '7 days') {
      const st = w.soak.judged.stats;
      const week = `highest reading ${st.max}, day-7 reading ${st.day7}, ${st.samples} readings, awake ${(st.awakeShare * 100).toFixed(0)}% of the time`;
      assert.deepStrictEqual(w.soak.judged.then, [], `the week's readings: ${week}`);
    }
    const said = looked.map((l) => `${l.shown} (${l.bytes} bytes, panel ${l.panel})`).join('; ');
    let history = '';
    if (time === '1 hour') {
      // Every reading of the hour is judged, not only the end ones.
      const hour = cost.judgeHour(required(w.memorySamples, 'memorySamples'), { hourMs: w.hourMs });
      history = `; over the ${w.ranFor}: highest ${hour.max}, first ${hour.first}, last ${hour.last}`;
      assert.deepStrictEqual(hour.problems, [], `the hour's readings${history}`);
    }
    for (const l of looked) {
      assert.ok(l.under50, `Activity Monitor's Memory for the meter after ${time}: ${said}${history}`);
    }
  });

  // The seven-day row: bound once the soak has reported (Q2).
  const soak = checks.soakReport();
  if (soak) {
    reg.define(/^the meter has been running without a restart for 7 days$/, (w) => {
      // One process (same pid and start time) of the P7 build, seven days old by its own start time,
      // read without an awake hole, its CPU time advancing: a restart resets the count (ruled 2026-10-22).
      const judged = checks.judgeSoak(soak, { version: checks.appVersion() });
      assert.deepStrictEqual(judged.given, [], `the soak report ${checks.soakReportFile} shows one P7 process alive for seven days`);
      const last = soak.filter((s) => s.program && !s.error).at(-1);
      const memory = JSON.parse(run(paths.meterCost, ['memory', String(last.footprint)]));
      w.soak = { judged, atSevenDays: { ...memory, at: last.at } };
    });
  }

  // --- D75: never an energy hog (Q3) -----------------------------------------------------

  const energy = checks.energyReport();
  if (energy) {
    reg.define(/^the Mac is on battery and the meter has been running all day$/, (w) => {
      assert.match(energy.power, /'Battery Power'/, `pmset: on battery when the menu was read: ${energy.power}`);
      const lines = energy.powerLog;
      const lastAC = lines.map((l, i) => (/Using AC/.test(l) ? i : -1)).filter((i) => i >= 0).at(-1) ?? -1;
      const onBattery = lines.slice(lastAC + 1).find((l) => /Using Batt/.test(l));
      assert.ok(onBattery, `pmset's log shows the switch to battery: ${JSON.stringify(lines.slice(-5))}`);
      const since = checks.pmsetSeconds(onBattery);
      const hours = (energy.at - since) / 3600;
      assert.ok(hours >= ALL_DAY_HOURS, `on battery ${hours.toFixed(1)} h before the read (all day: ${ALL_DAY_HOURS} h or more)`);
      assert.strictEqual(energy.meter.program, checks.INSTALLED, 'the installed meter was running');
      assert.ok(checks.lstartSeconds(energy.meter.started) < since,
        `the meter (started ${energy.meter.started}) ran since before the Mac went on battery`);
      w.energy = energy;
    });

    reg.define(/^the user opens the battery menu$/, (w) => {
      const e = required(w.energy, 'energy');
      // The menu the harness opened: the battery's own, with its energy section.
      assert.ok(e.menu.includes('Battery'), `the battery menu was open: ${JSON.stringify(e.menu)}`);
      assert.ok(e.menu.some((t) => /^(No )?Apps Using Significant Energy$/.test(t)),
        `the menu shows its energy section: ${JSON.stringify(e.menu)}`);
      w.batteryMenu = e.menu;
    });

    reg.define(/^the user does not see the meter listed under "Apps Using Significant Energy"$/, (w) => {
      const menu = required(w.batteryMenu, 'batteryMenu');
      const heading = menu.findIndex((t) => /^(No )?Apps Using Significant Energy$/.test(t));
      const listed = menu.slice(heading + 1);
      assert.ok(!listed.some((t) => /\bMeter\b/.test(t)),
        `the battery menu lists ${JSON.stringify(listed)} under "${menu[heading]}"`);
    });
  }
};
