'use strict';
// Processes the harness starts, and the only processes it ever ends. Each is identified by
// pid AND start time; before a signal the harness checks both still match, so a reused pid
// can never receive it.
const { spawn, execFileSync } = require('node:child_process');

function startTimeOf(pid) {
  try {
    return execFileSync('ps', ['-o', 'lstart=', '-p', String(pid)], { encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
}

/** Spawns a process the harness owns. */
function start(file, args = [], options = {}) {
  const child = spawn(file, args, { stdio: ['ignore', 'pipe', 'pipe'], ...options });
  if (!child.pid) throw new Error(`could not start ${file}`);
  const started = startTimeOf(child.pid);
  if (!started) throw new Error(`${file} (pid ${child.pid}) exited at once`);
  const owned = { child, pid: child.pid, started, file, exited: false };
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

module.exports = { start, end, isRunning, sleep, startTimeOf };
