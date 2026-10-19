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

/**
 * A past for the meter to have run through before it launches, given in ages (seconds before
 * the launch): a CPU, GPU and RAM level that holds unless a stretch sets another, and stretches
 * the Mac slept through. The test source drives the meter's own loop through it on the past's
 * own clock, so five minutes of history take no five minutes of waiting.
 */
class Past {
  constructor(seconds, levels = {}) {
    this.seconds = seconds;
    this.levels = { cpu: 5, gpu: 3, ram: 45, temp: 50, ...levels };
    this.stretches = [];
    this.sleeps = [];
  }

  /** `metric` is at `value` from `fromAge` seconds ago until `toAge` seconds ago (0 is now). */
  hold(metric, fromAge, toAge, value) {
    this.stretches.push({ metric, fromAge, toAge, value });
    return this;
  }

  /** The Mac slept from `fromAge` seconds ago until `toAge` seconds ago. */
  asleep(fromAge, toAge) {
    this.sleeps.push({ fromAge, toAge });
    return this;
  }

  level(metric, age) {
    let value = this.levels[metric];
    for (const s of this.stretches) {
      if (s.metric === metric && age <= s.fromAge && age >= s.toAge) value = s.value;
    }
    return value;
  }

  readingsAt(age) {
    return readings({
      cpu: this.level('cpu', age), gpu: this.level('gpu', age), ram: this.level('ram', age),
      temp: this.level('temp', age),
    });
  }

  /** The feed: the readings now, and the past as consecutive stretches ending now. */
  feed() {
    const ages = new Set([this.seconds, 0]);
    for (const s of [...this.stretches, ...this.sleeps]) {
      for (const age of [s.fromAge, s.toAge]) if (age > 0 && age < this.seconds) ages.add(age);
    }
    const bounds = [...ages].sort((a, b) => b - a);
    const past = [];
    for (let i = 0; i + 1 < bounds.length; i++) {
      const seconds = bounds[i] - bounds[i + 1];
      const middle = (bounds[i] + bounds[i + 1]) / 2;
      if (this.sleeps.some((s) => middle <= s.fromAge && middle >= s.toAge)) {
        past.push({ seconds, asleep: true });
      } else {
        const values = this.readingsAt(middle);
        delete values.cpu.since;
        past.push({ seconds, ...values });
      }
    }
    return { ...this.readingsAt(0), past };
  }
}

module.exports = {
  Feed, Past, readings, cpuLoad, cpuSplit, memoryAt, memoryUsedGB, gpuAt, sensorsAt,
  physicalMemory, pageSize, GiB,
};
