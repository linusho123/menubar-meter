'use strict';
// The heavy-tasks list against the real Mac: real tasks the harness runs, their values checked by
// macOS's own tools (ps, top) and by Activity Monitor's own % GPU column, read through
// Accessibility. These back the scenarios that describe their tasks to the test reading source;
// they never stand in for a scenario.
const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
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
    });
  } finally {
    await procs.end(load);
  }
});

const jsc = '/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc';

test('a real task whose program lives in /System is system, with no End (D99)', async () => {
  // A program macOS ships, run by the user for one busy core: it ranks in the top five.
  const busy = procs.start(jsc, ['-e', 'for(;;){}']);
  try {
    await procs.sleep(2000);
    const [owner, program] = run('ps', ['-o', 'user=,comm=', '-p', String(busy.pid)]).split(/\s+/, 2);
    assert.strictEqual(owner, os.userInfo().username, 'ps: the task runs as the user');
    assert.ok(program.startsWith('/System/'), `ps: its program is ${program}`);
    await withRealMeter(async (meter) => {
      await tasks.openAndRead(meter.pid, 5);
      let row;
      for (let i = 0; i < 10 && !row; i++) {
        await procs.sleep(600);
        row = tasks.rowsNamed(tasks.listNow(meter.pid), 'jsc')[0];
      }
      assert.ok(row, 'the busy /System task is listed');
      assert.ok(row.tags.includes('system'), `its tags: ${row.tags}`);
      assert.deepStrictEqual(row.buttons.map((b) => b.text), [], 'it has no End');
      // The meter and macOS's own tasks, wherever they are listed, are system too.
      for (const other of tasks.listNow(meter.pid).rows) {
        if (['Meter', 'WindowServer', 'loginwindow', 'Dock', 'kernel_task'].includes(other.name)) {
          assert.ok(other.tags.includes('system') && other.buttons.length === 0, `${other.name} is system`);
        }
      }
    });
  } finally {
    await procs.end(busy);
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
  // Five tasks each keeping a core busy fill the five CPU rows, so the GPU stand-in can be listed
  // only as the extra GPU row (D109).
  const cpuHogs = [1, 2, 3, 4, 5].map(() => procs.start(process.execPath, [path.join(__dirname, 'support', 'load.js'), '1']));
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
      const amNow = () => {
        for (let attempt = 1; ; attempt++) {
          try {
            return value(run(paths.meterAx, ['cell', String(am.pid), 'PID', String(gpu.pid), '% GPU']));
          } catch (error) {
            if (attempt === 5) throw error;
          }
        }
      };
      // Activity Monitor's figure moves when it refreshes (about every 5 s), and it reads higher
      // once the panel has been open a few seconds. Its readings count only after its first
      // refresh with the panel open: wait for the figure to change from what it read at opening.
      const atOpening = amNow();
      const refreshBy = Date.now() + 10000;
      while (Date.now() < refreshBy && amNow() === atOpening) await procs.sleep(500);
      // Then 16 readings of each side over about 15 s, their medians compared.
      const ours = [];
      const theirs = [];
      for (let i = 0; i < 16; i++) {
        await procs.sleep(900);
        const row = tasks.rowsNamed(tasks.listNow(meter.pid), 'meter-gpu-load')[0];
        assert.ok(row, 'the GPU stand-in is listed');
        ours.push(value(row.values.GPU));
        theirs.push(amNow());
      }
      const meterGpu = median(ours);
      const amGpu = median(theirs);
      assert.ok(Math.abs(meterGpu - amGpu) <= 20,
        `the list reads ${ours.join(', ')}% GPU; Activity Monitor ${theirs.join(', ')}`);
      // Over a tenth of the GPU and outside the five CPU rows, the task has the sixth row, tagged
      // GPU and nothing else (D109).
      const shown = tasks.listNow(meter.pid);
      const index = shown.rows.findIndex((r) => r.name === 'meter-gpu-load');
      assert.ok(index >= 0, 'the GPU stand-in is still listed');
      assert.ok(value(shown.rows[index].values.GPU) > 10, 'the stand-in is over a tenth of the GPU');
      assert.strictEqual(index, 5, `the GPU row is the sixth: row ${index + 1}`);
      assert.deepStrictEqual(shown.rows[index].tags, ['GPU'], 'the extra row says GPU, and only GPU');
    });
  } finally {
    await procs.end(gpu);
    for (const hog of cpuHogs) await procs.end(hog);
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
