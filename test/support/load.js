'use strict';
// A load generator: ONE task that keeps `threads` cores fully busy until it is ended.
const { Worker, isMainThread } = require('node:worker_threads');

if (isMainThread && require.main === module) {
  const threads = Number(process.argv[2]);
  for (let i = 0; i < threads; i++) {
    new Worker('for (;;) {}', { eval: true });
  }
}
