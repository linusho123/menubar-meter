'use strict';
// The acceptance criteria: every feature file, under the wip ratchet. wip only shrinks.
const path = require('node:path');
const { runFeatures } = require('gherkin-node-test');
const paths = require('./support/paths');

runFeatures(paths.features, {
  'menu-bar-readout': require('./steps/menu-bar-readout.steps'),
  'recent-history': require('./steps/recent-history.steps'),
  'heavy-tasks': require('./steps/heavy-tasks.steps'),
  'ending-tasks': require('./steps/ending-tasks.steps'),
  'network-and-disk': require('./steps/network-and-disk.steps'),
  presence: require('./steps/presence.steps'),
}, {
  wip: [
    'own-cost',
  ],
  manifest: path.join(paths.root, 'run-manifest.ndjson'),
});
