'use strict';
// The helpers the real-system check reads the panel's byte rates with.
const test = require('node:test');
const assert = require('node:assert/strict');
const rates = require('./support/rates');

test('the reference formatter is decimal and steps at a thousand', () => {
  const cases = [[0, '0.0 KB/s'], [300000, '300.0 KB/s'], [999949, '999.9 KB/s'], [999950, '1.0 MB/s'],
    [1005000, '1.0 MB/s'], [999949999, '999.9 MB/s'], [999950000, '1.0 GB/s'], [20e6, '20.0 MB/s']];
  for (const [bytes, text] of cases) assert.equal(rates.format(bytes), text);
});

test('a reading is canonical when the reference formatter writes the same text for its value', () => {
  for (const ok of ['0.0 KB/s', '999.9 KB/s', '1.0 MB/s', '20.0 MB/s', '1.2 GB/s']) {
    assert.equal(rates.canonical(ok), true, ok);
  }
  // A step at 1024 or at 300 leaves these behind.
  for (const bad of ['1005.0 KB/s', '1000.0 KB/s', '0.3 MB/s', '1024.0 MB/s']) {
    assert.equal(rates.canonical(bad), false, bad);
  }
});

test('readings are weighted by how long each was shown, a dash counting for nothing', () => {
  const seen = [{ at: 0, value: 10 }, { at: 100, value: 20 }, { at: 400, value: null }, { at: 500, value: 40 }];
  // 10 for 100 ms, 20 for 300 ms, a dash for 100 ms, 40 for 500 ms (the window ends at 1000).
  assert.equal(rates.weightedMean(seen, 1000), (10 * 100 + 20 * 300 + 40 * 500) / 900);
});

test('parsing a reading gives bytes a second, decimal', () => {
  assert.equal(rates.parse('112.4 MB/s'), 112.4e6);
  assert.equal(rates.parse('300.0 KB/s'), 300000);
});
