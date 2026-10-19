'use strict';
// Starts the built meter, with or without the test reading source, and
// quits it after each scenario. Only processes started here are ever ended.
const fs = require('node:fs');
const procs = require('./procs');
const menubar = require('./menubar');
const { releaseApp, testApp, binaryOf, harness } = require('./paths');

const LIVE = /^CPU [ \d]{3}%  GPU [ \d]{3}%  RAM [ \d]{3}%  [ \d]{3}°C$/u;

function requireBuilt(app) {
  if (!fs.existsSync(binaryOf(app))) throw new Error(`${app} is not built: run npm run build:app`);
  if (!fs.existsSync(harness)) throw new Error(`${harness} is not built: run npm run build:app`);
}

/**
 * Launch the meter. `source` is a TestSource for the test build; without one
 * the installed (release) build runs against the real Mac.
 * Resolves once its item is in the menu bar showing every value.
 */
async function launch(world, { source } = {}) {
  const app = source ? testApp : releaseApp;
  requireBuilt(app);
  const env = { ...process.env };
  delete env.METER_TEST_SOURCE;
  if (source) { source.write(); env.METER_TEST_SOURCE = source.file; }
  const handle = procs.start('meter', binaryOf(app), [], { env });
  world.defer(() => procs.stop(handle));
  const r = await menubar.watch(handle.pid, LIVE, Date.now() + 10000);
  if (!r.matched) throw new Error(`the meter did not show its readings within 10 s (item: ${JSON.stringify(r.title)})`);
  return handle;
}

/** Show a stand-in status item; started after the meter, macOS puts it to the meter's left. */
async function launchMarker(world) {
  requireBuilt(testApp);
  const handle = procs.start('marker', harness, ['marker']);
  world.defer(() => procs.stop(handle));
  for (let i = 0; i < 100; i++) {
    const it = await menubar.item(handle.pid);
    if (it && it.w > 0) return handle;
    await procs.sleep(50);
  }
  throw new Error('the stand-in status item did not appear');
}

module.exports = { launch, launchMarker, LIVE };
