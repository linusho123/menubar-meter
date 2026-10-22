'use strict';
// The battery-menu read for "never an energy hog" (D75, Q3), run by the user at the end of a day
// on battery (docs/P7-SOAK-AND-ENERGY.md): `node scripts/checks/energy-check.js`. It checks the
// Mac is on battery and the installed meter is running, opens the battery menu through
// Accessibility (meter-ax, as an assistive app presses a menu bar item; the pointer never moves),
// reads every text in it, closes it again and writes energy-report.json with what macOS showed:
//   { at, power (pmset -g batt), powerLog (pmset -g log's power-source lines), meter: { program,
//     pid, started (ps lstart), elapsed (ps etime) }, menu (the battery menu's texts, in order) }
// own-cost.steps.js binds the energy scenario to that report. Nothing here asks the meter.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.join(__dirname, '..', '..');
const meterAx = path.join(root, '.build', 'release', 'meter-ax');
const dir = process.env.METER_CHECKS_DIR || path.join(os.homedir(), 'Library', 'Logs', 'menubar-meter-checks');
const INSTALLED = '/Applications/Meter.app/Contents/MacOS/Meter';

// pmset's log runs to megabytes.
const run = (file, args) => execFileSync(file, args, { encoding: 'utf8', maxBuffer: 1 << 28 });
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function stop(message) {
  console.error(`energy check: ${message}`);
  process.exit(1);
}

async function main() {
  if (!fs.existsSync(meterAx)) stop(`build the harness helpers first (npm run build:app): no ${meterAx}`);
  const power = run('pmset', ['-g', 'batt']).split('\n')[0];
  if (!/'Battery Power'/.test(power)) stop(`the Mac is not on battery (${power}); run this at the end of the day, before plugging in`);

  const row = run('ps', ['-axo', 'pid=,comm=']).split('\n').map((l) => /^\s*(\d+)\s+(.+)$/.exec(l))
    .find((m) => m && m[2] === INSTALLED);
  if (!row) stop(`the installed meter (${INSTALLED}) is not running`);
  const pid = Number(row[1]);
  const meter = {
    program: INSTALLED,
    pid,
    started: run('ps', ['-o', 'lstart=', '-p', String(pid)]).trim().replace(/\s+/g, ' '),
    elapsed: run('ps', ['-o', 'etime=', '-p', String(pid)]).trim(),
  };
  const powerLog = run('pmset', ['-g', 'log']).split('\n').filter((l) => /Using (AC|Batt)/.test(l)).slice(-400);

  const controlCenter = Number(run('pgrep', ['-x', 'ControlCenter']).trim().split('\n')[0]);
  const items = JSON.parse(run(meterAx, ['item', String(controlCenter)]));
  const battery = items.find((i) => /^Battery/.test(i.title));
  if (!battery) stop(`no battery item in the menu bar: ${JSON.stringify(items.map((i) => i.title))}`);
  const texts = () => JSON.parse(run(meterAx, ['texts', String(controlCenter)]));
  if (texts().length > 0) stop('a Control Center menu is already open; close it and run this again');

  run(meterAx, ['press-item', String(controlCenter), battery.title]);
  let menu = [];
  try {
    const deadline = Date.now() + 10000;
    // The menu fills in a moment after it opens: read until its energy section shows.
    while (Date.now() < deadline) {
      await sleep(250);
      menu = texts();
      if (menu.some((t) => /^(No )?Apps Using Significant Energy$/.test(t))) break;
    }
    await sleep(500);
    menu = texts();
  } finally {
    run(meterAx, ['press-item', String(controlCenter), battery.title]);
    // The menu takes a moment to go.
    const closedBy = Date.now() + 3000;
    while (texts().length > 0 && Date.now() < closedBy) await sleep(100);
    if (texts().length > 0) console.error('energy check: the battery menu is still open; click elsewhere to close it');
  }
  if (!menu.some((t) => /^(No )?Apps Using Significant Energy$/.test(t))) {
    console.error('energy check: the menu showed no energy section this time; the report will not pass. Run it again.');
  }

  const report = { at: Date.now() / 1000, power, powerLog, meter, menu };
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'energy-report.json');
  fs.writeFileSync(file, `${JSON.stringify(report, null, 2)}\n`);
  console.log(`energy check: wrote ${file}`);
  console.log(`the battery menu read: ${JSON.stringify(menu)}`);
}

main().catch((error) => stop(error.stack || String(error)));
