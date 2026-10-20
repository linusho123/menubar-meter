'use strict';
// The heavy-tasks list against the real Mac: real tasks the harness runs, their values checked by
// macOS's own tools (ps, top) and by Activity Monitor's own % GPU column, read through
// Accessibility. These back the scenarios that describe their tasks to the test reading source;
// they never stand in for a scenario.
const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const paths = require('./support/paths');
const procs = require('./support/procs');
const menubar = require('./support/menubar');
const probes = require('./support/probes');
const tasks = require('./support/tasks');

const run = (file, args) => execFileSync(file, args, { encoding: 'utf8' }).trim();
const value = (text) => Number.parseFloat(text);
const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];

async function withRealMeter(body) {
  const meter = procs.start(paths.releaseApp);
  try {
    await menubar.waitForItem(meter.pid, (i) => !!menubar.fields(i.title), 10000, 'the meter');
    await body(meter);
  } finally {
    await procs.end(meter);
  }
}

/** `top`'s MEM for a process (its physical footprint, as Activity Monitor's Memory), in bytes. */
function topMemory(pid) {
  const lines = run('top', ['-l', '1', '-pid', String(pid), '-stats', 'pid,mem']).split('\n');
  const m = /^\s*\d+\s+([\d.]+)([BKMG])\+?\s*$/.exec(lines[lines.length - 1]);
  if (!m) throw new Error(`top reads "${lines[lines.length - 1]}"`);
  return Number(m[1]) * { B: 1, K: 2 ** 10, M: 2 ** 20, G: 2 ** 30 }[m[2]];
}

test('a real task\'s CPU and RAM in the list agree with ps and top', async () => {
  const cores = probes.cpuCount();
  const load = procs.start(process.execPath, [path.join(__dirname, 'support', 'load.js'), '5', '1024']);
  try {
    await procs.sleep(3000);
    await withRealMeter(async (meter) => {
      await tasks.openAndRead(meter.pid, 5);
      const seen = [];
      for (let i = 0; i < 6; i++) {
        await procs.sleep(600);
        const row = tasks.rowsNamed(tasks.listNow(meter.pid), 'node')
          .sort((a, b) => value(b.values.CPU) - value(a.values.CPU))[0];
        assert.ok(row, 'the busy node task is listed');
        seen.push(row);
      }
      const cpu = median(seen.map((r) => value(r.values.CPU)));
      const ps = probes.psCpu(load.pid) / cores;
      assert.ok(Math.abs(cpu - ps) <= 4, `the list reads ${cpu}% CPU; ps ${ps.toFixed(1)}% of the Mac`);
      assert.ok(Math.abs(cpu - (5 / cores) * 100) <= 4, `five busy cores of ${cores}: ${cpu}%`);
      const ram = value(seen[seen.length - 1].values.RAM);
      const top = (topMemory(load.pid) / probes.memsize()) * 100;
      assert.ok(Math.abs(ram - top) <= 0.3, `the list reads ${ram}% RAM; top ${top.toFixed(2)}% of the memory`);
      const last = seen[seen.length - 1];
      assert.deepStrictEqual(last.buttons.map((b) => b.text), ['End'], 'the user\'s own node has End');
      assert.deepStrictEqual(last.tags, []);
      // macOS's own tasks and the meter, wherever they are listed, are system.
      for (const row of tasks.listNow(meter.pid).rows) {
        if (['Meter', 'WindowServer', 'loginwindow', 'Dock', 'kernel_task'].includes(row.name)) {
          assert.ok(row.tags.includes('system') && row.buttons.length === 0, `${row.name} is system`);
        }
      }
    });
  } finally {
    await procs.end(load);
  }
});

test('a real task\'s GPU in the list agrees with Activity Monitor\'s % GPU', async () => {
  const runningBefore = (() => {
    try {
      return run('pgrep', ['-x', 'Activity Monitor']).split('\n').map(Number);
    } catch {
      return [];
    }
  })();
  const gpu = procs.start(paths.gpuLoad);
  try {
    // Activity Monitor keeps its columns up to date while its window is in front.
    run('open', ['-b', 'com.apple.ActivityMonitor']);
    let am = null;
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline) {
      const pid = Number(run('pgrep', ['-nx', 'Activity Monitor']));
      try {
        am = { pid, gpu: value(run(paths.meterAx, ['cell', String(pid), 'PID', String(gpu.pid), '% GPU'])) };
        if (am.gpu >= 5) break;
      } catch {
        am = null;
      }
      await procs.sleep(1000);
    }
    assert.ok(am && am.gpu >= 5, `Activity Monitor's % GPU for the stand-in: ${JSON.stringify(am)}`);
    await withRealMeter(async (meter) => {
      await tasks.openAndRead(meter.pid, 5);
      const ours = [];
      const theirs = [];
      for (let i = 0; i < 8; i++) {
        await procs.sleep(700);
        const row = tasks.rowsNamed(tasks.listNow(meter.pid), 'meter-gpu-load')[0];
        assert.ok(row, 'the GPU stand-in is listed');
        ours.push(value(row.values.GPU));
        theirs.push(value(run(paths.meterAx, ['cell', String(am.pid), 'PID', String(gpu.pid), '% GPU'])));
      }
      const meterGpu = median(ours);
      const amGpu = median(theirs);
      assert.ok(Math.abs(meterGpu - amGpu) <= 10,
        `the list reads ${ours.join(', ')}% GPU; Activity Monitor ${theirs.join(', ')}`);
      const row = tasks.rowsNamed(tasks.listNow(meter.pid), 'meter-gpu-load')[0];
      assert.ok(row.tags.includes('GPU') || row.tags.length === 0, `its tags: ${row.tags}`);
    });
  } finally {
    await procs.end(gpu);
    // An Activity Monitor this test started is quit again, politely; the user's is left open.
    const now = (() => {
      try {
        return run('pgrep', ['-x', 'Activity Monitor']).split('\n').map(Number);
      } catch {
        return [];
      }
    })();
    if (now.length > 0 && !now.some((pid) => runningBefore.includes(pid))) {
      run('osascript', ['-e', 'tell application id "com.apple.ActivityMonitor" to quit']);
    }
  }
});

test('meter-ax\'s usage line names every command it has', () => {
  const source = require('node:fs').readFileSync(path.join(paths.root, 'Sources', 'meter-ax', 'main.swift'), 'utf8');
  const commands = [...source.matchAll(/^case "([\w-]+)":/gm)].map((m) => m[1]);
  assert.ok(commands.includes('cell'), 'the source has the cell command');
  const { spawnSync } = require('node:child_process');
  const r = spawnSync(paths.meterAx, [], { encoding: 'utf8' });
  const usage = `${r.stdout}${r.stderr}`;
  for (const command of commands) assert.ok(usage.includes(command), `usage names "${command}": ${usage.trim()}`);
});
