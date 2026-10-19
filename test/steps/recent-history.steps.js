'use strict';
// recent-history.feature. Givens may set the meter's past and its readings through the test
// reading source (or, for the short history, let the real meter run on the real Mac); every
// Then reads only what macOS shows: the panel's text and layout through Accessibility, and the
// graph's lines from screenshot pixels, told apart by the colours the legend gives them.
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const { Past } = require('../support/feed');
const meter = require('../support/meter');
const panel = require('../support/panel');
const procs = require('../support/procs');

const WINDOW = 300;
const required = (value, what) => {
  if (value === undefined || value === null) throw new Error(`world.${what} read before any step set it`);
  return value;
};

/** "4.5 minutes", "5 minutes 10 seconds", "30 seconds", "2 minutes" in seconds. */
function seconds(text) {
  const m = /^(?:([\d.]+) minutes?)?\s*(?:(\d+) seconds?)?$/.exec(text.trim());
  if (!m || (m[1] === undefined && m[2] === undefined)) throw new Error(`not a duration: "${text}"`);
  return Number(m[1] || 0) * 60 + Number(m[2] || 0);
}

/** The process's elapsed time as `ps` reports it, in seconds: macOS's own account. */
function elapsedOf(pid) {
  const text = execFileSync('ps', ['-o', 'etime=', '-p', String(pid)], { encoding: 'utf8' }).trim();
  const m = /^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$/.exec(text);
  if (!m) throw new Error(`ps etime "${text}"`);
  return Number(m[1] || 0) * 86400 + Number(m[2] || 0) * 3600 + Number(m[3]) * 60 + Number(m[4]);
}

/** Starts the meter with the scenario's past, unless a Given already started it. */
async function running(w) {
  if (w.meter) return w.meter;
  const past = required(w.past, 'past');
  w.launchedAt = Date.now();
  return meter.launchWithFeed(w, past.feed());
}

/** How long before the capture the meter launched, in seconds: the past's ages shift by it. */
const shift = (w) => (required(w.capture, 'capture').at - required(w.launchedAt, 'launchedAt')) / 1000;

/** Where on the graph (0 left edge, 1 right edge) a moment `age` seconds before launch sits. */
const xOfAge = (w, age) => 1 - (age + shift(w)) / WINDOW;

const describe = (pixels) => {
  if (pixels.length === 0) return 'none';
  const xs = pixels.map((p) => p.x);
  const vs = pixels.map((p) => p.value);
  return `${pixels.length} px, x ${Math.min(...xs).toFixed(3)}..${Math.max(...xs).toFixed(3)}, `
    + `value ${Math.min(...vs).toFixed(1)}..${Math.max(...vs).toFixed(1)}%`;
};

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
};

/** The time axis: `left` under the graph's left edge, `right` under its right edge. */
function axisReads(w, left, right) {
  const capture = required(w.capture, 'capture');
  const graph = panel.theGraph(capture);
  const bottom = graph.y + graph.height;
  const [start] = panel.textsReading(capture, left);
  const [end] = panel.textsReading(capture, right);
  assert.ok(start, `the axis shows "${left}"`);
  assert.ok(end, `the axis shows "${right}"`);
  for (const text of [start, end]) {
    assert.ok(text.y >= bottom - 2 && text.y <= bottom + 20, `"${text.text}" sits under the graph`);
  }
  assert.ok(Math.abs(start.x - graph.x) <= 4, `"${left}" sits at the graph's left edge`);
  assert.ok(Math.abs(end.x + end.width - (graph.x + graph.width)) <= 4,
    `"${right}" sits at the graph's right edge`);
}

module.exports = (reg) => {
  // --- The Givens: the meter's past, driven through the test reading source ---

  reg.define(/^the meter has run for over (\d+) minutes$/, (w, minutes) => {
    w.past = new Past(Number(minutes) * 60 + 30);
  });

  reg.define(/^CPU spiked to 100% about ([\d.]+ minutes) ago and is at 100% now$/, (w, age) => {
    const past = required(w.past, 'past');
    const spike = seconds(age);
    past.levels.cpu = 6;
    past.hold('cpu', spike + 2, spike - 2, 100).hold('cpu', 15, 0, 100);
  });

  reg.define(/^GPU has sat at (\d+)% and RAM has held near (\d+)%$/, (w, gpu, ram) => {
    const past = required(w.past, 'past');
    past.levels.gpu = Number(gpu);
    past.levels.ram = Number(ram);
  });

  reg.define(/^CPU spiked to 100% (.+) ago and has stayed under 10% since$/, (w, age) => {
    const spike = seconds(age);
    w.past = new Past(spike + 60, { cpu: 5, gpu: 3, ram: 45 }).hold('cpu', spike + 2, spike - 2, 100);
  });

  reg.define(
    /^the meter was running, then the Mac slept for (\d+) minutes and woke within the last (\d+) minutes$/,
    (w, slept, within) => {
      const sleep = Number(slept) * 60;
      const wokeAge = 60;
      assert.ok(wokeAge + sleep < Number(within) * 60, 'the whole sleep falls within the window');
      w.sleptFrom = wokeAge + sleep;
      w.wokeAt = wokeAge;
      // Three levels far apart, so each line is seen on its own on both sides of the sleep.
      w.past = new Past(w.sleptFrom + 60, { cpu: 30, gpu: 10, ram: 60 }).asleep(w.sleptFrom, wokeAge);
    });

  // The short history runs on the real Mac: the release meter, no test source, really running
  // for the time the Given names, checked by `ps`.
  reg.define(/^the meter has been running for only (\d+) seconds$/, async (w, secs) => {
    const m = await meter.launchReal(w);
    w.launchedAt = Date.now();
    w.ranFor = Number(secs);
    while (elapsedOf(m.pid) < w.ranFor) await procs.sleep(200);
  });

  // --- The Whens: a click on the menu bar item ---

  reg.define(/^the user clicks the menu bar item$/, async (w) => {
    const m = await running(w);
    w.capture = await panel.clickAndCapture(m.pid);
  });

  reg.define(/^the user opens the panel$/, async (w) => {
    const m = await running(w);
    w.capture = await panel.clickAndCapture(m.pid);
    w.elapsedAtCapture = elapsedOf(m.pid);
  });

  // --- The panel and its axes ---

  reg.define(
    /^the user sees a panel drop down with one graph running from "(.+)" on the left to "(.+)" on the right$/,
    (w, left, right) => {
      const capture = required(w.capture, 'capture');
      const { item, window } = capture;
      assert.ok(window.y >= item.y + item.height - 1 && window.y <= item.y + item.height + 20,
        `the panel hangs just below the menu bar item (item bottom ${item.y + item.height}, panel top ${window.y})`);
      assert.ok(window.x < item.x + item.width && window.x + window.width > item.x,
        'the panel drops down under the item');
      assert.strictEqual(panel.graphs(capture).length, 1, 'one graph');
      axisReads(w, left, right);
    });

  reg.define(/^the user sees the graph's axis still run from "(.+)" to "(.+)"$/, (w, left, right) => {
    axisReads(w, left, right);
  });

  reg.define(/^the graph's scale runs from (\d+)% to (\d+)%$/, (w, low, high) => {
    const capture = required(w.capture, 'capture');
    const graph = panel.theGraph(capture);
    for (const [label, end] of [[`${high}%`, 'top'], [`${low}%`, 'bottom']]) {
      const [text] = panel.textsReading(capture, label);
      assert.ok(text, `the scale shows "${label}"`);
      assert.ok(text.x + text.width <= graph.x + 2, `"${label}" sits beside the graph's ${end}`);
      const centre = text.y + text.height / 2;
      const edge = end === 'top' ? graph.y : graph.y + graph.height;
      assert.ok(Math.abs(centre - edge) <= graph.height * 0.08,
        `"${label}" marks the graph's ${end} (label at ${centre}, edge at ${edge})`);
    }
    // Each line ends, at "now", at the height its legend value takes on that scale.
    const pixels = panel.linePixels(capture);
    for (const line of ['CPU', 'GPU', 'RAM']) {
      const value = panel.legendValue(capture, line);
      const end = pixels.filter((p) => p.line === line && p.x >= 0.985);
      assert.ok(end.length > 0, `the ${line} line reaches "now"`);
      const at = median(end.map((p) => p.value));
      assert.ok(Math.abs(at - value) <= 3,
        `the ${line} line ends at ${at.toFixed(1)}% on the scale; its legend reads ${value}%`);
    }
  });

  // --- The lines ---

  reg.define(/^the graph has exactly (\d+) lines: (\w+), (\w+) and (\w+)$/, (w, count, a, b, c) => {
    const capture = required(w.capture, 'capture');
    const labels = [a, b, c];
    assert.strictEqual(labels.length, Number(count));
    const hues = panel.legendHues(capture);
    for (let i = 0; i < labels.length; i++) {
      for (let j = i + 1; j < labels.length; j++) {
        const d = panel.hueDistance(hues[labels[i]], hues[labels[j]]);
        assert.ok(d >= 40, `${labels[i]} and ${labels[j]} are drawn in distinct colours (${d.toFixed(0)}° apart)`);
      }
    }
    const pixels = panel.linePixels(capture);
    for (const line of labels) {
      const own = pixels.filter((p) => p.line === line);
      assert.ok(own.length >= 200, `the ${line} line is drawn across the graph: ${describe(own)}`);
    }
    // Nothing else coloured: no fourth line. A few blended pixels where lines cross are allowed.
    const other = pixels.filter((p) => p.line === null);
    assert.ok(other.length <= pixels.length * 0.03,
      `${other.length} of ${pixels.length} coloured pixels belong to no legend line (hues ${[
        ...new Set(other.map((p) => Math.round(p.hue / 10) * 10))].join(', ')})`);
  });

  reg.define(/^the CPU line reaches 100% near the graph's left edge$/, (w) => {
    const pixels = panel.linePixels(required(w.capture, 'capture')).filter((p) => p.line === 'CPU');
    const top = pixels.filter((p) => p.value >= 97);
    assert.ok(top.some((p) => p.x <= 0.2), `the CPU line at 100%: ${describe(top)}`);
  });

  reg.define(/^the legend reads "(.+)"$/, (w, text) => {
    assert.strictEqual(panel.legend(required(w.capture, 'capture')).text, text);
  });

  reg.define(/^the spike the user sees is (near the graph's left edge|nowhere in the graph)$/, (w, where) => {
    const pixels = panel.linePixels(required(w.capture, 'capture')).filter((p) => p.line === 'CPU');
    assert.ok(pixels.length >= 200, `the CPU line is drawn: ${describe(pixels)}`);
    // The spike: the CPU line well above the under-10% it has held since.
    const spike = pixels.filter((p) => p.value > 50);
    if (where === 'nowhere in the graph') {
      assert.strictEqual(spike.length, 0, `the CPU line rises above 50%: ${describe(spike)}`);
    } else {
      assert.ok(spike.some((p) => p.value >= 97), `the spike reaches 100%: ${describe(spike)}`);
      assert.ok(spike.every((p) => p.x <= 0.2), `the spike sits near the left edge: ${describe(spike)}`);
    }
  });

  reg.define(/^the lines cover only the last (\d+) seconds at the right edge$/, (w, secs) => {
    const capture = required(w.capture, 'capture');
    const ran = required(w.elapsedAtCapture, 'elapsedAtCapture');
    assert.ok(ran >= Number(secs) && ran <= Number(secs) + 5,
      `ps: the meter had run ${ran} s when the panel opened`);
    const pixels = panel.linePixels(capture).filter((p) => p.line !== null);
    assert.ok(pixels.length >= 50, `lines are drawn: ${describe(pixels)}`);
    // Its first sample is from just after it started; ps counts whole seconds.
    const start = 1 - (ran + 1) / WINDOW;
    const left = Math.min(...pixels.map((p) => p.x));
    const right = Math.max(...pixels.map((p) => p.x));
    assert.ok(left >= start - 0.012 && left <= 1 - (ran - 1) / WINDOW + 0.012,
      `the lines start ${(1 - left) * WINDOW} s before now, the meter ran ${ran} s: ${describe(pixels)}`);
    assert.ok(right >= 0.985, `the lines run to the right edge: ${describe(pixels)}`);
  });

  reg.define(/^the rest of the graph is empty$/, (w) => {
    const capture = required(w.capture, 'capture');
    const ran = required(w.elapsedAtCapture, 'elapsedAtCapture');
    const pixels = panel.linePixels(capture);
    const before = pixels.filter((p) => p.x < 1 - (ran + 1) / WINDOW - 0.012);
    assert.strictEqual(before.length, 0, `nothing is drawn before the meter ran: ${describe(before)}`);
  });

  reg.define(/^the user sees no line for the (\d+) minutes the Mac was asleep$/, (w, minutes) => {
    assert.strictEqual(Number(minutes) * 60, required(w.sleptFrom, 'sleptFrom') - required(w.wokeAt, 'wokeAt'));
    const slept = xOfAge(w, w.sleptFrom);
    const woke = xOfAge(w, w.wokeAt);
    const pixels = panel.linePixels(required(w.capture, 'capture'));
    const during = pixels.filter((p) => p.x > slept + 0.01 && p.x < woke - 0.01);
    assert.strictEqual(during.length, 0,
      `nothing is drawn between ${slept.toFixed(3)} and ${woke.toFixed(3)}: ${describe(during)}`);
  });

  reg.define(/^the lines stop where it went to sleep and resume where it woke$/, (w) => {
    const slept = xOfAge(w, required(w.sleptFrom, 'sleptFrom'));
    const woke = xOfAge(w, required(w.wokeAt, 'wokeAt'));
    const middle = (slept + woke) / 2;
    const pixels = panel.linePixels(required(w.capture, 'capture'));
    for (const line of ['CPU', 'GPU', 'RAM']) {
      const own = pixels.filter((p) => p.line === line);
      const beforeSleep = own.filter((p) => p.x < middle);
      const afterWake = own.filter((p) => p.x > middle);
      assert.ok(beforeSleep.length > 0, `the ${line} line is drawn before the sleep: ${describe(own)}`);
      assert.ok(afterWake.length > 0, `the ${line} line is drawn after the wake: ${describe(own)}`);
      const stop = Math.max(...beforeSleep.map((p) => p.x));
      const resume = Math.min(...afterWake.map((p) => p.x));
      assert.ok(Math.abs(stop - slept) <= 0.012,
        `the ${line} line stops at ${stop.toFixed(3)}; the Mac went to sleep at ${slept.toFixed(3)}`);
      assert.ok(Math.abs(resume - woke) <= 0.012,
        `the ${line} line resumes at ${resume.toFixed(3)}; the Mac woke at ${woke.toFixed(3)}`);
    }
  });
};
