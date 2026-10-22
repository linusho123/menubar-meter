'use strict';
// The reports of the two checks that run on the user's own installed meter in normal use, outside
// the harness (docs/P7-SOAK-AND-ENERGY.md): the seven-day memory soak (D76) and the battery menu
// read after a day on battery (D75). Each holds what macOS's own tools read of the installed
// meter (ps, footprint, pmset, the battery menu through Accessibility), never anything the meter
// wrote. Until a report exists, the steps that read it are not bound and the row stays in wip.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cost = require('./cost');

const dir = process.env.METER_CHECKS_DIR || path.join(os.homedir(), 'Library', 'Logs', 'menubar-meter-checks');
const soakReportFile = path.join(dir, 'soak-report.ndjson');
const energyReportFile = path.join(dir, 'energy-report.json');

/** The version this build ships with (app/Info.plist): the one the reports must carry. */
function appVersion() {
  const text = fs.readFileSync(path.join(__dirname, '..', '..', 'app', 'Info.plist'), 'utf8');
  const m = /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/.exec(text);
  if (!m) throw new Error('app/Info.plist has no CFBundleShortVersionString');
  return m[1];
}

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

const DAY = 86400;
const MB = 1048576;
const SOAK_GAP = 20 * 60;
const SOAK_CPU_AFTER = 5 * 60;

/** Seconds a Mac was awake between two samples, from kern.sleeptime/kern.waketime (last sleep and wake). */
function awakeBetween(prev, cur) {
  if (!(cur.waketime > prev.at)) return cur.at - prev.at;
  return Math.max(0, cur.sleeptime - prev.at) + Math.max(0, cur.at - cur.waketime);
}

/**
 * Judges the seven-day soak report (a copy of every line of soak.sh from the process's first sample
 * to its seven-day one) against the P7 build `version`. { given, then, stats }: `given` holds what
 * makes it no soak of one P7 process for seven days (a restart, a hole, an older build, a frozen
 * meter), `then` what makes its memory fail (the max over every sample under 50.0 MB, no sustained
 * growth). A restart resets the count (the visionary's ruling, 2026-10-22): a different process, or
 * a line saying the meter was not running, anywhere in the window fails.
 */
function judgeSoak(report, { version, sevenDays = 7 * DAY } = {}) {
  const given = [];
  const then = [];
  const errors = report.filter((r) => r.error);
  const live = report.filter((r) => r.program && !r.error);
  const absent = report.filter((r) => r.program === null && !r.error);
  if (!live.length) return { given: ['the soak report holds no readings of the installed meter'], then, stats: { errors: errors.length } };
  const first = live[0];
  const last = live.at(-1);
  if (absent.length) {
    given.push(`the installed meter was not running at ${absent.length} reading(s), the first at ${new Date(absent[0].at * 1000).toISOString()}: a restart or a hole`);
  }
  const strangers = live.filter((s) => s.program !== INSTALLED);
  if (strangers.length) given.push(`the soak read a program that is not the installed meter: ${strangers[0].program}`);
  const other = live.find((s) => s.pid !== first.pid || s.started !== first.started);
  if (other) given.push(`one meter process, never restarted: pid ${first.pid} started ${first.started}, then pid ${other.pid} started ${other.started}`);
  const unversioned = live.filter((s) => s.version !== version);
  if (unversioned.length) given.push(`not the P7 build: version ${unversioned[0].version}, expected ${version}`);
  if (!first.sha || live.some((s) => s.sha !== first.sha)) given.push('the executable was not one build throughout (sha differs or is missing)');
  const bad = live.find((s) => !s.stat || /^[TZ]/.test(s.stat));
  if (bad) given.push(`the meter was in state ${bad.stat || 'unknown'} (stopped, zombie or not recorded) at ${new Date(bad.at * 1000).toISOString()}`);
  const uptime = last.at - lstartSeconds(first.started);
  if (!(uptime >= sevenDays)) given.push(`the process had run ${(uptime / DAY).toFixed(2)} days at its last reading: under 7 days`);
  let awake = 0;
  let cpuProblem = null;
  let gapProblem = null;
  for (let i = 1; i < live.length; i++) {
    const prev = live[i - 1];
    const cur = live[i];
    if (!Number.isFinite(cur.awake) || !Number.isFinite(prev.awake)) {
      gapProblem ||= 'readings lack the awake clock: sleep cannot be told from a hole';
      continue;
    }
    // The awake clock (CLOCK_UPTIME_RAW) stops while the Mac sleeps, darkwakes included, so its
    // difference is the time awake between the readings; going backwards is a reboot.
    const awakeSecs = cur.awake - prev.awake;
    if (awakeSecs < 0) {
      gapProblem ||= `the Mac restarted (the awake clock went back) at ${new Date(cur.at * 1000).toISOString()}: the meter's uptime ended`;
      continue;
    }
    if (awakeSecs > SOAK_GAP) {
      gapProblem ||= `an awake gap of ${(awakeSecs / 60).toFixed(0)} min with no reading, at ${new Date(prev.at * 1000).toISOString()} (the limit is 20 min)`;
    }
    awake += awakeSecs;
    if (awakeSecs >= SOAK_CPU_AFTER && !cpuProblem) {
      try {
        if (cost.cpuSeconds(cur.cpu) - cost.cpuSeconds(prev.cpu) < 0.01) {
          cpuProblem = `the meter's CPU time did not advance over ${(awakeSecs / 60).toFixed(0)} awake minutes at ${new Date(cur.at * 1000).toISOString()}`;
        }
      } catch (e) {
        cpuProblem = e.message;
      }
    }
  }
  if (gapProblem) given.push(gapProblem);
  if (cpuProblem) given.push(cpuProblem);

  const peak = live.reduce((a, b) => (b.footprint > a.footprint ? b : a));
  const stats = {
    samples: live.length, errors: errors.length, max: cost.shownMB(peak.footprint), maxAt: peak.at,
    day7: cost.shownMB(last.footprint), uptimeDays: uptime / DAY,
    awakeShare: last.at > first.at ? awake / (last.at - first.at) : 1,
  };
  if (!cost.underLine(peak.footprint)) then.push(`the highest reading in the week was ${stats.max} (at ${new Date(peak.at * 1000).toISOString()}), not under 50.0 MB`);
  const dayMax = (xs) => Math.max(...xs.map((s) => s.footprint));
  const firstDay = live.filter((s) => s.at - first.at < DAY);
  const lastDay = live.filter((s) => last.at - s.at < DAY);
  if (dayMax(lastDay) - dayMax(firstDay) > 5 * MB) {
    then.push(`memory grew: the highest reading was ${cost.shownMB(dayMax(firstDay))} on the first day and ${cost.shownMB(dayMax(lastDay))} on the last (more than 5 MB up)`);
  }
  return { given, then, stats };
}

/** All the elements of a `meter-ax windows` dump (an array of windows) or of a flat element list. */
function flatElements(dump) {
  if (!Array.isArray(dump)) return [];
  return dump.flatMap((x) => (x && Array.isArray(x.elements) ? x.elements : [x]));
}

const SECTION_HEADING = /^(?:No )?(?:Apps )?Using Significant Energy$/i;
const ROW_ROLES = new Set(['AXButton', 'AXMenuItem', 'AXStaticText', 'AXCheckBox', 'AXRadioButton', 'AXLink', 'AXMenuButton']);

/**
 * Reads the battery menu's energy section from a `meter-ax windows` dump of Control Center:
 * { state: 'none' | 'listed' | 'unreadable', apps }. The heading ("Using Significant Energy", or
 * "No Apps Using Significant Energy") is followed by one row per app, carried as a button or menu
 * item whose title, description or value is the app's name, up to the next heading or the
 * "Battery Settings…" button. A heading with no row readable, or no heading at all, is
 * unreadable: not the same as the meter not being listed.
 */
function energySection(dump) {
  const elements = flatElements(dump);
  const at = elements.findIndex((e) => SECTION_HEADING.test(String(e.text || '').trim()));
  if (at < 0) return { state: 'unreadable', apps: [], why: 'the menu shows no energy section' };
  if (/^No /i.test(elements[at].text.trim())) return { state: 'none', apps: [] };
  const apps = [];
  for (const e of elements.slice(at + 1)) {
    const text = String(e.text || '').trim();
    if (e.role === 'AXHeading' || /^Battery Settings/i.test(text)) break;
    if (ROW_ROLES.has(e.role) && text) apps.push(text);
  }
  return apps.length
    ? { state: 'listed', apps }
    : { state: 'unreadable', apps: [], why: 'the energy section is there but no app row is readable' };
}

const PMSET_EVENT = /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}) (Sleep|Wake|DarkWake)(?: {2,}|\t)/;

/**
 * How long the Mac has been on battery, from pmset's log lines (the whole span since the last
 * "Using AC" line, not a tail of the log): { state: 'ok' | 'unreadable', since, hours, sleptHours,
 * awakeHours }. Sleep runs from an "Entering Sleep" line to the next full "Wake" line (a DarkWake is
 * a maintenance wake and does not end it), and is taken out of the hours.
 */
function batteryDay(lines, at) {
  const power = lines.map((l, i) => ({ i, t: pmsetSeconds(l), ac: /Using AC/i.test(l), batt: /Using Batt/i.test(l) }));
  const lastAC = power.filter((p) => p.ac).at(-1);
  if (!lastAC) return { state: 'unreadable', why: 'pmset\'s log holds no "Using AC" line: the switch to battery cannot be dated' };
  const first = power.find((p) => p.i > lastAC.i && p.batt && p.t !== null);
  if (!first) return { state: 'unreadable', why: 'pmset\'s log shows no switch to battery after its last "Using AC" line' };
  const since = first.t;
  let slept = 0;
  let asleepFrom = null;
  for (const line of lines.slice(first.i)) {
    const m = PMSET_EVENT.exec(line);
    if (!m) continue;
    const t = pmsetSeconds(m[1]);
    if (m[2] === 'Sleep' && /Entering Sleep/.test(line) && asleepFrom === null) asleepFrom = Math.max(t, since);
    else if (m[2] === 'Wake' && asleepFrom !== null) {
      slept += Math.max(0, Math.min(t, at) - asleepFrom);
      asleepFrom = null;
    }
  }
  if (asleepFrom !== null) slept += Math.max(0, at - asleepFrom);
  const hours = (at - since) / 3600;
  return { state: 'ok', since, hours, sleptHours: slept / 3600, awakeHours: hours - slept / 3600 };
}

const ALL_DAY_HOURS = 6;

/**
 * Judges the battery-menu report (energy-check.js) against the P7 build `version`:
 * { given, when, then, problems, day, section, meterListed }. `given`: on battery for at least
 * 6 AWAKE hours (sleep taken out, per pmset's own lines), one installed P7 meter running since before
 * the switch and alive. `when`: the menu was readable and the menu was read properly (another app listed, or
 * macOS's explicit "No Apps Using Significant Energy"). `then`: the
 * meter is not among the listed apps.
 */
function judgeEnergy(report, { version, allDayHours = ALL_DAY_HOURS } = {}) {
  const given = [];
  const when = [];
  const then = [];
  if (!/'Battery Power'/.test(report.power || '')) given.push(`pmset: not on battery when the menu was read: ${report.power}`);
  const day = batteryDay(report.powerLog || [], report.at);
  if (day.state !== 'ok') given.push(`the battery day is unreadable: ${day.why}`);
  else {
    if (!(day.hours >= allDayHours)) given.push(`on battery ${day.hours.toFixed(1)} h before the read (all day: ${allDayHours} h or more)`);
    if (!(day.awakeHours >= allDayHours)) {
      given.push(`only ${day.awakeHours.toFixed(1)} awake hours on battery (${day.hours.toFixed(1)} h on battery, ${day.sleptHours.toFixed(1)} h asleep): all day is ${allDayHours} awake hours or more`);
    }
  }
  const meter = report.meter || {};
  if (meter.program !== INSTALLED) given.push('the installed meter was not the one read');
  if (meter.version !== version) given.push(`not the P7 build: the installed meter is version ${meter.version}, expected ${version}`);
  if (!meter.sha) given.push('the installed meter\'s executable sha is not recorded');
  if (day.state === 'ok' && meter.started) {
    if (!(lstartSeconds(meter.started) < day.since)) {
      given.push(`the meter (started ${meter.started}) was not running since before the Mac went on battery`);
    }
  }
  const after = report.meterAfter || {};
  if (after.pid !== meter.pid || after.started !== meter.started) given.push('the meter was replaced while the menu was read');
  const live = meter.live || {};
  if (/^[TZ]/.test(live.stat1 || 'X') || /^[TZ]/.test(live.stat2 || 'X')) given.push(`the meter was in state ${live.stat1}/${live.stat2} (stopped or zombie, or not recorded)`);
  try {
    if (cost.cpuSeconds(live.time2) - cost.cpuSeconds(live.time1) < 0.01) given.push('the meter\'s CPU time did not advance between two reads 10 s apart: a stopped or hung meter');
  } catch {
    given.push('the meter\'s CPU time was not recorded twice');
  }
  if (!live.ax) given.push('the meter did not answer Accessibility with a title');

  const section = energySection(report.menu);
  if (section.state === 'unreadable') when.push(`the battery menu's energy section was unreadable: ${section.why}`);
  // The stand-in control is optional (ruling 2026-10-22): the read is proved by another app listed,
  // or by macOS's own "No Apps Using Significant Energy"; neither seen is unreadable (above).
  const meterListed = section.apps.includes('Meter');
  if (meterListed) then.push(`the battery menu lists ${JSON.stringify(section.apps)}, Meter among them`);
  return { given, when, then, problems: [...given, ...when, ...then], day, section, meterListed };
}

module.exports = {
  judgeSoak, appVersion, energySection, batteryDay, judgeEnergy, flatElements, ALL_DAY_HOURS,
  dir, soakReportFile, energyReportFile, INSTALLED, soakReport, energyReport, lstartSeconds, pmsetSeconds,
};
