'use strict';
// The reports of the two checks that run on the user's own installed meter in normal use, outside
// the harness (docs/P7-SOAK-AND-ENERGY.md): the seven-day memory soak (D76) and the battery menu
// read after a day on battery (D75). Each holds what macOS's own tools read of the installed
// meter (ps, footprint, pmset, the battery menu through Accessibility), never anything the meter
// wrote. Until a report exists, the steps that read it are not bound and the row stays in wip.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const dir = process.env.METER_CHECKS_DIR || path.join(os.homedir(), 'Library', 'Logs', 'menubar-meter-checks');
const soakReportFile = path.join(dir, 'soak-report.ndjson');
const energyReportFile = path.join(dir, 'energy-report.json');

/** The installed release meter's program, the only one the checks read. */
const INSTALLED = '/Applications/Meter.app/Contents/MacOS/Meter';

/** The soak report's samples, oldest first, or null when the soak has not reported. */
function soakReport() {
  if (!fs.existsSync(soakReportFile)) return null;
  return fs.readFileSync(soakReportFile, 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l));
}

/** The battery-menu report, or null when none has been taken. */
function energyReport() {
  if (!fs.existsSync(energyReportFile)) return null;
  return JSON.parse(fs.readFileSync(energyReportFile, 'utf8'));
}

/** `ps -o lstart=` text ("Thu Oct 22 00:42:30 2026") as epoch seconds, in local time. */
function lstartSeconds(text) {
  const m = /^\w{3} (\w{3})\s+(\d{1,2}) (\d{2}):(\d{2}):(\d{2}) (\d{4})$/.exec(String(text).trim());
  if (!m) throw new Error(`not a ps start time: "${text}"`);
  const month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].indexOf(m[1]);
  return new Date(Number(m[6]), month, Number(m[2]), Number(m[3]), Number(m[4]), Number(m[5])).getTime() / 1000;
}

/** A `pmset -g log` line's timestamp ("2026-10-21 21:39:37 -0700 ...") as epoch seconds. */
function pmsetSeconds(line) {
  const m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})/.exec(line);
  if (!m) return null;
  const utc = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
  const offset = (Number(m[8]) * 60 + Number(m[9])) * 60000 * (m[7] === '-' ? -1 : 1);
  return (utc - offset) / 1000;
}

module.exports = {
  dir, soakReportFile, energyReportFile, INSTALLED, soakReport, energyReport, lstartSeconds, pmsetSeconds,
};
