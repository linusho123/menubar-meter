'use strict';
/**
 * Byte rates as the panel writes them, read back by the real-system check: an independent,
 * decimal reference (D95, D117: a KB is 1000 bytes, a value moves up a unit at 1000), so a
 * panel using 1024 prefixes or another step reads differently from it.
 */
const SCALE = { KB: 1e3, MB: 1e6, GB: 1e9 };
const UNITS = ['KB', 'MB', 'GB'];

/** A rate in bytes a second, one decimal, in the unit its number grows into. */
function format(bytesPerSecond) {
  let divisor = 100;
  for (let i = 0; i < UNITS.length; i++) {
    const tenths = Math.round(bytesPerSecond / divisor);
    if (tenths < 10000 || i === UNITS.length - 1) {
      return `${Math.floor(tenths / 10)}.${tenths % 10} ${UNITS[i]}/s`;
    }
    divisor *= 1000;
  }
  return '';
}

/** "112.4 MB/s" in bytes a second, decimal; null when it is not a rate. */
function parse(text) {
  const m = /^(\d+)\.(\d) (KB|MB|GB)\/s$/u.exec(text || '');
  return m ? Number(`${m[1]}.${m[2]}`) * SCALE[m[3]] : null;
}

/** True when the reference formatter writes this very text for the value it reads. */
function canonical(text) {
  const bytes = parse(text);
  return bytes !== null && format(bytes) === text;
}

/**
 * The mean of what a watcher saw, each value weighted by how long it stayed on screen: `seen` is
 * [{at (ms), value (a number, or null when there was nothing to read)}], and the last value stays
 * until `endAt`. A null counts for nothing, time included.
 */
function weightedMean(seen, endAt) {
  let total = 0;
  let time = 0;
  seen.forEach((s, i) => {
    const until = i + 1 < seen.length ? seen[i + 1].at : endAt;
    const span = Math.max(0, until - s.at);
    if (s.value === null || s.value === undefined) return;
    total += s.value * span;
    time += span;
  });
  return time === 0 ? NaN : total / time;
}

module.exports = { format, parse, canonical, weightedMean };
