'use strict';
// The test reading source's feed: raw inputs the sampler would otherwise read from the
// system. Givens write it; no Then ever reads it.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const sysctl = (name) => Number(execFileSync('sysctl', ['-n', name], { encoding: 'utf8' }).trim());
const physicalMemory = () => sysctl('hw.memsize');
const pageSize = () => sysctl('hw.pagesize');
const GiB = 2 ** 30;

/** Tenths of a percent, so every load the contract names is exact. */
const tenths = (percent) => Math.round(percent * 10);

/** A CPU load of `percent`, split between User and System, in effect from now. */
function cpuLoad(percent) {
  const total = tenths(percent);
  const user = Math.round(total * 0.7);
  return { user: user / 10, system: (total - user) / 10, since: Date.now() };
}

function cpuSplit(userPercent, systemPercent) {
  return { user: tenths(userPercent) / 10, system: tenths(systemPercent) / 10, since: Date.now() };
}

/** Page counts for a Memory Used of `usedBytes`, with reusable cache held besides. */
function memoryPages(usedBytes, cacheBytes) {
  const page = pageSize();
  const used = Math.round(usedBytes / page);
  const cache = Math.max(0, Math.round(cacheBytes / page));
  const wired = Math.round(used * 0.25);
  const compressed = Math.round(used * 0.2);
  const app = used - wired - compressed;
  const purgeable = Math.round(cache * 0.1);
  return { anonymous: app + purgeable, purgeable, wired, compressed, fileBacked: cache - purgeable };
}

/** Memory Used at `percent` of this Mac's physical memory, with cache besides. */
function memoryAt(percent) {
  const total = physicalMemory();
  const used = (total * percent) / 100;
  return memoryPages(used, Math.min(8 * GiB, Math.max(0, total - used - 0.05 * GiB)));
}

/** Memory Used as Activity Monitor writes it ("18.0 GB"), with cache besides. */
function memoryUsedGB(gb) {
  const used = gb * GiB;
  return memoryPages(used, Math.min(8 * GiB, Math.max(0, physicalMemory() - used - 0.05 * GiB)));
}

/** The GPU accelerator's statistics; only "Device Utilization %" is macOS's overall reading. */
function gpuAt(percent) {
  return {
    'Device Utilization %': percent,
    'Renderer Utilization %': (percent + 37) % 101,
    'Tiler Utilization %': (percent + 61) % 101,
  };
}

/** The temperature sensors, with the hottest die at `celsius` among other sensors. */
function sensorsAt(celsius) {
  return {
    'PMU tdie1': celsius - 0.3,
    'PMU tdie2': celsius,
    'PMU2 tdie1': celsius - 1.2,
    'PMU tdev1': -22.1,
    'PMU tcal': 51.8,
    'gas gauge battery': 29.3,
    'NAND CH0 temp': 30,
  };
}

class Feed {
  constructor() {
    this.dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-feed-'));
    this.file = path.join(this.dir, 'feed.json');
    this.values = {};
  }

  /** Sets readings (cpu, memory, gpu, sensors); `null` means no fresh reading arrives. */
  set(values) {
    this.values = { ...this.values, ...values };
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.values));
    fs.renameSync(tmp, this.file);
  }

  remove() {
    fs.rmSync(this.dir, { recursive: true, force: true });
  }
}

/** A full feed for readings given as the user reads them. */
function readings({ cpu, gpu, ram, temp }) {
  return { cpu: cpuLoad(cpu), gpu: gpuAt(gpu), memory: memoryAt(ram), sensors: sensorsAt(temp) };
}

module.exports = {
  Feed, readings, cpuLoad, cpuSplit, memoryAt, memoryUsedGB, gpuAt, sensorsAt,
  physicalMemory, pageSize, GiB,
};
