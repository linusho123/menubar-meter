'use strict';
const path = require('node:path');

const root = path.join(__dirname, '..', '..');
module.exports = {
  root,
  releaseApp: path.join(root, 'build', 'release', 'Meter.app'),
  testApp: path.join(root, 'build', 'test', 'Meter.app'),
  harness: path.join(root, 'build', 'meter-harness'),
  binaryOf: (app) => path.join(app, 'Contents', 'MacOS', 'Meter'),
};
