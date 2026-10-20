'use strict';
// A load generator: ONE task that keeps `threads` cores fully busy, and holds `mib` MiB of
// memory it has written to, until it is ended.
const { Worker, isMainThread } = require('node:worker_threads');

if (isMainThread && require.main === module) {
  const threads = Number(process.argv[2]);
  const mib = Number(process.argv[3] || 0);
  const held = [];
  for (let i = 0; i < mib; i++) held.push(Buffer.alloc(2 ** 20, 1));
  for (let i = 0; i < threads; i++) {
    new Worker('for (;;) {}', { eval: true });
  }
  if (threads === 0) setInterval(() => held.length, 60000);
}
