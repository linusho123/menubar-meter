'use strict';
const path = require('node:path');
const procs = require('./procs');

/** Start one task keeping `threads` cores busy; it ends with the scenario. */
function busyTask(world, threads) {
  const handle = procs.start('load', process.execPath, [path.join(__dirname, 'load-task.js'), String(threads)]);
  world.defer(() => procs.stop(handle));
  return handle;
}

module.exports = { busyTask };
