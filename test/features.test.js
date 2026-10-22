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
  'own-cost': require('./steps/own-cost.steps'),
}, {
  wip: [
    // Checked on the user's own installed meter in normal use (docs/P7-SOAK-AND-ENERGY.md): the
    // seven-day memory row binds once the soak has reported (Q2), and the energy scenario once the
    // battery menu has been read after a day on battery (Q3). The one-hour row runs now.
    {
      feature: 'own-cost',
      scenarios: [
        "The meter's memory stays under its line",
        'The meter is never flagged as an energy hog',
      ],
    },
  ],
  manifest: path.join(paths.root, 'run-manifest.ndjson'),
});
