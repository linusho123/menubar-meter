'use strict';
// network-and-disk.feature. The Given sets the meter's raw network and disk counters through
// the test reading source, growing at the rates Activity Monitor would read; every Then reads
// only what macOS shows: the panel's text through Accessibility. The real-system check (a real
// transfer against netstat and ioreg) is in real-sources.test.js.
const assert = require('node:assert');
const feeds = require('../support/feed');
const meter = require('../support/meter');
const panel = require('../support/panel');
const procs = require('../support/procs');

const required = (value, what) => {
  if (value === undefined || value === null) throw new Error(`world.${what} read before any step set it`);
  return value;
};

/**
 * An amount as Activity Monitor writes it ("0 bytes", "112.4 MB", "1.2 GB") in bytes, with its
 * decimal prefixes: a KB is 1000 bytes (measured against Activity Monitor, DESIGN P5).
 */
function amBytes(text) {
  const m = /^([\d.,]+) (bytes|KB|MB|GB)$/.exec(text.trim());
  if (!m) throw new Error(`not an Activity Monitor amount: "${text}"`);
  const scale = { bytes: 1, KB: 1e3, MB: 1e6, GB: 1e9 }[m[2]];
  return Math.round(Number(m[1].replace(/,/g, '')) * scale);
}

module.exports = (reg) => {
  reg.define(
    /^Activity Monitor reads Data received\/sec (.+), Data sent\/sec (.+), Data read\/sec (.+) and Data written\/sec (.+)$/,
    async (w, received, sent, read, written) => {
      const values = feeds.readings({ cpu: 10, gpu: 5, ram: 40, temp: 45 });
      values.network = { received: amBytes(received), sent: amBytes(sent) };
      values.disk = { read: amBytes(read), written: amBytes(written) };
      await meter.launchWithFeed(w, values);
      // Two passes, so a rate has been measured from two reads of the counters.
      await procs.sleep(1200);
    });

  reg.define(/^the user opens the panel$/, async (w) => {
    const m = required(w.meter, 'meter');
    w.capture = await panel.clickAndCapture(m.pid);
  });

  reg.define(/^the user sees the line "(.+)"$/u, async (w, line) => {
    const m = required(w.meter, 'meter');
    required(w.capture, 'capture');
    // What the panel shows now, read again for a moment while the panel refreshes.
    const deadline = Date.now() + 2000;
    let texts = panel.textsNow(m.pid);
    while (!texts.includes(line) && Date.now() < deadline) {
      await procs.sleep(100);
      texts = panel.textsNow(m.pid);
    }
    assert.ok(texts.includes(line), `the panel shows "${line}"; it reads ${JSON.stringify(texts)}`);
    assert.strictEqual(texts.filter((t) => t === line).length, 1, `one line reads "${line}"`);
  });
};
