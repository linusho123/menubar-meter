'use strict';
// What the user sees in the panel: its elements read through the Accessibility API by the
// meter-ax helper, and its pixels from a screenshot (`screencapture`). Never anything the meter
// writes for tests.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const paths = require('./paths');
const menubar = require('./menubar');
const png = require('./png');
const { sleep } = require('./procs');

const ax = (args) => JSON.parse(execFileSync(paths.meterAx, args, { encoding: 'utf8' }));

/** The top edge of each display, in the Accessibility API's screen points. */
function screenTops() {
  const script = 'ObjC.import("AppKit"); const s = $.NSScreen.screens; const h = s.objectAtIndex(0).frame.size.height;'
    + ' const tops = []; for (let i = 0; i < s.count; i++) { const f = s.objectAtIndex(i).frame;'
    + ' tops.push({ x: f.origin.x, y: h - (f.origin.y + f.size.height), width: f.size.width }); } JSON.stringify(tops)';
  return JSON.parse(execFileSync('osascript', ['-l', 'JavaScript', '-e', script], { encoding: 'utf8' }));
}

/**
 * The meter's item once it sits still in a menu bar, where the user can click it: a newly
 * launched status item is placed a moment after it is made. With more than one display, the
 * item shows in the menu bar of the display in use, at the top of that display.
 */
async function inMenuBar(pid) {
  const tops = screenTops();
  const shown = (i) => i && i.width > 0 && i.height > 0 && tops.some((t) => i.x >= t.x
    && i.x + i.width <= t.x + t.width && i.y >= t.y - 2 && i.y <= t.y + 40);
  // macOS hides status items while a full-screen app holds the display in use: wait a while
  // for the item to show again rather than click one the user cannot see.
  const deadline = Date.now() + 30000;
  let last = null;
  while (Date.now() < deadline) {
    const [item] = menubar.itemsOf(pid);
    if (shown(item) && last && item.x === last.x && item.y === last.y) return item;
    last = shown(item) ? item : null;
    await sleep(100);
  }
  throw new Error(`the meter's item never settled in a menu bar: ${JSON.stringify(menubar.itemsOf(pid))}; displays ${JSON.stringify(tops)}`);
}

/** The meter's one panel, as Accessibility reads it now. */
function panelWindow(pid) {
  const windows = ax(['windows', String(pid)]);
  if (windows.length !== 1) throw new Error(`expected one panel, saw ${windows.length} windows`);
  return windows[0];
}

/**
 * What the user sees in the open panel at one moment: its elements and a screenshot of it.
 * Returns the capture with the time it was taken.
 */
function captureNow(pid, item = null) {
  const window = panelWindow(pid);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-shot-'));
  const file = path.join(dir, 'panel.png');
  const at = Date.now();
  try {
    execFileSync('screencapture', ['-x', '-R',
      `${window.x},${window.y},${window.width},${window.height}`, file]);
    const image = png.read(file);
    return { item, window, image, scale: image.width / window.width, at };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

/** Presses the menu bar item without waiting for anything (to close an open panel). */
async function press(pid) {
  const item = await inMenuBar(pid);
  execFileSync(paths.meterAx, ['press', String(pid)]);
  return item;
}

/** Clicks the menu bar item (an Accessibility press, as an assistive app clicks it). */
async function click(pid) {
  const item = await press(pid);
  const deadline = Date.now() + 3000;
  let windows = [];
  while (windows.length === 0 && Date.now() < deadline) {
    await sleep(50);
    windows = ax(['windows', String(pid)]);
  }
  if (windows.length === 0) throw new Error('no panel dropped down after the click');
  return item;
}

/**
 * Clicks the menu bar item and, once a panel has dropped down, captures what the user sees at
 * that moment: the panel's elements and a screenshot of it.
 */
async function clickAndCapture(pid) {
  const item = await click(pid);
  // Let the panel finish drawing, then read it and photograph it at one moment.
  await sleep(150);
  return captureNow(pid, item);
}

// --- Colour ---

/** The hue (degrees) and chroma (0-255) of a pixel. */
function hueOf([r, g, b]) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const chroma = max - min;
  let hue = 0;
  if (chroma > 0) {
    if (max === r) hue = ((g - b) / chroma) % 6;
    else if (max === g) hue = (b - r) / chroma + 2;
    else hue = (r - g) / chroma + 4;
    hue = (hue * 60 + 360) % 360;
  }
  return { hue, chroma, max };
}

/** A coloured pixel: not the panel's greys, black or white. */
const isColoured = (pixel) => {
  const { chroma, max } = hueOf(pixel);
  return chroma >= 60 && max >= 90;
};

const hueDistance = (a, b) => {
  const d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
};

function meanHue(hues) {
  if (hues.length === 0) return null;
  const x = hues.reduce((s, h) => s + Math.cos((h * Math.PI) / 180), 0);
  const y = hues.reduce((s, h) => s + Math.sin((h * Math.PI) / 180), 0);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

/** Every pixel inside a box given in screen points, as { px, py (points), rgb }. */
function pixelsIn(capture, box) {
  const { window, image, scale } = capture;
  const out = [];
  const x0 = Math.max(0, Math.ceil((box.x - window.x) * scale));
  const x1 = Math.min(image.width, Math.floor((box.x + box.width - window.x) * scale));
  const y0 = Math.max(0, Math.ceil((box.y - window.y) * scale));
  const y1 = Math.min(image.height, Math.floor((box.y + box.height - window.y) * scale));
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      out.push({
        px: window.x + (x + 0.5) / scale, py: window.y + (y + 0.5) / scale, cx: x, cy: y, rgb: image.rgb(x, y),
      });
    }
  }
  return out;
}

// --- Reading the panel ---

const texts = (capture) => capture.window.elements.filter((e) => e.role === 'AXStaticText');

/** The static texts reading exactly `text`. */
const textsReading = (capture, text) => texts(capture).filter((e) => e.text === text);

/** The panel's graphs: images on screen. */
const graphs = (capture) => capture.window.elements.filter((e) => e.role === 'AXImage');

function theGraph(capture) {
  const found = graphs(capture);
  if (found.length !== 1) throw new Error(`expected one graph in the panel, found ${found.length}`);
  return found[0];
}

/** The legend: the one text that names the three lines and their values. */
function legend(capture) {
  const found = texts(capture).filter((e) => {
    const words = (e.words || []).map((w) => w.text);
    return ['CPU', 'GPU', 'RAM'].every((label) => words.includes(label)) && words.length >= 6;
  });
  if (found.length !== 1) throw new Error(`expected one legend naming CPU, found ${found.length}`);
  return found[0];
}

/** The legend's current value for a line, in percent, as the user reads it. */
function legendValue(capture, label) {
  const words = legend(capture).words;
  const i = words.findIndex((w) => w.text === label);
  if (i < 0 || i + 1 >= words.length) throw new Error(`the legend has no value for ${label}`);
  const m = /^(\d+\.\d)%$/.exec(words[i + 1].text);
  if (!m) throw new Error(`the legend's ${label} value reads "${words[i + 1].text}"`);
  return Number(m[1]);
}

/** The colour (hue) the legend gives each line's label: how the user tells the lines apart. */
function legendHues(capture) {
  const hues = {};
  for (const label of ['CPU', 'GPU', 'RAM']) {
    const word = legend(capture).words.find((w) => w.text === label);
    if (!word) throw new Error(`the legend does not name ${label}`);
    const coloured = pixelsIn(capture, word).filter((p) => isColoured(p.rgb));
    if (coloured.length < 10) throw new Error(`the legend's ${label} carries no colour`);
    hues[label] = meanHue(coloured.map((p) => hueOf(p.rgb).hue));
  }
  return hues;
}

/** The vertical centre of the one text reading `text`, in screen points. */
function centreOf(capture, text) {
  const found = textsReading(capture, text);
  if (found.length !== 1) throw new Error(`expected one "${text}" label, found ${found.length}`);
  return found[0].y + found[0].height / 2;
}

/**
 * The graph's coloured pixels, each with its place as the user reads it: `x` from 0 at the
 * graph's left edge to 1 at its right edge, `value` in percent on the scale its "0%" and
 * "100%" labels mark, and `line` the legend label whose colour it carries (null for none).
 */
function linePixels(capture) {
  const graph = theGraph(capture);
  const hues = legendHues(capture);
  const zero = centreOf(capture, '0%');
  const hundred = centreOf(capture, '100%');
  // The graph's whole width and a couple of points either side, so a line drawn at the very
  // edge (the five-minute edge is its left border) is read; the grey frame is not coloured.
  const inside = { x: graph.x - 2, y: graph.y - 1, width: graph.width + 4, height: graph.height + 2 };
  return pixelsIn(capture, inside).filter((p) => isColoured(p.rgb)).map((p) => {
    const { hue } = hueOf(p.rgb);
    let line = null;
    let best = 30;
    for (const [label, h] of Object.entries(hues)) {
      const d = hueDistance(hue, h);
      if (d < best) { best = d; line = label; }
    }
    return {
      cx: p.cx,
      cy: p.cy,
      x: (p.px - graph.x) / graph.width,
      value: ((zero - p.py) / (zero - hundred)) * 100,
      line,
      hue,
    };
  });
}

/** The panel's texts the user reads now, through Accessibility. */
const textsNow = (pid) => ax(['texts', String(pid)]);

/** The one text the user reads that starts with `prefix` ("Net ", "Disk "), or undefined. */
const lineStarting = (textList, prefix) => textList.find((t) => typeof t === 'string' && t.startsWith(prefix));

/**
 * Watches the open panel's texts through Accessibility for `durationMs`: `seen` holds
 * `{ at, texts }` each time they change, stamped by the watcher as it reads them.
 */
async function watchTexts(pid, durationMs) {
  const { spawn } = require('node:child_process');
  const readline = require('node:readline');
  const child = spawn(paths.meterAx, ['watch-texts', String(pid), String(durationMs)]);
  const seen = [];
  readline.createInterface({ input: child.stdout }).on('line', (line) => {
    const tab = line.indexOf('\t');
    seen.push({ at: Number(line.slice(0, tab)), texts: JSON.parse(line.slice(tab + 1)) });
  });
  const done = new Promise((resolve) => child.on('exit', resolve));
  const deadline = Date.now() + 3000;
  while (seen.length === 0 && Date.now() < deadline) await sleep(10);
  if (seen.length === 0) throw new Error('the Accessibility watcher saw no panel');
  return { seen, done, stop: () => child.kill('SIGTERM') };
}

module.exports = {
  textsNow, lineStarting, watchTexts,
  click, press, capture: captureNow, panelWindow, clickAndCapture, textsReading, theGraph, graphs, legend, legendValue,
  legendHues, linePixels, hueDistance, centreOf, pixelsIn, isColoured, hueOf,
};
