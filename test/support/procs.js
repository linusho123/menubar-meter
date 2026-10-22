'use strict';
// Processes the harness starts, and the only processes it ever ends. Each is identified by
// pid and start time (to the second, as `ps -o lstart` shows it, backed by the child's exit
// event); before a signal the harness checks both still match, so a reused pid can never
// receive it.
const { spawn, execFileSync } = require('node:child_process');

function startTimeOf(pid) {
  try {
    return execFileSync('ps', ['-o', 'lstart=', '-p', String(pid)], { encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
}

const ownedProcesses = [];

/**
 * Pids of running meters (any copy of Meter.app) that neither the harness started nor are in
 * `allowed` (the pids of the install it manages). Another meter would hold the shortcut and
 * make a count of meters wrong.
 */
function foreignMeters(allowed = []) {
  const live = new Set(ownedProcesses.filter(isRunning).map((o) => o.pid));
  const out = execFileSync('ps', ['-axo', 'pid=,comm='], { encoding: 'utf8' });
  return out.split('\n').map((l) => /^\s*(\d+)\s+(.+)$/.exec(l))
    .filter((m) => m && /\/Meter\.app\/Contents\/MacOS\/Meter$/.test(m[2]))
    .map((m) => Number(m[1]))
    .filter((pid) => !live.has(pid) && !allowed.includes(pid));
}

/** Spawns a process the harness owns. */
function start(file, args = [], options = {}) {
  const child = spawn(file, args, { stdio: ['ignore', 'pipe', 'pipe'], ...options });
  if (!child.pid) throw new Error(`could not start ${file}`);
  const started = startTimeOf(child.pid);
  if (!started) throw new Error(`${file} (pid ${child.pid}) exited at once`);
  const owned = { child, pid: child.pid, started, file, exited: false };
  ownedProcesses.push(owned);
  child.on('exit', () => { owned.exited = true; });
  return owned;
}

function isRunning(owned) {
  return !owned.exited && startTimeOf(owned.pid) === owned.started;
}

/** Ends a process the harness started, after checking pid and start time still match. */
async function end(owned) {
  if (!isRunning(owned)) return;
  owned.child.kill('SIGTERM');
  for (let i = 0; i < 50 && isRunning(owned); i++) await sleep(100);
  if (isRunning(owned)) owned.child.kill('SIGKILL');
  for (let i = 0; i < 50 && isRunning(owned); i++) await sleep(100);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = { foreignMeters, start, end, isRunning, sleep, startTimeOf };
