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
