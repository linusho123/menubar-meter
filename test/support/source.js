'use strict';
// The test-only reading source, fed by Givens and Whens. It holds RAW inputs
// in the shapes macOS itself returns (CPU ticks, vm_statistics64 page counts,
// IOAccelerator's PerformanceStatistics, HID temperature sensors), so the
// meter's own derivation still runs on them. No Then ever reads this file.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const GiB = 2 ** 30;
const PAGE = 16384;
const TICKS = 10000; // CPU ticks per pass: fine enough for 0.01% steps
// This Mac's memory-tagging region, as vm_statistics64 reports it.
const TAG_STORAGE = 65536;
const TAG_STORING = 7300;

function physicalBytes() {
  return Number(execFileSync('sysctl', ['-n', 'hw.memsize'], { encoding: 'utf8' }).trim());
}

/** CPU busy share → per-pass ticks; `system` and `user` as Activity Monitor splits them. */
function cpuTicks({ user, system }) {
  const u = Math.round(user * TICKS / 100);
  const s = Math.round(system * TICKS / 100);
  if (u + s > TICKS) throw new Error(`CPU over 100%: ${user} + ${system}`);
  return { user: u, system: s, nice: 0, idle: TICKS - u - s };
}

/**
 * Page counts whose Activity Monitor Memory Used is `usedBytes`, split over
 * App Memory, Wired, Compressed and the tagging region, with reusable cache
 * (file-backed and purgeable pages) held besides in most of what is left.
 */
function vmPages(usedBytes) {
  const physPages = Math.floor(physicalBytes() / PAGE);
  let used = Math.round(usedBytes / PAGE);
  let tagStorage = 0;
  let tagStoring = 0;
  if (used >= TAG_STORAGE + TAG_STORING) { tagStorage = TAG_STORAGE; tagStoring = TAG_STORING; used -= TAG_STORAGE + TAG_STORING; }
  const wired = Math.floor(used * 0.15);
  const compressor = Math.floor(used * 0.10);
  const app = used - wired - compressor;
  const room = Math.max(0, physPages - Math.round(usedBytes / PAGE));
  const cache = Math.floor(room * 0.8);
  const purgeable = Math.floor(cache * 0.1);
  const external = cache - purgeable;
  return {
    pageSize: PAGE, internal: app + purgeable, purgeable, external, wired, compressor,
    tagStorage, tagStoring,
  };
}

/** IOAccelerator's statistics with `device` as Device Utilization %, other figures distinct from it. */
function gpuStats(device) {
  return {
    'Device Utilization %': device,
    'Renderer Utilization %': (device + 37) % 101,
    'Tiler Utilization %': (device + 13) % 101,
    'recoveryCount': 0,
  };
}

/** HID temperature sensors whose hottest die sensor is `celsius`, among sensors that are not the die. */
function sensors(celsius) {
  return {
    'PMU tdie1': celsius - 1.25,
    'PMU tdie6': celsius,
    'PMU tdie9': celsius - 2.5,
    'PMU2 tdie3': celsius - 3.75,
    'PMU tcal': 51.82,
    'PMU tdev2': celsius + 4.5,
    'PMU tdev1': -22.13,
    'gas gauge battery': 27.7,
    'NAND CH0 temp': 30,
  };
}

class TestSource {
  constructor() {
    this.dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-source-'));
    this.file = path.join(this.dir, 'source.json');
    // A plausible, unremarkable Mac until a Given says otherwise.
    this.doc = {};
    this.set('CPU', 20).set('GPU', 10).set('RAM', 40).set('temperature', 45);
  }

  /** Set one reading as Activity Monitor / macOS would show it. */
  set(reading, value) {
    switch (reading) {
      case 'CPU': this.doc.cpuTicksPerPass = cpuTicks({ user: value, system: 0 }); break;
      case 'GPU': this.doc.gpu = gpuStats(value); break;
      case 'RAM': this.doc.vm = vmPages(physicalBytes() * value / 100); break;
      case 'temperature': this.doc.sensors = sensors(value); break;
      default: throw new Error(`unknown reading ${reading}`);
    }
    return this;
  }

  setCpuSplit(user, system) { this.doc.cpuTicksPerPass = cpuTicks({ user, system }); return this; }
  setMemoryUsed(bytes) { this.doc.vm = vmPages(bytes); return this; }

  /** No fresh reading arrives for this input from now on. */
  gap(reading) {
    const key = { CPU: 'cpuTicksPerPass', GPU: 'gpu', RAM: 'vm', temperature: 'sensors' }[reading];
    if (!key) throw new Error(`unknown reading ${reading}`);
    this.doc[key] = null;
    return this;
  }

  /** Write atomically, so the meter never reads half a file. */
  write() {
    const tmp = this.file + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(this.doc));
    fs.renameSync(tmp, this.file);
    return Date.now();
  }

  remove() { fs.rmSync(this.dir, { recursive: true, force: true }); }
}

module.exports = { TestSource, physicalBytes, GiB };
