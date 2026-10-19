'use strict';
// Independent system probes: macOS's own tools, never the meter.
const { execFileSync } = require('node:child_process');

const run = (file, args) => execFileSync(file, args, { encoding: 'utf8' });

/** Whole-Mac CPU User and System from `top`, over one second. */
function topCpu() {
  const lines = run('top', ['-l', '2', '-n', '0', '-s', '1']).split('\n')
    .filter((l) => l.startsWith('CPU usage:'));
  const m = /([\d.]+)% user, ([\d.]+)% sys/.exec(lines[lines.length - 1]);
  return { user: Number(m[1]), system: Number(m[2]) };
}

/** Activity Monitor's Memory Used (app + wired + compressed) from `vm_stat`, in bytes. */
function vmStatMemoryUsed() {
  const out = run('vm_stat', []);
  const page = Number(/page size of (\d+) bytes/.exec(out)[1]);
  const field = (name) => Number(new RegExp(`${name}:\\s+(\\d+)`).exec(out)[1]);
  const app = field('Anonymous pages') - field('Pages purgeable');
  return (app + field('Pages wired down') + field('Pages occupied by compressor')) * page;
}

function memsize() {
  return Number(run('sysctl', ['-n', 'hw.memsize']).trim());
}

function cpuCount() {
  return Number(run('sysctl', ['-n', 'hw.ncpu']).trim());
}

/** macOS's overall GPU utilization as `ioreg` prints the accelerator's statistics. */
function ioregGpu() {
  const m = /"Device Utilization %"=(\d+)/.exec(run('ioreg', ['-r', '-d', '1', '-c', 'IOAccelerator']));
  return m ? Number(m[1]) : null;
}

/** A process's CPU use in percent of one core, as `ps` reports it. */
function psCpu(pid) {
  return Number(run('ps', ['-o', '%cpu=', '-p', String(pid)]).trim());
}

module.exports = { topCpu, vmStatMemoryUsed, memsize, cpuCount, ioregGpu, psCpu };
