'use strict';
// The acceptance suite: every feature file under features/, bound to its
// steps. The wip register below is the debt: it only ever shrinks.
const path = require('node:path');
const { runFeatures } = require('gherkin-node-test');

runFeatures(path.join(__dirname, '..', 'features'), {
  'menu-bar-readout': require('./steps/menu-bar-readout.steps'),
}, {
  wip: [
    'menu-bar-readout',
    'recent-history',
    'heavy-tasks',
    'ending-tasks',
    'network-and-disk',
    'presence',
    'own-cost',
  ],
  manifest: path.join(__dirname, '..', 'run-manifest.ndjson'),
});
