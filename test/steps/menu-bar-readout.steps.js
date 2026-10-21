'use strict';
// menu-bar-readout.feature. Givens may set the meter's raw inputs through the test reading
// source; every Then reads only what macOS shows: the status item through Accessibility.
const assert = require('node:assert');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const feeds = require('../support/feed');
const menubar = require('../support/menubar');
const meter = require('../support/meter');
const probes = require('../support/probes');
const panel = require('../support/panel');
const procs = require('../support/procs');

/**
 * Where the menu bar's room for status items starts: the right edge of the notch (the left edge
 * of the screen's top-right area), or 0 on a screen with none. Read from macOS itself.
 */
function menuBarStart() {
  const script = 'ObjC.import("AppKit"); const a = $.NSScreen.screens.objectAtIndex(0)'
    + '.auxiliaryTopRightArea; a ? a.origin.x : 0';
  return Number(execFileSync('osascript', ['-l', 'JavaScript', '-e', script], { encoding: 'utf8' }));
}

/** A status item macOS really shows lies fully right of the notch; a hidden one does not. */
function assertShown(item, notchRight, what) {
  assert.ok(item && item.width > 0 && item.x >= notchRight,
    `${what} hidden: not enough menu bar room (item at x=${item && item.x}, notch ends at ${notchRight})`);
}

const DASH = '–';
const isNumber = (value) => /^\d+(%|°C)$/u.test(value);
const allNumbers = (item) => {
  const f = menubar.fields(item.title);
  return !!f && Object.values(f).every(isNumber);
};
const required = (value, what) => {
  if (value === undefined || value === null) throw new Error(`world.${what} read before any step set it`);
  return value;
};

/** Waits for the first refresh showing every value, then one more full refresh. */
async function refreshed(w) {
  const m = required(w.meter, 'meter');
  await menubar.waitForItem(m.pid, allNumbers, 5000, 'every value shown');
  await procs.sleep(1100);
  const [item] = menubar.itemsOf(m.pid);
  w.item = item;
  return item;
}

const unit = (reading) => (reading === 'temperature' ? '°C' : '%');
const feedKey = { CPU: 'cpu', GPU: 'gpu', RAM: 'memory', temperature: 'sensors' };
function feedFor(reading, value) {
  switch (reading) {
    case 'CPU': return feeds.cpuLoad(value);
    case 'GPU': return feeds.gpuAt(value);
    case 'RAM': return feeds.memoryAt(value);
    case 'temperature': return feeds.sensorsAt(value);
    default: throw new Error(`no such reading: ${reading}`);
  }
}

module.exports = (reg) => {
  // --- Reading the values in the menu bar (D89) ---

  reg.define(
    /^the Mac is running with CPU at (\d+)%, GPU at (\d+)%, RAM at (\d+)% and the chip at (\d+) °C$/,
    async (w, cpu, gpu, ram, temp) => {
      await meter.launchWithFeed(w, feeds.readings({
        cpu: Number(cpu), gpu: Number(gpu), ram: Number(ram), temp: Number(temp),
      }));
    });

  reg.define(/^the user looks at the menu bar$/, async (w) => {
    await refreshed(w);
    w.menuBar = menubar.allItems();
  });

  reg.define(/^the user sees the item near Control Center read exactly "(.+)"$/, (w, text) => {
    const item = required(w.item, 'item');
    assert.strictEqual(item.title, text);
    const bar = required(w.menuBar, 'menuBar');
    const controlCenter = bar.find((i) => i.app === 'Control Center' && i.title === 'Control Center');
    assert.ok(controlCenter, 'Control Center has an item in the menu bar');
    const rightEdge = Math.max(...bar.map((i) => i.x + i.width));
    assert.ok(Math.abs(item.y - controlCenter.y) <= 3, 'the item is in the same menu bar as Control Center');
    assert.ok(item.x + item.width <= controlCenter.x, 'the item sits left of Control Center among the status items');
    assert.ok(item.x >= rightEdge / 2, 'the item is on the status-item side of the menu bar');
  });

  // --- The menu bar item keeps one width (D90) ---

  reg.define(
    /^the menu bar item has been showing CPU (\d+)%, GPU (\d+)%, RAM (\d+)% and (\d+)°C$/,
    async (w, cpu, gpu, ram, temp) => {
      const m = await meter.launchWithFeed(w, feeds.readings({
        cpu: Number(cpu), gpu: Number(gpu), ram: Number(ram), temp: Number(temp),
      }));
      const shows = { CPU: `${cpu}%`, GPU: `${gpu}%`, RAM: `${ram}%`, temperature: `${temp}°C` };
      await menubar.waitForItem(m.pid, (i) => {
        const f = menubar.fields(i.title);
        return !!f && Object.keys(shows).every((k) => f[k] === shows[k]);
      }, 5000, `the item showing ${JSON.stringify(shows)}`);
      await procs.sleep(500);
      // Before anything else: macOS hides a status item that has no room (Accessibility still
      // lists it at a stale place), so the meter must really be in the menu bar.
      const notchRight = menuBarStart();
      assertShown(menubar.itemsOf(m.pid)[0], notchRight, 'the meter');
      // One narrow stand-in started after the meter sits to its left, an icon beside it.
      await meter.launchNeighbor(w, 'N');
      await procs.sleep(500);
      const [before] = menubar.itemsOf(m.pid);
      assertShown(before, notchRight, 'the meter');
      w.before = before;
      w.leftOfItem = menubar.allItems()
        .filter((i) => i.pid !== m.pid && i.x >= notchRight && i.x + i.width <= before.x + 1);
      assert.ok(w.leftOfItem.length > 0, 'at least one menu bar icon sits to the item\'s left');
    });

  reg.define(
    /^the readings change to CPU (\d+)%, GPU (\d+)%, RAM (\d+)% and (\d+) °C$/,
    async (w, cpu, gpu, ram, temp) => {
      const m = required(w.meter, 'meter');
      required(w.feed, 'feed').set(feeds.readings({
        cpu: Number(cpu), gpu: Number(gpu), ram: Number(ram), temp: Number(temp),
      }));
      const shows = { CPU: `${cpu}%`, GPU: `${gpu}%`, RAM: `${ram}%`, temperature: `${temp}°C` };
      w.after = await menubar.waitForItem(m.pid, (i) => {
        const f = menubar.fields(i.title);
        return !!f && Object.keys(shows).every((k) => f[k] === shows[k]);
      }, 5000, `the item showing ${JSON.stringify(shows)}`);
    });

  reg.define(/^the item's width in the menu bar is unchanged$/, (w) => {
    assert.strictEqual(required(w.after, 'after').width, required(w.before, 'before').width);
  });

  reg.define(/^the menu bar icons to the item's left have not moved$/, (w) => {
    const before = required(w.leftOfItem, 'leftOfItem');
    const now = menubar.allItems();
    for (const icon of before) {
      const same = now.filter((i) => i.pid === icon.pid && i.title === icon.title);
      assert.ok(same.length > 0, `${icon.app || icon.pid} "${icon.title}" is still in the menu bar`);
      assert.ok(same.some((i) => i.x === icon.x && i.y === icon.y),
        `${icon.app || icon.pid} "${icon.title}" moved from x=${icon.x} to ${same.map((i) => i.x).join(', ')}`);
    }
  });

  // --- The readout follows a change within a second (D115) ---

  reg.define(/^the menu bar item reads (CPU|GPU|RAM|temperature) at (\d+)(%|°C)$/u,
    async (w, reading, before, sign) => {
      assert.strictEqual(sign, unit(reading));
      const base = { cpu: 30, gpu: 10, ram: 30, temp: 50 };
      const values = feeds.readings(base);
      values[feedKey[reading]] = feedFor(reading, Number(before));
      const m = await meter.launchWithFeed(w, values);
      await menubar.waitForItem(m.pid, (i) => {
        const f = menubar.fields(i.title);
        return !!f && Object.values(f).every(isNumber) && f[reading] === `${before}${sign}`;
      }, 5000, `${reading} at ${before}${sign}`);
    });

  reg.define(/^the Mac's (CPU|GPU|RAM|temperature) moves to (\d+)(%|°C) and stays there$/u,
    async (w, reading, after, sign) => {
      assert.strictEqual(sign, unit(reading));
      const m = required(w.meter, 'meter');
      w.watcher = await menubar.watch(m.pid, 4000);
      w.defer(() => w.watcher.stop());
      const value = feedFor(reading, Number(after));
      w.changedAt = Date.now();
      if (reading === 'CPU') value.since = w.changedAt;
      required(w.feed, 'feed').set({ [feedKey[reading]]: value });
    });

  reg.define(/^within 1 second the user sees the item's (CPU|GPU|RAM|temperature) value read "(.+)"$/u,
    async (w, reading, shown) => {
      const watcher = required(w.watcher, 'watcher');
      const changedAt = required(w.changedAt, 'changedAt');
      const deadline = changedAt + 2000;
      let hit;
      while (!hit && Date.now() < deadline) {
        hit = watcher.seen.find((s) => s.at >= changedAt && menubar.fields(s.title)?.[reading] === shown);
        if (!hit) await procs.sleep(20);
      }
      assert.ok(hit, `${reading} never read "${shown}"; saw ${JSON.stringify(watcher.seen)}`);
      assert.ok(hit.at - changedAt <= 1000,
        `${reading} read "${shown}" ${hit.at - changedAt} ms after the change`);
    });

  // --- Rounding (D46), Memory Used (D47), CPU (D48), GPU (D49) ---

  reg.define(/^the Mac's CPU use is ([\d.]+)%$/, async (w, actual) => {
    const values = feeds.readings({ cpu: 0, gpu: 5, ram: 40, temp: 45 });
    values.cpu = feeds.cpuLoad(Number(actual));
    await meter.launchWithFeed(w, values);
  });

  reg.define(/^the menu bar item refreshes$/, async (w) => {
    await refreshed(w);
  });

  reg.define(/^the user sees the item's (CPU|GPU|RAM|temperature) value read "(.+)"$/u,
    (w, reading, shown) => {
      const f = menubar.fields(required(w.item, 'item').title);
      assert.ok(f, `the item reads "${w.item.title}"`);
      assert.strictEqual(f[reading], shown);
    });

  reg.define(/^this Mac has (\d+) GB of memory$/, (w, gb) => {
    // The real Mac's own figure; the meter divides by it.
    assert.strictEqual(probes.memsize(), Number(gb) * feeds.GiB);
  });

  reg.define(/^Activity Monitor reads Memory Used of ([\d.]+) GB, with reusable cache held besides$/,
    async (w, gb) => {
      const values = feeds.readings({ cpu: 10, gpu: 5, ram: 0, temp: 45 });
      values.memory = feeds.memoryUsedGB(Number(gb));
      assert.ok(values.memory.fileBacked + values.memory.purgeable > 0, 'cache is held besides');
      await meter.launchWithFeed(w, values);
    });

  reg.define(/^Activity Monitor's CPU tab reads System "([\d.]+)%" and User "([\d.]+)%" at the same moment$/,
    async (w, system, user) => {
      const values = feeds.readings({ cpu: 0, gpu: 5, ram: 40, temp: 45 });
      values.cpu = feeds.cpuSplit(Number(user), Number(system));
      await meter.launchWithFeed(w, values);
    });

  reg.define(/^macOS reports its overall GPU utilization as "(\d+)%"$/, async (w, gpu) => {
    const values = feeds.readings({ cpu: 10, gpu: 0, ram: 40, temp: 45 });
    values.gpu = feeds.gpuAt(Number(gpu));
    await meter.launchWithFeed(w, values);
  });

  // --- A value with no fresh reading turns into a dash (D114) ---
  // The network and disk rows read the panel's network and disk lines (D95), each one reading
  // dashed as a whole line (D114). The Given owns all the driving: a harness ticker keeps every reading changing, and the
  // Accessibility watcher records what the user sees. The Thens only read the watcher.

  /** The live readings at tick `n`: each differs from the reading two ticks earlier. */
  const liveAt = (n) => {
    const step = n % 4;
    return { cpu: 30 + step * 10, gpu: 10 + step * 10, ram: 30 + step * 10, temp: 50 + step * 5 };
  };
  /** The network and disk rates at tick `n`, in bytes a second: each changing like the rest. */
  const ratesAt = (n) => {
    const mb = 1e6 * (1 + (n % 4));
    return { network: { received: 2 * mb, sent: mb }, disk: { read: 3 * mb, written: 4 * mb } };
  };
  const lineOf = { network: 'Net ', disk: 'Disk ' };
  const panelReadings = Object.keys(lineOf);

  reg.define(/^the meter is live$/, async (w) => {
    w.live = liveAt(0);
    const m = await meter.launchWithFeed(w, { ...feeds.readings(w.live), ...ratesAt(0) });
    await menubar.waitForItem(m.pid, allNumbers, 5000, 'every value shown');
    w.dropped = new Set();
    let tick = 0;
    const ticker = setInterval(() => {
      tick += 1;
      const values = { ...feeds.readings(liveAt(tick)), ...ratesAt(tick) };
      for (const reading of w.dropped) delete values[feedKey[reading] || reading];
      w.feed.set(values);
    }, 250);
    w.defer(() => clearInterval(ticker));
    w.watcher = await menubar.watch(m.pid, 15000);
    w.defer(() => w.watcher.stop());
  });

  // Network and disk show in the panel: the user opens it and watches the line move before
  // its reading stops.
  reg.define(/^no fresh (network|disk) reading arrives$/u, async (w, reading) => {
    const m = required(w.meter, 'meter');
    await panel.click(m.pid);
    w.panelWatcher = await panel.watchTexts(m.pid, 15000);
    w.defer(() => w.panelWatcher.stop());
    const lines = () => new Set(w.panelWatcher.seen
      .map((s) => panel.lineStarting(s.texts, lineOf[reading])).filter(Boolean));
    const deadline = Date.now() + 5000;
    while (lines().size < 3 && Date.now() < deadline) await procs.sleep(50);
    assert.ok(lines().size >= 3, `the ${reading} line was never live: ${JSON.stringify([...lines()])}`);
    w.stale = reading;
    w.dropped.add(reading);
    w.stoppedAt = Date.now();
    w.feed.set({ [reading]: null });
  });

  reg.define(/^no fresh (CPU|GPU|RAM|temperature) reading arrives$/u, (w, reading) => {
    w.stale = reading;
    w.dropped.add(reading);
    w.stoppedAt = Date.now();
    required(w.feed, 'feed').set({ [feedKey[reading]]: null });
  });

  reg.define(/^3 seconds pass without one$/, async (w) => {
    const wait = required(w.stoppedAt, 'stoppedAt') + 3000 - Date.now();
    if (wait > 0) await procs.sleep(wait);
  });

  reg.define(/^the user sees that value shown as "(.+)"$/u, async (w, dash) => {
    const reading = required(w.stale, 'stale');
    if (panelReadings.includes(reading)) {
      await panelLineDashed(w, reading, dash);
      return;
    }
    const watcher = required(w.watcher, 'watcher');
    const stoppedAt = required(w.stoppedAt, 'stoppedAt');
    const dashed = (s) => menubar.fields(s.title)?.[reading] === `${DASH}${unit(reading)}`;
    const deadline = stoppedAt + 5000;
    let first;
    while (!first && Date.now() < deadline) {
      first = watcher.seen.find(dashed);
      if (!first) await procs.sleep(20);
    }
    assert.ok(first, `${reading} never showed a dash; saw ${JSON.stringify(watcher.seen)}`);
    // The last time the user saw this value change is when the meter last took a fresh
    // reading of it (the feed kept it changing until it stopped). D114: a dash no earlier
    // than three seconds after that, less a little for the watcher's own jitter.
    let lastChange = watcher.seen[0].at;
    let previous;
    for (const s of watcher.seen) {
      if (dashed(s)) break;
      const value = menubar.fields(s.title)?.[reading];
      if (value !== previous) lastChange = s.at;
      previous = value;
    }
    assert.ok(first.at - lastChange >= 2750,
      `${reading} turned into a dash ${first.at - lastChange} ms after the user last saw it change`);
    const [item] = menubar.itemsOf(required(w.meter, 'meter').pid);
    assert.ok(item.title.includes(dash), `"${item.title}" shows "${dash}"`);
    assert.ok(dashed(item), `"${item.title}" shows ${reading} as a dash`);
  });

  /** The panel's line for `reading` turns into `dash`, whole, 3 seconds after it last moved. */
  async function panelLineDashed(w, reading, dash) {
    const watcher = required(w.panelWatcher, 'panelWatcher');
    const stoppedAt = required(w.stoppedAt, 'stoppedAt');
    const line = (s) => panel.lineStarting(s.texts, lineOf[reading]);
    const dashed = (s) => line(s) === dash;
    const deadline = stoppedAt + 5000;
    let first;
    while (!first && Date.now() < deadline) {
      first = watcher.seen.find(dashed);
      if (!first) await procs.sleep(20);
    }
    assert.ok(first, `the ${reading} line never read "${dash}"; saw ${JSON.stringify([...new Set(watcher.seen.map(line))])}`);
    // No half-dashed line on the way: each read is the whole line live or the whole dash.
    const live = new RegExp(`^${lineOf[reading]}\\S+ \\d+\\.\\d (KB|MB|GB)/s \\S+ \\d+\\.\\d (KB|MB|GB)/s$`, 'u');
    for (const s of watcher.seen) {
      const text = line(s);
      assert.ok(text === dash || live.test(text), `the ${reading} line read "${text}"`);
    }
    let lastChange = watcher.seen[0].at;
    let previous;
    for (const s of watcher.seen) {
      if (dashed(s)) break;
      if (line(s) !== previous) lastChange = s.at;
      previous = line(s);
    }
    // A pass every half second, a panel read every tenth or so: the last change seen can trail
    // the last fresh reading by up to a read.
    assert.ok(first.at - lastChange >= 2750,
      `the ${reading} line turned into a dash ${first.at - lastChange} ms after the user last saw it change`);
    const now = panel.lineStarting(panel.textsNow(required(w.meter, 'meter').pid), lineOf[reading]);
    assert.strictEqual(now, dash, `the ${reading} line reads "${dash}"`);
  }

  reg.define(/^the user sees the other values still updating$/, async (w) => {
    const reading = required(w.stale, 'stale');
    const watcher = required(w.watcher, 'watcher');
    if (panelReadings.includes(reading)) {
      // The menu bar's values and the panel's other line go on moving; this line stays a dash.
      const pw = required(w.panelWatcher, 'panelWatcher');
      const other = panelReadings.find((r) => r !== reading);
      const dash = { network: `Net ↓ ${DASH} ↑ ${DASH}`, disk: `Disk R ${DASH} W ${DASH}` }[reading];
      const base = pw.seen.find((s) => panel.lineStarting(s.texts, lineOf[reading]) === dash);
      assert.ok(base, `the ${reading} line never showed a dash`);
      const at = (s, r) => menubar.fields(s.title)?.[r];
      const titleAt = [...watcher.seen].reverse().find((s) => s.at <= base.at) || watcher.seen[0];
      const changed = () => {
        const bar = watcher.seen.filter((s) => s.at >= base.at);
        const lines = pw.seen.filter((s) => s.at >= base.at);
        return Object.keys(feedKey).every((r) => bar.some((s) => at(s, r) !== undefined && at(s, r) !== at(titleAt, r)))
          && lines.some((s) => panel.lineStarting(s.texts, lineOf[other]) !== panel.lineStarting(base.texts, lineOf[other]));
      };
      const deadline = Date.now() + 3000;
      while (!changed() && Date.now() < deadline) await procs.sleep(20);
      assert.ok(changed(), `the other values stopped updating after the ${reading} line dashed`);
      const after = pw.seen.filter((s) => s.at >= base.at);
      assert.ok(after.every((s) => panel.lineStarting(s.texts, lineOf[reading]) === dash), `the ${reading} line stayed a dash`);
      return;
    }
    const others = Object.keys(feedKey).filter((r) => r !== reading);
    const dashValue = `${DASH}${unit(reading)}`;
    const at = (s, r) => menubar.fields(s.title)?.[r];
    const base = watcher.seen.find((s) => at(s, reading) === dashValue);
    assert.ok(base, `${reading} never showed a dash`);
    const changed = () => {
      const after = watcher.seen.filter((s) => s.at >= base.at);
      return others.every((r) => after.some((s) => at(s, r) !== undefined && at(s, r) !== at(base, r)));
    };
    const deadline = Date.now() + 3000;
    while (!changed() && Date.now() < deadline) await procs.sleep(20);
    assert.ok(changed(), `the other values stopped updating; saw ${JSON.stringify(watcher.seen)}`);
    const after = watcher.seen.filter((s) => s.at >= base.at);
    assert.ok(after.every((s) => at(s, reading) === dashValue), `${reading} stayed a dash`);
  });

  // --- The temperature rises under load (D112), against the real system ---

  reg.define(/^the Mac has sat idle and the menu bar shows the chip temperature$/, async (w) => {
    const m = await meter.launchReal(w);
    let quiet = 0;
    const deadline = Date.now() + 180000;
    while (quiet < 5) {
      if (Date.now() > deadline) throw new Error('the Mac never sat idle (top: User + System under 20%)');
      const { user, system } = probes.topCpu();
      quiet = user + system < 20 ? quiet + 1 : 0;
    }
    const [item] = menubar.itemsOf(m.pid);
    const shown = menubar.fields(item.title)?.temperature;
    assert.ok(shown && isNumber(shown), `the menu bar shows a chip temperature: "${item.title}"`);
    w.idleTemperature = Number.parseInt(shown, 10);
  });

  reg.define(/^one task fully uses every CPU core for (\d+) minutes$/, async (w, minutes) => {
    const m = required(w.meter, 'meter');
    const cores = probes.cpuCount();
    const started = Date.now();
    const load = procs.start(process.execPath, [path.join(__dirname, '..', 'support', 'load.js'), String(cores)]);
    w.defer(() => procs.end(load));
    await procs.sleep(5000);
    const used = probes.psCpu(load.pid);
    assert.ok(used >= cores * 85, `the task uses ${used}% of ${cores} cores' ${cores * 100}%`);
    await procs.sleep(started + Number(minutes) * 60000 - Date.now());
    const [item] = menubar.itemsOf(m.pid);
    const shown = menubar.fields(item.title)?.temperature;
    assert.ok(shown && isNumber(shown), `the menu bar shows a chip temperature: "${item.title}"`);
    w.loadedTemperature = Number.parseInt(shown, 10);
    await procs.end(load);
  });

  reg.define(/^the temperature the user sees at the end is higher than the one shown at idle$/, (w) => {
    const idle = required(w.idleTemperature, 'idleTemperature');
    const loaded = required(w.loadedTemperature, 'loadedTemperature');
    assert.ok(loaded > idle, `${loaded}°C at the end of the load, ${idle}°C at idle`);
  });
};
