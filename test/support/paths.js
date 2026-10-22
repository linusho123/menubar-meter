'use strict';
const path = require('node:path');

const root = path.join(__dirname, '..', '..');

module.exports = {
  root,
  features: path.join(root, 'features'),
  // The installed-style app: no test reading source compiled in.
  releaseApp: path.join(root, 'build', 'Meter.app', 'Contents', 'MacOS', 'Meter'),
  // The test app: the test reading source compiled in, used only when given a feed.
  testApp: path.join(root, 'build', 'test', 'Meter.app', 'Contents', 'MacOS', 'Meter'),
  meterAx: path.join(root, '.build', 'release', 'meter-ax'),
  neighbor: path.join(root, '.build', 'release', 'meter-neighbor'),
  gpuLoad: path.join(root, '.build', 'release', 'meter-gpu-load'),
  meterCost: path.join(root, '.build', 'release', 'meter-cost'),
};
