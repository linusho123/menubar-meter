'use strict';
// A stand-in busy task: one process keeping N threads spinning.
// Usage: node load-task.js <threads>
const { Worker, isMainThread } = require('node:worker_threads');

if (isMainThread) {
  const n = Number(process.argv[2]);
  if (!Number.isInteger(n) || n < 1) throw new Error('usage: load-task.js <threads>');
  for (let i = 0; i < n - 1; i++) new Worker(__filename);
  for (;;) { /* spin */ }
} else {
  for (;;) { /* spin */ }
}
