'use strict';
// The meter against the real system, checked by macOS's own tools (top, vm_stat, ioreg), and
// the test reading source checked absent from the release app. These back the scenarios that
// inject their Givens; they never stand in for a scenario.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const paths = require('./support/paths');
const procs = require('./support/procs');
const menubar = require('./support/menubar');
const probes = require('./support/probes');
const { Feed, readings } = require('./support/feed');

async function withRealMeter(env, body) {
  const meter = procs.start(paths.releaseApp, [], { env: { ...process.env, ...env } });
  try {
    await menubar.waitForItem(meter.pid, (i) => !!menubar.fields(i.title), 10000, 'the meter');
    await procs.sleep(1500);
    await body(meter);
  } finally {
    await procs.end(meter);
  }
}

const value = (title, reading) => Number.parseInt(menubar.fields(title)[reading], 10);
const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;

test('the release app has no test reading source compiled in', () => {
  const release = fs.readFileSync(paths.releaseApp);
  const testBuild = fs.readFileSync(paths.testApp);
  // The test source's type and its feed field, by their names in the Swift metadata.
  for (const marker of ['10TestInputs', 'feedPath']) {
    assert.ok(testBuild.includes(marker), `the test app carries the test source (${marker})`);
    assert.ok(!release.includes(marker), `the release app does not (${marker})`);
  }
});

test('the release app ignores a feed and reads the real Mac', async () => {
  const feed = new Feed();
  feed.set(readings({ cpu: 100, gpu: 100, ram: 100, temp: 123 }));
  try {
    await withRealMeter({ METER_TEST_FEED: feed.file }, async (meter) => {
      const [item] = menubar.itemsOf(meter.pid);
      assert.notStrictEqual(menubar.fields(item.title).temperature, '123°C');
    });
  } finally {
    feed.remove();
  }
});

test('the real readings agree with top, vm_stat and ioreg', async () => {
  const cores = probes.cpuCount();
  const half = Math.round(cores / 2);
  const load = procs.start(process.execPath, [path.join(__dirname, 'support', 'load.js'), String(half)]);
  try {
    await procs.sleep(3000);
    await withRealMeter({}, async (meter) => {
      const watcher = await menubar.watch(meter.pid, 2600);
      const top = probes.topCpu();
      const memoryUsed = probes.vmStatMemoryUsed();
      const gpu = probes.ioregGpu();
      await watcher.done;
      const titles = watcher.seen.map((s) => s.title).filter((t) => menubar.fields(t));
      const cpu = mean(titles.map((t) => value(t, 'CPU')).filter(Number.isFinite));
      assert.ok(Math.abs(cpu - (top.user + top.system)) <= 12,
        `meter CPU ${cpu.toFixed(1)}% vs top User + System ${(top.user + top.system).toFixed(1)}%`);
      const ram = value(titles[titles.length - 1], 'RAM');
      const vmStat = (memoryUsed / probes.memsize()) * 100;
      assert.ok(Math.abs(ram - vmStat) <= 2, `meter RAM ${ram}% vs vm_stat Memory Used ${vmStat.toFixed(1)}%`);
      assert.notStrictEqual(gpu, null, 'ioreg reports a GPU utilization');
      const gpus = titles.map((t) => value(t, 'GPU')).filter(Number.isFinite);
      assert.ok(gpus.some((g) => Math.abs(g - gpu) <= 15), `meter GPU ${gpus} vs ioreg ${gpu}%`);
      const temperature = value(titles[titles.length - 1], 'temperature');
      assert.ok(temperature >= 20 && temperature <= 110, `a believable chip temperature: ${temperature}°C`);
    });
  } finally {
    await procs.end(load);
  }
});

test('the panel\'s legend agrees with vm_stat on the real Mac', async () => {
  const panel = require('./support/panel');
  await withRealMeter({}, async (meter) => {
    const capture = await panel.clickAndCapture(meter.pid);
    const vmStat = (probes.vmStatMemoryUsed() / probes.memsize()) * 100;
    const ram = panel.legendValue(capture, 'RAM');
    assert.ok(Math.abs(ram - vmStat) <= 2, `legend RAM ${ram}% vs vm_stat Memory Used ${vmStat.toFixed(1)}%`);
    assert.match(panel.legend(capture).text, /^CPU \d+\.\d%  GPU \d+\.\d%  RAM \d+\.\d%$/);
  });
});

/** A panel line's two rate texts ("Net ↓ 112.4 MB/s ↑ 300.0 KB/s"), or null when it is not one. */
function lineTexts(text, label) {
  const unit = '(\\d+\\.\\d [KMG]B/s)';
  const m = new RegExp(`^${label} \\S+ ${unit} \\S+ ${unit}$`, 'u').exec(text || '');
  return m ? [m[1], m[2]] : null;
}

/**
 * A real, paced transfer on this Mac while the panel is open, compared with what netstat and
 * ioreg count over the same seconds. Three streams: 20 MB/s, whose mean must match the system's to
 * 2% on the network (a 1024 prefix is 4.7% off there); and 1.01 MB/s, just over the step from KB
 * to MB, where a step at 1024 (or 300) leaves a reading such as `1005.0 KB/s` that the decimal
 * reference formatter would write otherwise. Above 1 MB/s the text has one decimal, so that stream's
 * bound is half a step (50 KB/s) and cannot see a 1024 prefix (24 KB/s low); the 0.9 MB/s stream
 * reads in KB/s to a tenth, and its bound is 1.5% of the system's own count plus 2 KB/s (about
 * 16 KB/s) against a 1024 prefix's 22 KB/s. Bounds follow netstat's count, not the nominal pace.
 */
/** The system's counters and the moment they were read (the middle of the reads). */
function snapshot() {
  const before = Date.now();
  const net = probes.netstatBytes();
  const disk = probes.ioregDiskBytes();
  return { net, disk, at: (before + Date.now()) / 2 };
}

const STREAMS = [
  { name: '20 MB/s', net: 20e6, tolerance: 0.02, floor: 60e3 },
  { name: '1.01 MB/s', net: 1.01e6, tolerance: 0.005, floor: 50e3 },
  { name: '0.9 MB/s', net: 0.9e6, tolerance: 0.015, floor: 2e3 },
];

for (const stream of STREAMS) {
  test(`the panel's network and disk lines agree with netstat and ioreg under a real transfer, ${stream.name}`,
    async () => {
      const panel = require('./support/panel');
      const rates = require('./support/rates');
      const os = require('node:os');
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-transfer-'));
      const MB = 1e6;
      try {
        await withRealMeter({}, async (meter) => {
          await panel.click(meter.pid);
          // Loopback traffic (Activity Monitor counts lo0, as measured) and uncached disk reads and
          // writes, each at a steady rate, for 10 s, in a temporary folder.
          const transfer = procs.start('python3', ['-I', path.join(__dirname, 'support', 'transfer.py'),
            '10', String(stream.net), String(8 * MB), String(6 * MB), dir]);
          try {
            await procs.sleep(3500);
            const watcher = await panel.watchTexts(meter.pid, 4000);
            // The counters are read as the watcher shows its first reading and as it ends, so
            // the system's rates and the panel's mean span the same seconds.
            const first = snapshot();
            await watcher.done;
            const last = snapshot();
            const t0 = first.at;
            const t1 = last.at;
            const net0 = first.net;
            const net1 = last.net;
            const disk0 = first.disk;
            const disk1 = last.disk;
            const seconds = (t1 - t0) / 1000;
            const probe = {
              Net: [(net1.received - net0.received) / seconds, (net1.sent - net0.sent) / seconds],
              Disk: [(disk1.read - disk0.read) / seconds, (disk1.written - disk0.written) / seconds],
            };
            for (const label of ['Net', 'Disk']) {
              const texts = watcher.seen.map((s) => ({
                at: s.at, pair: lineTexts(panel.lineStarting(s.texts, `${label} `), label) }));
              const shown = texts.filter((t) => t.pair);
              assert.ok(shown.length >= 3, `the ${label} line was read: ${JSON.stringify(watcher.seen.at(-1))}`);
              // Every reading is written as the decimal reference writes its value.
              for (const t of shown) {
                for (const text of t.pair) {
                  assert.ok(rates.canonical(text), `${label} reads "${text}", which the decimal step at a thousand writes ${rates.format(rates.parse(text))}`);
                }
              }
              for (const i of [0, 1]) {
                const ours = rates.weightedMean(
                  texts.map((t) => ({ at: Math.max(t.at, t0), value: t.pair ? rates.parse(t.pair[i]) : null })), t1);
                const theirs = probe[label][i];
                const allowed = label === 'Net' ? stream.tolerance * theirs + stream.floor : 0.25 * theirs + 0.5 * MB;
                assert.ok(Math.abs(ours - theirs) <= allowed,
                  `${label} ${i ? 'second' : 'first'} value: the panel reads ${(ours / MB).toFixed(3)} MB/s, `
                  + `the system counted ${(theirs / MB).toFixed(3)} MB/s`);
              }
            }
            // The transfer itself shows: loopback counted, reads and writes counted.
            assert.ok(probe.Net[0] >= 0.8 * stream.net && probe.Disk[0] >= 5 * MB && probe.Disk[1] >= 4 * MB,
              `a non-idle transfer: ${JSON.stringify(probe)}`);
          } finally {
            await procs.end(transfer);
          }
        });
      } finally {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    });
}
