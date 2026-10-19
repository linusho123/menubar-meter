'use strict';
// menu-bar-readout.feature
//
// Givens (and the timing of Whens) may feed the meter's test-only reading
// source. Every Then reads only what macOS's Accessibility API reports the
// menu bar shows (via build/meter-harness), never the source file and never
// anything the meter writes about itself.
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { TestSource, physicalBytes, GiB } = require('../support/source');
const meter = require('../support/meter');
const menubar = require('../support/menubar');
const probes = require('../support/probes');
const { busyTask } = require('../support/load');
const { sleep } = require('../support/procs');

const READING = '(CPU|GPU|RAM|temperature)';
const unit = (reading) => (reading === 'temperature' ? '°C' : '%');

function source(w) {
  if (!w.source) {
    w.source = new TestSource();
    w.shown = { CPU: 20, GPU: 10, RAM: 40, temperature: 45 }; // TestSource's defaults
    w.defer(() => w.source.remove());
  }
  return w.source;
}

/** Feed a reading to the test source (and to the running meter, if any). */
function feed(w, reading, value) {
  source(w).set(reading, value);
  w.shown[reading] = value;
  return w.meter ? w.source.write() : Date.now();
}

async function live(w) {
  if (!w.meter) w.meter = await meter.launch(w, { source: source(w) });
  return w.meter;
}

async function itemNow(w) {
  const it = await menubar.item(w.meter.pid);
  assert.ok(it, 'the meter has no item in the menu bar');
  return it;
}

/** Wait until the item shows `reading` as `shown` (e.g. "80%"); resolves the watch result. */
function until(w, reading, shown, deadline) {
  return menubar.watch(w.meter.pid, menubar.valueRegex(reading, shown), deadline);
}

/** Wait until the item shows every value given. */
async function untilAll(w, values, ms) {
  const f = (r) => (r in values ? ' '.repeat(3 - String(values[r]).length) + values[r] : '.{3}');
  const re = new RegExp(`^CPU ${f('CPU')}%  GPU ${f('GPU')}%  RAM ${f('RAM')}%  ${f('temperature')}°C$`, 'u');
  const r = await menubar.watch(w.meter.pid, re, Date.now() + ms);
  assert.ok(r.matched, `the item never showed ${JSON.stringify(values)}; it reads ${JSON.stringify(r.title)}`);
}

/** A change to a reading not under test, seen in the menu bar: a refresh has just happened. */
async function seeARefresh(w, notReading) {
  const other = notReading === 'temperature' ? 'GPU' : 'temperature';
  const next = w.shown[other] >= 99 ? w.shown[other] - 1 : w.shown[other] + 1;
  feed(w, other, next);
  const r = await until(w, other, `${next}${unit(other)}`, Date.now() + 3000);
  assert.ok(r.matched, `the item never refreshed; it reads ${JSON.stringify(r.title)}`);
}

function controlCenterPid() {
  return Number(execFileSync('pgrep', ['-x', 'ControlCenter'], { encoding: 'utf8' }).trim().split('\n')[0]);
}

module.exports = (reg) => {
  // ---- Reading the values in the menu bar (D89) ---------------------------

  reg.define(/^the Mac is running with CPU at (\d+)%, GPU at (\d+)%, RAM at (\d+)% and the chip at (\d+) °C$/,
    (w, cpu, gpu, ram, temp) => {
      feed(w, 'CPU', Number(cpu));
      feed(w, 'GPU', Number(gpu));
      feed(w, 'RAM', Number(ram));
      feed(w, 'temperature', Number(temp));
    });

  reg.define(/^the user looks at the menu bar$/, async (w) => {
    await live(w);
  });

  reg.define(/^the user sees the item near Control Center read exactly "(.+)"$/, async (w, text) => {
    const it = await itemNow(w);
    assert.strictEqual(it.title, text);
    const cc = (await menubar.items(controlCenterPid())).find((i) => i.description === 'Control Center');
    assert.ok(cc, 'Control Center has no item in the menu bar');
    assert.ok(Math.abs((it.y + it.h / 2) - (cc.y + cc.h / 2)) < 6, `the item is not in the menu bar beside Control Center (${JSON.stringify(it)} vs ${JSON.stringify(cc)})`);
    assert.ok(it.x + it.w <= cc.x, `the item is not among the status items left of Control Center (${JSON.stringify(it)} vs ${JSON.stringify(cc)})`);
  });

  // ---- The menu bar item keeps one width (D90) ----------------------------

  reg.define(/^the menu bar item has been showing CPU (\d+)%, GPU (\d+)%, RAM (\d+)% and (\d+)°C$/,
    async (w, cpu, gpu, ram, temp) => {
      const values = { CPU: Number(cpu), GPU: Number(gpu), RAM: Number(ram), temperature: Number(temp) };
      for (const [r, v] of Object.entries(values)) feed(w, r, v);
      await live(w);
      await untilAll(w, values, 3000);
      // An icon to the item's left: a stand-in status item started after the
      // meter, which macOS places to its left.
      w.marker = await meter.launchMarker(w);
      await sleep(500);
      const it = await itemNow(w);
      const mk = await menubar.item(w.marker.pid);
      assert.ok(mk && mk.x + mk.w <= it.x, `the stand-in icon is not to the item's left (${JSON.stringify(mk)} vs ${JSON.stringify(it)})`);
      w.before = { item: it, marker: mk };
    });

  reg.define(/^the readings change to CPU (\d+)%, GPU (\d+)%, RAM (\d+)% and (\d+) °C$/,
    async (w, cpu, gpu, ram, temp) => {
      const values = { CPU: Number(cpu), GPU: Number(gpu), RAM: Number(ram), temperature: Number(temp) };
      for (const [r, v] of Object.entries(values)) feed(w, r, v);
      await untilAll(w, values, 3000);
      await sleep(500); // let the menu bar finish any layout change
    });

  reg.define(/^the item's width in the menu bar is unchanged$/, async (w) => {
    const it = await itemNow(w);
    assert.strictEqual(it.w, w.before.item.w, `width was ${w.before.item.w}, now ${it.w}`);
  });

  reg.define(/^the menu bar icons to the item's left have not moved$/, async (w) => {
    const mk = await menubar.item(w.marker.pid);
    assert.ok(mk, 'the stand-in icon left the menu bar');
    assert.deepStrictEqual({ x: mk.x, y: mk.y, w: mk.w }, { x: w.before.marker.x, y: w.before.marker.y, w: w.before.marker.w });
  });

  // ---- The readout follows a change within a second (D115) ----------------

  reg.define(new RegExp(`^the menu bar item reads ${READING} at (\\d+)(?:%|°C)$`), async (w, reading, value) => {
    feed(w, reading, Number(value));
    await live(w);
    const r = await until(w, reading, `${value}${unit(reading)}`, Date.now() + 3000);
    assert.ok(r.matched, `the item never read ${reading} ${value}; it reads ${JSON.stringify(r.title)}`);
  });

  reg.define(new RegExp(`^the Mac's ${READING} moves to (\\d+)(?:%|°C) and stays there$`), async (w, reading, value) => {
    // Move it 0.4 s after a refresh the user saw: at one pass a second the
    // next refresh is ~0.6 s away; anything slower is well over a second.
    await seeARefresh(w, reading);
    await sleep(400);
    w.changedAt = feed(w, reading, Number(value));
  });

  reg.define(new RegExp(`^within 1 second the user sees the item's ${READING} value read "(\\d+(?:%|°C))"$`), async (w, reading, shown) => {
    const r = await until(w, reading, shown, w.changedAt + 2500);
    assert.ok(r.matched, `the item never read ${reading} ${shown}; it reads ${JSON.stringify(r.title)}`);
    const took = r.seenAtEpochMs - w.changedAt;
    if (process.env.METER_TRACE) console.log(`# ${reading} -> ${shown} seen after ${Math.round(took)} ms`);
    assert.ok(took <= 1000, `the item read ${reading} ${shown} only ${Math.round(took)} ms after the change`);
  });

  // ---- Rounding, RAM, CPU and GPU sources (D46, D47, D48, D49) -------------

  reg.define(/^the Mac's CPU use is (\d+(?:\.\d+)?)%$/, (w, actual) => {
    feed(w, 'CPU', Number(actual));
  });

  reg.define(/^this Mac has (\d+) GB of memory$/, (w, gb) => {
    // The real Mac's own figure: the meter reads hw.memsize itself.
    assert.strictEqual(physicalBytes(), Number(gb) * GiB, `this Mac has ${physicalBytes() / GiB} GB, not ${gb} GB`);
  });

  reg.define(/^Activity Monitor reads Memory Used of (\d+(?:\.\d+)?) GB, with reusable cache held besides$/, (w, used) => {
    source(w).setMemoryUsed(Number(used) * GiB);
    const vm = w.source.doc.vm;
    assert.ok(vm.external + vm.purgeable > 0, 'no reusable cache is held besides');
    if (w.meter) w.source.write();
  });

  reg.define(/^Activity Monitor's CPU tab reads System "(\d+(?:\.\d+)?)%" and User "(\d+(?:\.\d+)?)%" at the same moment$/, (w, system, user) => {
    source(w).setCpuSplit(Number(user), Number(system));
    if (w.meter) w.source.write();
  });

  reg.define(/^macOS reports its overall GPU utilization as "(\d+)%"$/, (w, gpu) => {
    feed(w, 'GPU', Number(gpu));
  });

  reg.define(/^the menu bar item refreshes$/, async (w) => {
    await live(w);
    await seeARefresh(w, 'CPU');
  });

  reg.define(new RegExp(`^the user sees the item's ${READING} value read "(\\d+(?:%|°C))"$`), async (w, reading, shown) => {
    const it = await itemNow(w);
    const p = menubar.parse(it.title);
    assert.ok(p, `the item's text has another shape: ${JSON.stringify(it.title)}`);
    assert.strictEqual(p.value[reading], shown, `the item reads ${JSON.stringify(it.title)}`);
  });

  // ---- A value with no fresh reading turns into a dash (D114) -------------

  reg.define(/^the meter is live$/, async (w) => {
    await live(w);
  });

  reg.define(new RegExp(`^no fresh ${READING} reading arrives$`), (w, reading) => {
    assert.ok(w.meter, 'the meter is not running');
    source(w).gap(reading);
    w.gapped = reading;
    w.gapAt = w.source.write();
  });

  reg.define(/^(\d+) seconds pass without one$/, async (w, seconds) => {
    await sleep(w.gapAt + Number(seconds) * 1000 - Date.now());
  });

  reg.define(/^the user sees that value shown as "(.+)"$/, async (w, dash) => {
    const width = { CPU: 8, GPU: 8, RAM: 8, temperature: 5 }[w.gapped];
    const segment = dash.padStart(width);
    // The When ended three seconds after the last fresh reading could have
    // arrived; allow one refresh's drawing time on top.
    let r;
    for (const deadline = Date.now() + 700; ;) {
      const it = await itemNow(w);
      const p = menubar.parse(it.title);
      if (p && p.segment[w.gapped] === segment) { r = { matched: true }; break; }
      if (Date.now() > deadline) { r = { matched: false, title: it.title }; break; }
      await sleep(20);
    }
    assert.ok(r.matched, `${w.gapped} is not shown as ${JSON.stringify(segment)}; the item reads ${JSON.stringify(r.title)}`);
    w.dashSegment = segment;
  });

  reg.define(/^the user sees the other values still updating$/, async (w) => {
    const next = { CPU: 33, GPU: 44, RAM: 55, temperature: 66 };
    const others = menubar.READINGS.filter((r) => r !== w.gapped);
    for (const r of others) {
      assert.notStrictEqual(w.shown[r], next[r]);
      feed(w, r, next[r]);
    }
    const values = Object.fromEntries(others.map((r) => [r, next[r]]));
    await untilAll(w, values, 2500);
    const p = menubar.parse((await itemNow(w)).title);
    assert.strictEqual(p.segment[w.gapped], w.dashSegment, `${w.gapped} no longer shows its dash`);
  });

  // ---- The temperature rises under load (D112), on the real Mac -----------

  reg.define(/^the Mac has sat idle and the menu bar shows the chip temperature$/, async (w) => {
    const top = await probes.topCpu();
    assert.ok(top.idle >= 60, `this Mac is not idle: top reports ${top.idle}% idle`);
    w.meter = await meter.launch(w); // the installed build, real readings
    await sleep(3000);
    const p = menubar.parse((await itemNow(w)).title);
    assert.ok(p && /^\d+°C$/.test(p.value.temperature), `no chip temperature in the menu bar: ${JSON.stringify(p)}`);
    w.idleCelsius = parseInt(p.value.temperature, 10);
  });

  reg.define(/^one task fully uses every CPU core for (\d+) minutes$/, async (w, minutes) => {
    const end = Date.now() + Number(minutes) * 60000;
    const cores = probes.cores();
    const task = busyTask(w, cores);
    await sleep(10000);
    // Independent witnesses that the load is real.
    const ps = probes.psOf(task.pid);
    assert.ok(ps && ps.cpu >= (cores - 1) * 90, `the busy task is not using every core: ps reports ${JSON.stringify(ps)}`);
    const top = await probes.topCpu();
    assert.ok(top.idle <= 15, `the Mac is not fully loaded: top reports ${top.idle}% idle`);
    await sleep(end - Date.now());
  });

  reg.define(/^the temperature the user sees at the end is higher than the one shown at idle$/, async (w) => {
    const p = menubar.parse((await itemNow(w)).title);
    assert.ok(p && /^\d+°C$/.test(p.value.temperature), `no chip temperature in the menu bar: ${JSON.stringify(p)}`);
    const end = parseInt(p.value.temperature, 10);
    assert.ok(end > w.idleCelsius, `the temperature read ${w.idleCelsius}°C at idle and ${end}°C after the load`);
  });
};
