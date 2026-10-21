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
}, {
  wip: [
    'network-and-disk',
    'presence',
    'own-cost',
    // The network and disk rows need the panel's network and disk lines (P5).
    {
      feature: 'menu-bar-readout',
      scenarios: ['A value with no fresh reading turns into a dash'],
    },
  ],
  manifest: path.join(paths.root, 'run-manifest.ndjson'),
});
