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

/** A panel line's two rates ("Net ↓ 112.4 MB/s ↑ 0.3 MB/s") in bytes a second, decimal prefixes. */
function lineRates(text, label) {
  const unit = '(\\d+\\.\\d) (KB|MB|GB)/s';
  const m = new RegExp(`^${label} ${unit} \\S+ ${unit}$`, 'u').exec(text || '');
  if (!m) return null;
  const scale = { KB: 1e3, MB: 1e6, GB: 1e9 };
  return [Number(m[1]) * scale[m[2]], Number(m[3]) * scale[m[4]]];
}

test('the panel\'s network and disk lines agree with netstat and ioreg under a real transfer', async () => {
  const panel = require('./support/panel');
  const os = require('node:os');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-transfer-'));
  const MB = 1e6;
  try {
    await withRealMeter({}, async (meter) => {
      await panel.click(meter.pid);
      // Loopback traffic (Activity Monitor counts lo0, as measured) and uncached disk reads and
      // writes, each at a steady rate, for 10 s: about 300 MB in all, in a temporary folder.
      const transfer = procs.start('python3', ['-I', path.join(__dirname, 'support', 'transfer.py'),
        '10', String(20 * MB), String(8 * MB), String(6 * MB), dir]);
      try {
        await procs.sleep(3500);
        const net0 = probes.netstatBytes();
        const disk0 = probes.ioregDiskBytes();
        const t0 = Date.now();
        const watcher = panel.watchTexts(meter.pid, 4000);
        await watcher.done;
        const net1 = probes.netstatBytes();
        const disk1 = probes.ioregDiskBytes();
        const seconds = (Date.now() - t0) / 1000;
        const probe = {
          Net: [(net1.received - net0.received) / seconds, (net1.sent - net0.sent) / seconds],
          Disk: [(disk1.read - disk0.read) / seconds, (disk1.written - disk0.written) / seconds],
        };
        for (const label of ['Net', 'Disk']) {
          const read = watcher.seen.map((s) => lineRates(panel.lineStarting(s.texts, `${label} `), label))
            .filter(Boolean);
          assert.ok(read.length >= 5, `the ${label} line was read: ${JSON.stringify(watcher.seen.at(-1))}`);
          for (const i of [0, 1]) {
            const ours = mean(read.map((r) => r[i]));
            const theirs = probe[label][i];
            assert.ok(Math.abs(ours - theirs) <= 0.25 * theirs + 0.5 * MB,
              `${label} ${i ? 'second' : 'first'} value: the panel reads ${(ours / MB).toFixed(2)} MB/s, `
              + `the system counted ${(theirs / MB).toFixed(2)} MB/s`);
          }
        }
        // The transfer itself shows: loopback counted, reads and writes counted.
        assert.ok(probe.Net[0] >= 15 * MB && probe.Disk[0] >= 5 * MB && probe.Disk[1] >= 4 * MB,
          `a non-idle transfer: ${JSON.stringify(probe)}`);
      } finally {
        await procs.end(transfer);
      }
    });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
