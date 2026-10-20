'use strict';
// heavy-tasks.feature. Givens may describe the running tasks to the test reading source (their
// raw CPU and GPU rates and memory, and who runs them from where, taken from `ps` and `top` for
// the real macOS tasks the scenarios name), or run real tasks on the real Mac; every Then reads
// only what macOS shows: the panel's list through Accessibility and its pixels, `ps` for which
// tasks run, and the app in front as macOS reports it.
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const feeds = require('../support/feed');
const meter = require('../support/meter');
const menubar = require('../support/menubar');
const panel = require('../support/panel');
const paths = require('../support/paths');
const probes = require('../support/probes');
const procs = require('../support/procs');
const tasks = require('../support/tasks');

const required = (value, what) => {
  if (value === undefined || value === null) throw new Error(`world.${what} read before any step set it`);
  return value;
};
const percent = (text) => {
  const m = /^([\d.]+)%$/.exec(text.trim());
  if (!m) throw new Error(`not a percentage: "${text}"`);
  return Number(m[1]);
};
const ax = (args) => execFileSync(paths.meterAx, args, { encoding: 'utf8' });
const describeRows = (shown) => shown.rows.map((r) => `${r.name} ${JSON.stringify(r.values)} [${r.tags}] [${r.buttons.map((b) => b.text)}]`).join('; ');
const hasEnd = (row) => row.buttons.some((b) => b.text === 'End');

/** The scenario's fed tasks, by name. */
function fed(w) {
  if (!w.tasks) w.tasks = new Map();
  return w.tasks;
}

/** Sets a task's fields; a task keeps its process id from the moment it is first named. */
function setTask(w, name, fields) {
  const current = fed(w).get(name) || { pid: tasks.newPid() };
  fed(w).set(name, { ...current, name, ...fields });
}

/** The feed's task list: the scenario's tasks, plus the same quiet ones to fill the Mac. */
function taskFeed(w) {
  const macCores = w.cores;
  const named = [...fed(w).values()].map((t) => tasks.fedTask({ ...t, macCores }));
  if (!w.quiet) w.quiet = tasks.quietTasks(4, { cpuFrom: 2, macCores });
  return [...named, ...w.quiet];
}

/** Starts the test meter fed the scenario's tasks, unless a Given already started it. */
async function running(w) {
  if (w.meter) return w.meter;
  const values = feeds.readings({ cpu: 40, gpu: 10, ram: 40, temp: 50 });
  values.tasks = taskFeed(w);
  if (w.cores) values.cores = w.cores;
  if (w.gpuBusy !== undefined) values.gpuBusy = w.gpuBusy;
  return meter.launchWithFeed(w, values);
}

/** A real macOS task, as `ps` (its program and owner) or `top` (its owner) reports it. */
function realTask(name) {
  for (const line of execFileSync('ps', ['-axo', 'pid=,user=,comm='], { encoding: 'utf8' }).split('\n')) {
    const m = /^\s*(\d+)\s+(\S+)\s+(.+)$/.exec(line);
    if (m && path.basename(m[3]) === name && m[3].startsWith('/')) {
      return { pid: Number(m[1]), user: m[2], path: m[3] };
    }
  }
  const top = execFileSync('top', ['-l', '1', '-stats', 'pid,command,user'], { encoding: 'utf8' });
  for (const line of top.split('\n')) {
    const m = /^(\d+)\s+(.+?)\s+(\S+)\s*$/.exec(line);
    if (m && m[2] === name) return { pid: Number(m[1]), user: m[3], path: null };
  }
  throw new Error(`neither ps nor top lists ${name} on this Mac`);
}

const uidOf = (user) => Number(execFileSync('id', ['-u', user], { encoding: 'utf8' }).trim());

/** Moves the pointer as the mouse moves it; the scenario puts it back where it was. */
function movePointer(w, x, y) {
  if (!w.pointerWas) {
    w.pointerWas = JSON.parse(ax(['pointer']));
    w.defer(() => ax(['move', String(w.pointerWas.x), String(w.pointerWas.y)]));
  }
  ax(['move', String(x), String(y)]);
}

/** Every row is drawn plain: not one coloured pixel in any of them, tags included (D110). */
function assertPlain(capture, shown) {
  for (const row of shown.rows) {
    const coloured = panel.pixelsIn(capture, row.box).filter((p) => panel.isColoured(p.rgb));
    assert.strictEqual(coloured.length, 0, `${coloured.length} coloured pixels in ${row.name}'s row`);
  }
}

const centre = (box) => ({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
const inside = (point, box) => point.x >= box.x && point.x <= box.x + box.width
  && point.y >= box.y && point.y <= box.y + box.height;

module.exports = (reg) => {
  // --- Opening the panel ---

  reg.define(/^the user opens the panel$/, async (w) => {
    const m = await running(w);
    w.capture = await tasks.openAndRead(m.pid, w.expectRows || 5);
    w.shown = tasks.list(w.capture);
  });

  // --- The top five by CPU, then the GPU and RAM hogs (D108) ---

  reg.define(/^these tasks are running$/, (w, table) => {
    for (const row of table.hashes()) {
      setTask(w, row.task, { cpu: percent(row.cpu), gpu: percent(row.gpu), ram: percent(row.ram) });
    }
    w.expectRows = Math.min(fed(w).size, 7);
  });

  reg.define(/^the user sees the heavy-tasks list read, in order$/, (w, table) => {
    const capture = required(w.capture, 'capture');
    const shown = tasks.list(capture);
    // The list lies below the graph (D10), under its heading and its CPU, GPU and RAM columns.
    const graph = panel.theGraph(capture);
    assert.ok(shown.heading.y >= graph.y + graph.height, '"heavy tasks" is below the graph');
    const expected = table.hashes();
    const read = shown.rows.map((r) => ({
      task: r.name, tag: r.tags.join(' '), button: r.buttons.map((b) => b.text).join(' '),
    }));
    assert.deepStrictEqual(read, expected, `the list reads ${describeRows(shown)}`);
    for (const row of shown.rows) {
      assert.deepStrictEqual(Object.keys(row.values).sort(), ['CPU', 'GPU', 'RAM'],
        `${row.name}'s row shows a value under CPU, GPU and RAM`);
    }
    // The tags are plain words in the row's own style (D110).
    assertPlain(capture, shown);
  });

  // --- An extra row only for a real hog (D109) ---

  reg.define(/^the biggest (GPU|RAM) user is not among the five CPU rows$/, (w, kind) => {
    w.kind = kind;
    [30, 25, 20, 15, 10].forEach((cpu, i) => setTask(w, `cpu${i + 1}`, { cpu, gpu: 1, ram: 2 }));
    setTask(w, 'hog', { cpu: 1, gpu: 0.5, ram: 1 });
  });

  reg.define(/^it uses ([\d.]+%) of the (GPU|Mac's memory)$/, (w, share, whole) => {
    const kind = required(w.kind, 'kind');
    assert.strictEqual(whole, kind === 'GPU' ? 'GPU' : "Mac's memory", 'the share is of the right whole');
    setTask(w, 'hog', kind === 'GPU' ? { gpu: percent(share) } : { ram: percent(share) });
  });

  reg.define(/^the user sees its extra row tagged "(GPU|RAM)" is (absent|listed)$/, (w, kind, shown) => {
    const list = required(w.shown, 'shown');
    const tagged = list.rows.filter((r) => r.tags.includes(kind));
    if (shown === 'listed') {
      assert.strictEqual(list.rows.length, 6, `five CPU rows and the extra row: ${describeRows(list)}`);
      assert.strictEqual(tagged.length, 1, `one row tagged ${kind}: ${describeRows(list)}`);
      assert.strictEqual(list.rows[5], tagged[0], 'the extra row comes after the five CPU rows');
      assert.strictEqual(tagged[0].name, 'hog', `the biggest ${kind} user is the extra row`);
    } else {
      assert.strictEqual(tagged.length, 0, `no row tagged ${kind}: ${describeRows(list)}`);
      assert.strictEqual(list.rows.length, 5, `just the five CPU rows: ${describeRows(list)}`);
      assert.strictEqual(tasks.rowsNamed(list, 'hog').length, 0, 'the GPU or RAM user is not listed');
    }
  });

  // --- A task's CPU (D54) and RAM (D107), as shares of this Mac ---

  reg.define(/^this Mac has (\d+) CPU cores$/, (w, cores) => {
    // The real Mac's own count; the meter divides by it.
    assert.strictEqual(probes.cpuCount(), Number(cores), 'sysctl hw.ncpu');
  });

  reg.define(/^one task is fully using (\d+) of them$/, (w, cores) => {
    setTask(w, 'stand-in', { busyCores: Number(cores), ram: 1 });
    w.taskName = 'stand-in';
  });

  reg.define(/^this Mac has (\d+) GB of memory$/, (w, gb) => {
    assert.strictEqual(probes.memsize(), Number(gb) * tasks.GiB, 'sysctl hw.memsize');
  });

  reg.define(/^one task in the list uses ([\d.]+) GB of it$/, (w, gb) => {
    setTask(w, 'stand-in', { cpu: 30, memory: Math.round(Number(gb) * tasks.GiB) });
    w.taskName = 'stand-in';
  });

  reg.define(/^the user sees that task's row read "(.+)" under (CPU|RAM)$/, (w, value, column) => {
    const list = required(w.shown, 'shown');
    const rows = tasks.rowsNamed(list, required(w.taskName, 'taskName'));
    assert.strictEqual(rows.length, 1, `one row for the task: ${describeRows(list)}`);
    assert.strictEqual(rows[0].values[column], value);
  });

  // --- Counted against the Mac it runs on (D80) ---

  reg.define(/^the meter runs on a Mac with (\d+) CPU cores$/, (w, cores) => {
    w.cores = Number(cores);
  });

  reg.define(/^one task fully uses all of them$/, (w) => {
    setTask(w, 'stand-in', { busyCores: required(w.cores, 'cores'), ram: 1 });
    w.taskName = 'stand-in';
  });

  reg.define(/^the user sees that task's row read "100\.0%" under CPU, on a Mac of (\d+) cores$/, (w, cores) => {
    assert.strictEqual(Number(cores), required(w.cores, 'cores'), 'the Mac the Given set up');
    const list = required(w.shown, 'shown');
    const rows = tasks.rowsNamed(list, required(w.taskName, 'taskName'));
    assert.strictEqual(rows.length, 1, `one row for the task: ${describeRows(list)}`);
    assert.strictEqual(rows[0].values.CPU, '100.0%');
  });

  // --- A task's GPU (D49) ---

  reg.define(/^Activity Monitor's "% GPU" column reads "([\d.]+)" for (\w+)$/, (w, gpu, name) => {
    // Activity Monitor's figure is the task's part of all GPU clients' time, of the GPU's busy
    // figure (D49): the GPU is 30% busy, its clients together keep it 50% of the time, and the
    // task's part of that is `gpu / 30`. The task's own time (20.5%) is not the figure.
    const busy = 30;
    const clients = 50;
    const own = (Number(gpu) / busy) * clients;
    w.gpuBusy = busy;
    setTask(w, name, { gpu: own });
    setTask(w, 'WindowServer', { cpu: 0.1, gpu: clients - own - 0.4, uid: 88 });
  });

  reg.define(/^(\w+) is in the heavy-tasks list$/, (w, name) => {
    setTask(w, name, { cpu: 25 });
  });

  reg.define(/^the user sees (\w+)'s row read "(.+)" under (CPU|GPU|RAM)$/, (w, name, value, column) => {
    const list = required(w.shown, 'shown');
    const rows = tasks.rowsNamed(list, name);
    assert.strictEqual(rows.length, 1, `one row for ${name}: ${describeRows(list)}`);
    assert.strictEqual(rows[0].values[column], value);
  });

  // --- The system mark (D99, D57) ---

  reg.define(/^(\w+), whose program (.+), is among the top five by CPU$/, (w, name, where) => {
    const real = realTask(name);
    const me = os.userInfo().username;
    if (where === 'lives in /System and runs as the user') {
      assert.ok(real.path && real.path.startsWith('/System/'), `ps: ${name}'s program is ${real.path}`);
      assert.strictEqual(real.user, me, `ps: ${name} runs as ${real.user}`);
    } else {
      const m = /^runs as (\S+), not as the user$/.exec(where);
      assert.ok(m, `a program that ${where}`);
      assert.strictEqual(real.user, m[1], `${name} runs as ${real.user}`);
      assert.notStrictEqual(real.user, me);
    }
    // It ranks third by CPU, among the user's own tasks.
    [['node', 30], ['Xcode', 25], ['Mail', 15], ['Notes', 10]].forEach(([n, cpu]) => setTask(w, n, { cpu }));
    setTask(w, name, { cpu: 20, uid: uidOf(real.user), path: real.path });
    w.rank = 2;
  });

  reg.define(/^the user sees (\w+) listed in its CPU rank, tagged "system"$/, (w, name) => {
    const list = required(w.shown, 'shown');
    const row = list.rows[required(w.rank, 'rank')];
    assert.ok(row && row.name === name, `${name} is in row ${w.rank + 1}: ${describeRows(list)}`);
    assert.deepStrictEqual(row.tags, ['system']);
  });

  reg.define(/^(\w+)'s row has no End button$/, (w, name) => {
    const list = required(w.shown, 'shown');
    const rows = tasks.rowsNamed(list, name);
    assert.strictEqual(rows.length, 1, `one row for ${name}: ${describeRows(list)}`);
    assert.deepStrictEqual(rows[0].buttons, [], `${name}'s row has no button`);
  });

  reg.define(
    /^node, run as the user from ~\/\.nvm, and Xcode, run as the user from \/Applications, are in the heavy-tasks list$/,
    (w) => {
      // The real node this Mac runs, from the user's own ~/.nvm.
      const node = process.execPath;
      assert.ok(node.startsWith(path.join(os.homedir(), '.nvm') + path.sep), `node runs from ${node}`);
      setTask(w, 'node', { cpu: 30, path: node, uid: tasks.myUid() });
      setTask(w, 'Xcode', { cpu: 25, path: '/Applications/Xcode.app/Contents/MacOS/Xcode', uid: tasks.myUid() });
      [['Mail', 15], ['Notes', 10], ['Maps', 5]].forEach(([n, cpu]) => setTask(w, n, { cpu }));
    });

  reg.define(/^the user sees an End button on node's row and on Xcode's row$/, (w) => {
    const list = required(w.shown, 'shown');
    for (const name of ['node', 'Xcode']) {
      const rows = tasks.rowsNamed(list, name);
      assert.strictEqual(rows.length, 1, `one row for ${name}: ${describeRows(list)}`);
      assert.deepStrictEqual(rows[0].buttons.map((b) => b.text), ['End'], `${name}'s row has End`);
      assert.deepStrictEqual(rows[0].tags, [], `${name}'s row is not marked`);
    }
  });

  reg.define(/^the meter itself ranks among the top five tasks by CPU$/, async (w) => {
    [['node', 30], ['Xcode', 25], ['Mail', 15], ['Notes', 10]].forEach(([n, cpu]) => setTask(w, n, { cpu }));
    const m = await running(w);
    // The meter's own process, by its real pid and program, at 20% of the Mac: third.
    setTask(w, 'Meter', { cpu: 20, pid: m.pid, path: paths.testApp, uid: tasks.myUid() });
    w.feed.set({ tasks: taskFeed(w) });
    w.rank = 2;
  });

  reg.define(/^the user sees the meter's own row in its CPU rank, tagged "system", with no End button$/, (w) => {
    const list = required(w.shown, 'shown');
    const row = list.rows[required(w.rank, 'rank')];
    assert.ok(row && row.name === 'Meter', `the meter is in row ${w.rank + 1}: ${describeRows(list)}`);
    assert.deepStrictEqual(row.tags, ['system']);
    assert.deepStrictEqual(row.buttons, [], 'no End button');
  });

  reg.define(/^the user still sees the "Quit Meter" row at the bottom of the panel$/, (w) => {
    const capture = required(w.capture, 'capture');
    const quit = capture.window.elements.filter((e) => e.role === 'AXButton' && e.text === 'Quit Meter');
    assert.strictEqual(quit.length, 1, 'one "Quit Meter" row');
    const bottom = Math.max(...capture.window.elements.filter((e) => e.width > 0).map((e) => e.y + e.height));
    assert.strictEqual(quit[0].y + quit[0].height, bottom, '"Quit Meter" is the lowest thing in the panel');
    assert.ok(capture.window.y + capture.window.height - (quit[0].y + quit[0].height) <= 16,
      '"Quit Meter" sits at the bottom edge of the panel');
    const list = tasks.list(capture);
    assert.ok(quit[0].y >= list.openRow.y + list.openRow.height, '"Quit Meter" is below "Open Activity Monitor…"');
  });

  // --- Ties (D58) ---

  reg.define(/^"(\w+)" and "(\w+)" both sit at exactly ([\d.]+)% CPU, tied for the fifth row$/, (w, a, b, cpu) => {
    [['node', 30], ['Xcode', 25], ['Safari', 20], ['Mail', 15]].forEach(([n, c]) => setTask(w, n, { cpu: c }));
    // In the order the Given names them, so the later name has the higher process id and
    // comes later in the system's list.
    setTask(w, a, { cpu: Number(cpu) });
    setTask(w, b, { cpu: Number(cpu) });
    w.tie = `${Number(cpu).toFixed(1)}%`;
  });

  reg.define(/^the user sees "(\w+)" in the fifth row and "(\w+)" not in the five CPU rows$/, (w, fifth, out) => {
    const list = required(w.shown, 'shown');
    assert.strictEqual(list.rows[4].name, fifth, describeRows(list));
    assert.strictEqual(list.rows[4].values.CPU, required(w.tie, 'tie'));
    assert.ok(list.rows.slice(0, 5).every((r) => r.name !== out), describeRows(list));
  });

  // --- The row under the pointer holds (D101) ---

  reg.define(/^the pointer rests on the End button of (\w+)'s row, and (\w+) is just below it$/, async (w, held, below) => {
    [['Safari', 40], [held, 25], [below, 20], ['Mail', 10], ['Notes', 5]].forEach(([n, cpu]) => setTask(w, n, { cpu }));
    const m = await running(w);
    w.capture = await tasks.openAndRead(m.pid, 5);
    const list = tasks.list(w.capture);
    const index = list.rows.findIndex((r) => r.name === held);
    assert.ok(index >= 0 && list.rows[index + 1].name === below, `${below} is just below ${held}: ${describeRows(list)}`);
    const end = list.rows[index].buttons.find((b) => b.text === 'End');
    assert.ok(end, `${held}'s row has End`);
    const at = centre(end);
    movePointer(w, at.x, at.y);
    await procs.sleep(300);
    w.held = held;
    w.below = below;
  });

  reg.define(/^(\w+) passes (\w+) on CPU at the next refresh$/, async (w, passer, passed) => {
    const m = required(w.meter, 'meter');
    setTask(w, passer, { cpu: 30 });
    setTask(w, passed, { cpu: 26 });
    w.updated = { [passer]: '30.0%', [passed]: '26.0%' };
    w.feed.set({ tasks: taskFeed(w) });
    // The next refresh: the user sees the new numbers.
    w.capture = await tasks.waitForList(m.pid, (l) => Object.entries(w.updated)
      .every(([n, v]) => tasks.rowsNamed(l, n)[0]?.values.CPU === v), 3000, 'the refresh with the new numbers');
  });

  reg.define(/^the user sees the row under the pointer still show (\w+), with its updated numbers$/, (w, name) => {
    const list = tasks.list(required(w.capture, 'capture'));
    const pointer = JSON.parse(ax(['pointer']));
    const under = list.rows.filter((r) => pointer.y >= r.box.y && pointer.y <= r.box.y + r.box.height);
    assert.strictEqual(under.length, 1, `one row under the pointer at ${JSON.stringify(pointer)}: ${describeRows(list)}`);
    assert.strictEqual(under[0].name, name, describeRows(list));
    assert.strictEqual(under[0].values.CPU, required(w.updated, 'updated')[name]);
    assert.ok(under[0].buttons.some((b) => b.text === 'End' && inside(pointer, b)), 'the pointer rests on its End button');
  });

  reg.define(/^when the pointer leaves the button, the user sees (\w+) move above (\w+)$/, async (w, above, below) => {
    const m = required(w.meter, 'meter');
    const list = tasks.list(required(w.capture, 'capture'));
    const row = tasks.rowsNamed(list, below)[0];
    // Off the button, onto the row's own name.
    const name = centre(row.nameElement);
    movePointer(w, name.x, name.y);
    const index = (l, n) => l.rows.findIndex((r) => r.name === n);
    await tasks.waitForList(m.pid, (l) => index(l, above) >= 0 && index(l, above) < index(l, below),
      1500, `${above} above ${below}`);
  });

  // --- No nudging (D110), against the real Mac ---

  reg.define(/^(\w+) has used (\d+)% of the Mac's CPU for the last (\d+) minutes$/, async (w, name, cpu, minutes) => {
    assert.strictEqual(name, 'node', 'the stand-in hog is a real node');
    const cores = probes.cpuCount();
    // A real node task keeping every core busy: the hog the user sees, run by the harness.
    const load = procs.start(process.execPath, [path.join(__dirname, '..', 'support', 'load.js'), String(cores)]);
    w.defer(() => procs.end(load));
    w.load = load;
    // The meter has been running the whole hour, with the Mac at that load.
    const past = new feeds.Past(Number(minutes) * 60, { cpu: Number(cpu) });
    await meter.launchWithFeed(w, past.feed());
    await procs.sleep(3000);
    const used = probes.psCpu(load.pid) / cores;
    assert.ok(used >= Number(cpu) - 15, `ps: node uses ${used.toFixed(1)}% of the Mac`);
  });

  reg.define(/^the user has clicked nothing in the meter$/, (w) => {
    const m = required(w.meter, 'meter');
    assert.deepStrictEqual(JSON.parse(ax(['windows', String(m.pid)])), [], 'the meter shows no window');
  });

  reg.define(/^another minute passes$/, async (w) => {
    const m = required(w.meter, 'meter');
    w.windowsSeen = [];
    w.titlesSeen = new Set();
    const end = Date.now() + 60000;
    while (Date.now() < end) {
      const windows = JSON.parse(ax(['windows', String(m.pid)]));
      if (windows.length > 0) w.windowsSeen.push(...windows.map((x) => x.title || '(untitled)'));
      for (const item of menubar.itemsOf(m.pid)) w.titlesSeen.add(item.title);
      await procs.sleep(1000);
    }
  });

  reg.define(/^Activity Monitor still lists (\w+) as running$/, (w, name) => {
    const load = required(w.load, 'load');
    assert.ok(procs.isRunning(load), `ps: the ${name} task (pid ${load.pid}) is still running`);
    const comm = execFileSync('ps', ['-o', 'comm=', '-p', String(load.pid)], { encoding: 'utf8' }).trim();
    assert.strictEqual(path.basename(comm), name);
  });

  reg.define(/^the user sees (\w+)'s row with an ordinary End button and no colour, icon, highlight, warning or prompt$/, async (w, name) => {
    const m = required(w.meter, 'meter');
    // Nothing came up on its own while the minute passed: no window, and the menu bar item
    // only ever read its plain values.
    assert.deepStrictEqual(required(w.windowsSeen, 'windowsSeen'), [], 'the meter put up no window');
    for (const title of w.titlesSeen) assert.ok(menubar.fields(title), `the item read "${title}"`);
    await panel.click(m.pid);
    const capture = await tasks.waitForList(m.pid, (l) => tasks.rowsNamed(l, name)
      .some((r) => r.values.CPU && percent(r.values.CPU) >= 50), 5000, `${name}'s row`);
    const list = tasks.list(capture);
    const row = tasks.rowsNamed(list, name).find((r) => percent(r.values.CPU) >= 50);
    assert.deepStrictEqual(row.buttons.map((b) => b.text), ['End'], 'an End button');
    assert.deepStrictEqual(row.tags, [], 'no words beyond its name and values');
    assert.deepStrictEqual(row.images, [], 'no icon');
    // Drawn like every other row: not one coloured pixel, and the same background.
    assertPlain(capture, { rows: [row] });
    // Its background, the colour most of its pixels share, is every other row's.
    const background = (r) => {
      const counts = new Map();
      for (const p of panel.pixelsIn(capture, r.box)) {
        const key = p.rgb.join(',');
        counts.set(key, (counts.get(key) || 0) + 1);
      }
      return [...counts.entries()].sort((a, b) => b[1] - a[1])[0][0].split(',').map(Number);
    };
    const own = background(row);
    for (const other of list.rows.filter((r) => r !== row)) {
      const theirs = background(other);
      assert.ok(own.every((c, i) => Math.abs(c - theirs[i]) <= 3),
        `${name}'s row is drawn on ${own}, ${other.name}'s on ${theirs}: no highlight`);
    }
    // Nothing else in the panel urges anything: one window, and no word of warning.
    assert.strictEqual(JSON.parse(ax(['windows', String(m.pid)])).length, 1, 'just the panel');
    const words = capture.window.elements.map((e) => e.text).join(' ');
    assert.ok(!/warning|hog|consider|recommend|should|!/i.test(words), `the panel reads: ${words}`);
  });

  // --- Open Activity Monitor (D59) ---

  reg.define(/^the panel is open$/, async (w) => {
    [['node', 30], ['Xcode', 25], ['Safari', 20], ['Mail', 15], ['Notes', 10], ['Maps', 5]]
      .forEach(([n, cpu]) => setTask(w, n, { cpu }));
    // Activity Monitor is not the app in front to begin with (an Activity Monitor left in
    // front would let the Then pass with no click at all): the Finder is brought forward.
    execFileSync('osascript', ['-e', 'tell application id "com.apple.finder" to activate']);
    const m = await running(w);
    w.capture = await tasks.openAndRead(m.pid, 5);
    w.topFive = tasks.list(w.capture).rows.map((r) => r.name);
    assert.deepStrictEqual(w.topFive, ['node', 'Xcode', 'Safari', 'Mail', 'Notes']);
  });

  reg.define(/^the user clicks "Open Activity Monitor…" below the heavy-tasks list$/, (w) => {
    const m = required(w.meter, 'meter');
    const list = tasks.list(required(w.capture, 'capture'));
    const last = list.rows[list.rows.length - 1];
    assert.ok(list.openRow.y >= last.box.y + last.box.height, 'the row is below the list');
    const running = (() => {
      try {
        return execFileSync('pgrep', ['-x', 'Activity Monitor'], { encoding: 'utf8' }).trim().split('\n').map(Number);
      } catch {
        return [];
      }
    })();
    const before = JSON.parse(ax(['front']));
    assert.notStrictEqual(before.bundle, 'com.apple.ActivityMonitor', 'Activity Monitor is not in front before the click');
    w.clickedAt = Date.now();
    ax(['press-button', String(m.pid), 'Open Activity Monitor…']);
    // An Activity Monitor this click started is the harness's to quit again, politely; one the
    // user had open is left as it was.
    w.defer(async () => {
      const front = JSON.parse(ax(['front']));
      if (front.bundle !== 'com.apple.ActivityMonitor' || running.includes(front.pid)) return;
      const started = procs.startTimeOf(front.pid);
      if (!started || new Date(started).getTime() < w.clickedAt - 2000) return;
      execFileSync('osascript', ['-e', 'tell application id "com.apple.ActivityMonitor" to quit']);
    });
  });

  reg.define(/^the user sees Activity Monitor open in front$/, async (w) => {
    let front;
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      front = JSON.parse(ax(['front']));
      if (front.bundle === 'com.apple.ActivityMonitor') break;
      await procs.sleep(200);
    }
    assert.strictEqual(front.bundle, 'com.apple.ActivityMonitor', `in front: ${front.name}`);
    let windows = 0;
    while (windows === 0 && Date.now() < deadline) {
      windows = Number(execFileSync('osascript', ['-e',
        'tell application "System Events" to count windows of (first process whose bundle identifier is "com.apple.ActivityMonitor")'],
      { encoding: 'utf8' }).trim());
      if (windows === 0) await procs.sleep(200);
    }
    assert.ok(windows > 0, 'Activity Monitor shows a window');
  });

  reg.define(/^the panel's own list still shows the top five by CPU$/, async (w) => {
    const m = required(w.meter, 'meter');
    await procs.sleep(1000);
    const list = tasks.listNow(m.pid);
    assert.deepStrictEqual(list.rows.map((r) => r.name), required(w.topFive, 'topFive'), describeRows(list));
    assert.ok(list.rows.every((r) => r.tags.length === 0), 'five CPU rows');
  });
};
