'use strict';
// Independent system probes: what macOS reports through its own tools,
// never anything the meter wrote.
const { execFileSync, execFile } = require('node:child_process');
const { promisify } = require('node:util');
const run = promisify(execFile);

/** `top`'s second sample (the first is since boot): {user, sys, idle} in %. */
async function topCpu() {
  const { stdout } = await run('top', ['-l', '2', '-n', '0', '-s', '1'], { encoding: 'utf8' });
  const lines = stdout.split('\n').filter((l) => l.startsWith('CPU usage:'));
  const m = /CPU usage: ([\d.]+)% user, ([\d.]+)% sys, ([\d.]+)% idle/.exec(lines.at(-1) || '');
  if (!m) throw new Error(`could not read top: ${lines.at(-1)}`);
  return { user: Number(m[1]), sys: Number(m[2]), idle: Number(m[3]) };
}

/** `vm_stat` page counts, by label. */
function vmStat() {
  const out = execFileSync('vm_stat', { encoding: 'utf8' });
  const pageSize = Number(/page size of (\d+) bytes/.exec(out)[1]);
  const pages = {};
  for (const line of out.split('\n')) {
    const m = /^"?([^":]+)"?:\s+(\d+)\.$/.exec(line.trim());
    if (m) pages[m[1]] = Number(m[2]);
  }
  return { pageSize, pages };
}

function physicalBytes() {
  return Number(execFileSync('sysctl', ['-n', 'hw.memsize'], { encoding: 'utf8' }).trim());
}

/** Activity Monitor's Memory Used, rebuilt from `vm_stat` by its definition. */
function memoryUsedBytes() {
  const { pageSize, pages } = vmStat();
  const app = pages['Anonymous pages'] - pages['Pages purgeable'];
  const tagging = (pages['Pages tag-storage'] || 0) + (pages['Pages tag-storage holding tags'] || 0);
  return (app + pages['Pages wired down'] + pages['Pages occupied by compressor'] + tagging) * pageSize;
}

/** macOS's overall GPU utilization as `ioreg` lists it. */
function gpuUtilization() {
  const out = execFileSync('ioreg', ['-r', '-d', '1', '-c', 'IOAccelerator', '-w0'], { encoding: 'utf8' });
  const all = [...out.matchAll(/"Device Utilization %"=(\d+)/g)].map((m) => Number(m[1]));
  if (all.length === 0) throw new Error('ioreg lists no IOAccelerator utilization');
  return Math.max(...all);
}

function cores() {
  return Number(execFileSync('sysctl', ['-n', 'hw.ncpu'], { encoding: 'utf8' }).trim());
}

/** A process's CPU use (% of one core) and command, as `ps` reports it. */
function psOf(pid) {
  try {
    const out = execFileSync('ps', ['-o', '%cpu=,comm=', '-p', String(pid)], { encoding: 'utf8' }).trim();
    const m = /^([\d.]+)\s+(.*)$/.exec(out);
    return m ? { cpu: Number(m[1]), command: m[2] } : null;
  } catch {
    return null;
  }
}

module.exports = { topCpu, vmStat, physicalBytes, memoryUsedBytes, gpuUtilization, cores, psOf };
