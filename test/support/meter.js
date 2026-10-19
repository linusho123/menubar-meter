'use strict';
// Starts the built meter (with or without the test reading source) and ends it afterwards.
const paths = require('./paths');
const procs = require('./procs');
const menubar = require('./menubar');
const { Feed } = require('./feed');

/** Starts the test app fed by a new feed holding `values`; ends both after the scenario. */
async function launchWithFeed(world, values) {
  const feed = new Feed();
  feed.set(values);
  world.defer(() => feed.remove());
  const meter = procs.start(paths.testApp, [], {
    env: { ...process.env, METER_TEST_FEED: feed.file },
  });
  world.defer(() => procs.end(meter));
  await menubar.waitForItem(meter.pid, () => true, 10000, 'the meter in the menu bar');
  world.feed = feed;
  world.meter = meter;
  return meter;
}

/** Starts the release app, reading the real system. */
async function launchReal(world) {
  const meter = procs.start(paths.releaseApp);
  world.defer(() => procs.end(meter));
  await menubar.waitForItem(meter.pid, () => true, 10000, 'the meter in the menu bar');
  world.meter = meter;
  return meter;
}

/** Starts a stand-in status item titled `title`, a menu bar icon the harness owns. */
async function launchNeighbor(world, title) {
  const neighbor = procs.start(paths.neighbor, [title]);
  world.defer(() => procs.end(neighbor));
  await menubar.waitForItem(neighbor.pid, () => true, 10000, 'the stand-in status item');
  return neighbor;
}

module.exports = { launchWithFeed, launchReal, launchNeighbor };
