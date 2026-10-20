'use strict';
// The heavy-tasks list. Givens describe tasks for the test reading source (raw CPU and GPU
// rates and memory, never the meter's own results); Thens read the list the user sees in the
// panel through Accessibility, row by row as it lies on screen, and its pixels.
const { execFileSync } = require('node:child_process');
const paths = require('./paths');
const panel = require('./panel');
const probes = require('./probes');
const { physicalMemory } = require('./feed');
const { sleep } = require('./procs');

const GiB = 2 ** 30;
const DASH = '–';
const myUid = () => Number(execFileSync('id', ['-u'], { encoding: 'utf8' }).trim());

// Fed tasks get process ids no Mac ever gives (macOS's highest is 99998), so nothing the
// harness describes can be taken for a real process.
let nextPid = 900001;
const newPid = () => nextPid++;

/**
 * A task for the test reading source, given as the user would read it: `cpu` in percent of the
 * whole Mac (of `macCores` cores), `gpu` in percent of the GPU's time, `ram` in percent of the
 * Mac's memory (or `memory` in bytes). The feed carries the raw rates the system would show:
 * CPU cores kept busy, the share of GPU time, bytes of memory.
 */
function fedTask({
  name, cpu = 0, busyCores, gpu = 0, ram, memory, uid, path, pid, macCores,
}) {
  const cores = macCores ?? probes.cpuCount();
  return {
    pid: pid ?? newPid(),
    started: 1,
    name,
    uid: uid ?? myUid(),
    path: path === undefined ? `/Users/stand-in/bin/${name}` : path,
    busyCores: busyCores ?? (cpu / 100) * cores,
    gpuShare: gpu / 100,
    memory: memory ?? Math.round(((ram ?? 1) / 100) * physicalMemory()),
  };
}

/** Light tasks to fill the list around the ones a scenario names: low CPU, GPU and RAM. */
function quietTasks(count, { cpuFrom = 2, macCores } = {}) {
  return Array.from({ length: count }, (_, i) => fedTask({
    name: `quiet${i + 1}`, cpu: Math.max(0.1, cpuFrom - i * 0.3), gpu: 0.1, ram: 0.5, macCores,
  }));
}

// --- Reading the list ---

const isValue = (text) => /^\d+\.\d%$/.test(text) || text === DASH;
const centreY = (e) => e.y + e.height / 2;

/** The one element of `role` reading exactly `text`. */
function only(capture, role, text) {
  const found = capture.window.elements.filter((e) => e.role === role && e.text === text);
  if (found.length !== 1) throw new Error(`expected one ${role} "${text}" in the panel, found ${found.length}`);
  return found[0];
}

/**
 * The heavy-tasks list as the user reads it: its heading and column headings, and each row in
 * order from the top, with the row's name, its values under CPU, GPU and RAM, its other words
 * (tags) and its buttons, and the box it takes on screen.
 */
function list(capture) {
  const heading = only(capture, 'AXStaticText', 'heavy tasks');
  const headings = {};
  for (const column of ['CPU', 'GPU', 'RAM']) {
    const found = capture.window.elements.filter((e) => e.role === 'AXStaticText' && e.text === column
      && Math.abs(centreY(e) - centreY(heading)) <= 4);
    if (found.length !== 1) throw new Error(`expected one "${column}" column heading beside "heavy tasks", found ${found.length}`);
    headings[column] = found[0];
  }
  const openRow = only(capture, 'AXButton', 'Open Activity Monitor…');
  const top = heading.y + heading.height;
  const bottom = openRow.y;
  const inList = capture.window.elements.filter((e) => (e.role === 'AXStaticText' || e.role === 'AXButton'
    || e.role === 'AXImage') && e.width > 0 && centreY(e) > top && centreY(e) < bottom);
  // Rows: elements whose vertical centres lie together.
  const lines = [];
  for (const e of [...inList].sort((a, b) => centreY(a) - centreY(b))) {
    const line = lines.find((l) => Math.abs(centreY(l[0]) - centreY(e)) <= 5);
    if (line) line.push(e); else lines.push([e]);
  }
  const rows = lines.map((elements) => {
    const texts = elements.filter((e) => e.role === 'AXStaticText').sort((a, b) => a.x - b.x);
    const values = {};
    const words = [];
    for (const t of texts) {
      const column = isValue(t.text) && Object.entries(headings).find(([, h]) => Math.abs((h.x + h.width) - (t.x + t.width)) <= 6);
      if (column) values[column[0]] = t.text; else words.push(t);
    }
    const [name, ...tags] = words;
    const left = Math.min(...elements.map((e) => e.x));
    const right = Math.max(...elements.map((e) => e.x + e.width));
    const y0 = Math.min(...elements.map((e) => e.y));
    const y1 = Math.max(...elements.map((e) => e.y + e.height));
    return {
      name: name ? name.text : '',
      nameElement: name,
      values,
      tags: tags.map((t) => t.text),
      buttons: elements.filter((e) => e.role === 'AXButton'),
      images: elements.filter((e) => e.role === 'AXImage'),
      elements,
      box: { x: left, y: y0, width: right - left, height: y1 - y0 },
    };
  });
  return { heading, headings, rows, openRow };
}

/** The panel's list now, without a screenshot. */
function listNow(pid) {
  return list({ window: panel.panelWindow(pid) });
}

/** Waits until the list the user sees satisfies `predicate`; returns a full capture of it. */
async function waitForList(pid, predicate, timeoutMs, what) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() < deadline) {
    try {
      last = listNow(pid);
      if (predicate(last)) {
        const capture = panel.capture(pid);
        const shown = list(capture);
        if (predicate(shown)) return capture;
      }
    } catch (error) {
      last = error.message;
    }
    await sleep(100);
  }
  const seen = last && last.rows ? last.rows.map((r) => `${r.name} ${JSON.stringify(r.values)} ${r.tags} ${r.buttons.map((b) => b.text)}`) : last;
  throw new Error(`timed out after ${timeoutMs} ms waiting for ${what}; the list read ${JSON.stringify(seen)}`);
}

/** Opens the panel by clicking the menu bar item and waits for the list to show `rows` rows. */
async function openAndRead(pid, rows, what = `the list with ${rows} rows`) {
  const item = await panel.click(pid);
  const capture = await waitForList(pid, (l) => l.rows.length >= rows, 5000, what);
  capture.item = item;
  return capture;
}

/** The rows named `name`. */
const rowsNamed = (shown, name) => shown.rows.filter((r) => r.name === name);

module.exports = {
  fedTask, quietTasks, newPid, list, listNow, waitForList, openAndRead, rowsNamed, myUid, GiB, DASH,
};
