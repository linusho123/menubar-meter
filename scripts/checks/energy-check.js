'use strict';
// The battery-menu read for "never an energy hog" (D75, Q3), run by the user at the end of a day
// on battery (docs/P7-SOAK-AND-ENERGY.md): `node scripts/checks/energy-check.js`. It checks the
// Mac is on battery and the installed meter is running, runs a positive control (a stand-in app of
// the harness's own, busy on two cores, ended by its pid and start time when done), opens the
// battery menu through Accessibility (meter-ax, as an assistive app presses a menu bar item; the
// pointer never moves), reads every element in it until the control is listed (up to 5 minutes),
// closes it again and writes energy-report.json with what macOS showed:
//   { at, power (pmset -g batt),
//     powerLog (pmset -g log, from its last "Using AC" line to the end: the power-source lines and
//               the Sleep/Wake/DarkWake lines, for the awake hours of the battery day),
//     meter: { program, pid, started (ps lstart), elapsed (ps etime), version, sha (of the
//              executable), live: { stat1, time1, stat2, time2 (ps, 10 s apart), ax (its status
//              item's title through Accessibility) } },
//     meterAfter: { pid, started } (the same meter, read again once the menu is closed),
//     menu (the Control Center windows as meter-ax prints them: every element's role and text),
//     control: { name, seen (listed under the energy section), tries } }
// own-cost.steps.js binds the energy scenario to that report. Nothing here asks the meter.
// METER_ENERGY_ALLOW_AC=1 lets the control be tried off battery; such a report fails its Given.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawn } = require('node:child_process');

const root = path.join(__dirname, '..', '..');
const meterAx = path.join(root, '.build', 'release', 'meter-ax');
const standIn = path.join(root, '.build', 'release', 'meter-standin');
const dir = process.env.METER_CHECKS_DIR || path.join(os.homedir(), 'Library', 'Logs', 'menubar-meter-checks');
const INSTALLED = process.env.METER_ENERGY_PROGRAM || '/Applications/Meter.app/Contents/MacOS/Meter';
const CONTROL_NAME = 'EnergyControl';
const CONTROL_SECONDS = Number(process.env.METER_ENERGY_CONTROL_SECONDS) || 300;

// pmset's log runs to megabytes.
const run = (file, args) => execFileSync(file, args, { encoding: 'utf8', maxBuffer: 1 << 28 });
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const squeeze = (text) => text.trim().replace(/\s+/g, ' ');

function stop(message) {
  console.error(`energy check: ${message}`);
  process.exit(1);
}

const SECTION = /(?:^|\b)(?:No )?(?:Apps )?Using Significant Energy$/i;
const EVENT = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4} (Sleep|Wake|DarkWake)(?: {2,}|\t)/;

/** pmset's log from its last "Using AC" line to the end: power-source lines and sleep/wake lines. */
function powerLogLines() {
  const lines = run('pmset', ['-g', 'log']).split('\n').filter((l) => /Using (AC|Batt)/i.test(l) || EVENT.test(l));
  let lastAC = -1;
  lines.forEach((l, i) => { if (/Using AC/i.test(l)) lastAC = i; });
  return lastAC < 0 ? lines : lines.slice(lastAC);
}

function installedMeter() {
  const row = run('ps', ['-axo', 'pid=,comm=']).split('\n').map((l) => /^\s*(\d+)\s+(.+)$/.exec(l))
    .find((m) => m && m[2] === INSTALLED);
  if (!row) stop(`the installed meter (${INSTALLED}) is not running`);
  const pid = Number(row[1]);
  const plist = path.join(INSTALLED, '..', '..', 'Info.plist');
  return {
    program: INSTALLED,
    pid,
    started: squeeze(run('ps', ['-o', 'lstart=', '-p', String(pid)])),
    elapsed: squeeze(run('ps', ['-o', 'etime=', '-p', String(pid)])),
    version: run('plutil', ['-extract', 'CFBundleShortVersionString', 'raw', plist]).trim(),
    sha: run('shasum', ['-a', '256', INSTALLED]).split(/\s+/)[0],
  };
}

const statTime = (pid) => {
  const [stat, time] = squeeze(run('ps', ['-o', 'stat=,time=', '-p', String(pid)])).split(' ');
  return { stat, time };
};

/** The positive control: a stand-in app of the harness's own, busy on two cores. */
function startControl() {
  if (!fs.existsSync(standIn)) stop(`build the harness helpers first (npm run build:app): no ${standIn}`);
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-energy-control-'));
  const app = path.join(base, `${CONTROL_NAME}.app`);
  fs.mkdirSync(path.join(app, 'Contents', 'MacOS'), { recursive: true });
  const file = path.join(app, 'Contents', 'MacOS', CONTROL_NAME);
  fs.copyFileSync(standIn, file);
  fs.chmodSync(file, 0o755);
  fs.writeFileSync(path.join(app, 'Contents', 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>${CONTROL_NAME}</string>
<key>CFBundleIdentifier</key><string>local.menubar-meter.energycontrol</string>
<key>CFBundleName</key><string>${CONTROL_NAME}</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><false/>
</dict></plist>
`);
  try { execFileSync('codesign', ['--force', '--sign', '-', app], { stdio: 'ignore' }); } catch { /* unsigned still runs */ }
  const child = spawn(file, [path.join(base, 'record'), path.join(base, 'control'), '2'], { stdio: 'ignore' });
  const started = squeeze(run('ps', ['-o', 'lstart=', '-p', String(child.pid)]));
  return {
    pid: child.pid,
    end() {
      // Only the process this run started: same pid, same start time, same program.
      try {
        const now = squeeze(run('ps', ['-o', 'lstart=', '-p', String(child.pid)]));
        const comm = run('ps', ['-o', 'comm=', '-p', String(child.pid)]).trim();
        if (now === started && comm === file) child.kill('SIGKILL');
      } catch { /* already gone */ }
      fs.rmSync(base, { recursive: true, force: true });
    },
  };
}

async function main() {
  if (!fs.existsSync(meterAx)) stop(`build the harness helpers first (npm run build:app): no ${meterAx}`);
  const power = run('pmset', ['-g', 'batt']).split('\n')[0];
  if (!/'Battery Power'/.test(power) && process.env.METER_ENERGY_ALLOW_AC !== '1') {
    stop(`the Mac is not on battery (${power}); run this at the end of the day, before plugging in`);
  }

  const meter = installedMeter();
  const powerLog = powerLogLines();

  const controlCenter = Number(run('pgrep', ['-x', 'ControlCenter']).trim().split('\n')[0]);
  const items = JSON.parse(run(meterAx, ['item', String(controlCenter)]));
  const battery = items.find((i) => /^Battery/.test(i.title));
  if (!battery) stop(`no battery item in the menu bar: ${JSON.stringify(items.map((i) => i.title))}`);
  const texts = () => JSON.parse(run(meterAx, ['texts', String(controlCenter)]));
  if (texts().length > 0) stop('a Control Center menu is already open; close it and run this again');

  const control = startControl();
  let menu = [];
  let seen = false;
  let tries = 0;
  const closeMenu = async () => {
    run(meterAx, ['press-item', String(controlCenter), battery.title]);
    // The menu takes a moment to go.
    const closedBy = Date.now() + 3000;
    while (texts().length > 0 && Date.now() < closedBy) await sleep(100);
    if (texts().length > 0) console.error('energy check: the battery menu is still open; click elsewhere to close it');
  };
  const onExit = () => control.end();
  process.on('SIGINT', () => { control.end(); process.exit(130); });
  try {
    // Read the menu until the control shows in its energy section (it can take a few minutes for
    // macOS to call a busy app significant), for up to CONTROL_SECONDS.
    const deadline = Date.now() + CONTROL_SECONDS * 1000;
    do {
      tries++;
      run(meterAx, ['press-item', String(controlCenter), battery.title]);
      try {
        // The menu fills in a moment after it opens: read until its energy section shows.
        const until = Date.now() + 10000;
        while (Date.now() < until) {
          await sleep(250);
          if (JSON.parse(run(meterAx, ['windows', String(controlCenter)])).some((w) => w.elements.some((e) => SECTION.test(String(e.text || ''))))) break;
        }
        await sleep(1500);
        menu = JSON.parse(run(meterAx, ['windows', String(controlCenter)]));
      } finally {
        await closeMenu();
      }
      const apps = menu.flatMap((w) => w.elements).filter((e) => e.text).map((e) => e.text);
      seen = apps.includes(CONTROL_NAME);
      if (!seen && Date.now() < deadline) await sleep(20000);
    } while (!seen && Date.now() < deadline);
  } finally {
    onExit();
  }
  // Two ps reads 10 s apart, with Accessibility answering, show the meter alive.
  const first = statTime(meter.pid);
  await sleep(10000);
  const second = statTime(meter.pid);
  const title = (() => {
    try { return JSON.parse(run(meterAx, ['item', String(meter.pid)]))[0].title || ''; } catch { return ''; }
  })();
  meter.live = { stat1: first.stat, time1: first.time, stat2: second.stat, time2: second.time, ax: title };
  const after = installedMeter();

  if (!seen) console.error(`energy check: the control (${CONTROL_NAME}) was never listed in ${tries} read(s); the report will not pass. Run it again later in the day.`);
  const report = {
    at: Date.now() / 1000, power, powerLog, meter, meterAfter: { pid: after.pid, started: after.started }, menu,
    control: { name: CONTROL_NAME, seen, tries },
  };
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'energy-report.json');
  fs.writeFileSync(file, `${JSON.stringify(report, null, 2)}\n`);
  console.log(`energy check: wrote ${file}`);
  const apps = menu.flatMap((w) => w.elements).filter((e) => e.text && /^AX(Button|MenuItem)$/.test(e.role)).map((e) => e.text);
  console.log(`the battery menu's buttons: ${JSON.stringify(apps)}`);
}

main().catch((error) => stop(error.stack || String(error)));
