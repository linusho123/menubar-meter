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

/**
 * The meter's item once it sits still in the menu bar, where the user can click it: a newly
 * launched status item is placed a moment after it is made.
 */
async function inMenuBar(pid) {
  const shown = (i) => i && i.width > 0 && i.height > 0 && i.x >= 0 && i.y >= -2 && i.y <= 40;
  const deadline = Date.now() + 5000;
  let last = null;
  while (Date.now() < deadline) {
    const [item] = menubar.itemsOf(pid);
    if (shown(item) && last && item.x === last.x && item.y === last.y) return item;
    last = shown(item) ? item : null;
    await sleep(100);
  }
  throw new Error(`the meter's item never settled in the menu bar: ${JSON.stringify(menubar.itemsOf(pid))}`);
}

/**
 * Clicks the menu bar item (an Accessibility press, as an assistive app clicks it) and, once a
 * panel has dropped down, captures what the user sees at that moment: the panel's elements and
 * a screenshot of it. Returns the capture with the time it was taken.
 */
async function clickAndCapture(pid) {
  const item = await inMenuBar(pid);
  execFileSync(paths.meterAx, ['press', String(pid)]);
  const deadline = Date.now() + 3000;
  let windows = [];
  while (windows.length === 0 && Date.now() < deadline) {
    await sleep(50);
    windows = ax(['windows', String(pid)]);
  }
  if (windows.length === 0) throw new Error('no panel dropped down after the click');
  // Let the panel finish drawing, then read it and photograph it at one moment.
  await sleep(150);
  windows = ax(['windows', String(pid)]);
  if (windows.length !== 1) throw new Error(`expected one panel, saw ${windows.length} windows`);
  const [window] = windows;
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
      out.push({ px: window.x + (x + 0.5) / scale, py: window.y + (y + 0.5) / scale, rgb: image.rgb(x, y) });
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

/** The legend: the text that names the three lines. */
function legend(capture) {
  const found = texts(capture).filter((e) => (e.words || []).some((w) => w.text === 'CPU'));
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
  const inside = { x: graph.x + 1, y: graph.y + 1, width: graph.width - 2, height: graph.height - 2 };
  return pixelsIn(capture, inside).filter((p) => isColoured(p.rgb)).map((p) => {
    const { hue } = hueOf(p.rgb);
    let line = null;
    let best = 30;
    for (const [label, h] of Object.entries(hues)) {
      const d = hueDistance(hue, h);
      if (d < best) { best = d; line = label; }
    }
    return {
      x: (p.px - graph.x) / graph.width,
      value: ((zero - p.py) / (zero - hundred)) * 100,
      line,
      hue,
    };
  });
}

module.exports = {
  clickAndCapture, textsReading, theGraph, graphs, legend, legendValue, legendHues, linePixels,
  hueDistance, centreOf,
};
