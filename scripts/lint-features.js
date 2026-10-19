'use strict';
// Strict feature lint: every .feature file under features/ is in-dialect and
// clean of every spec lint, warnings promoted to errors.
const fs = require('node:fs');
const path = require('node:path');
const { lintFeature } = require('gherkin-node-test');

const dir = path.join(__dirname, '..', 'features');
const files = fs.readdirSync(dir, { recursive: true, encoding: 'utf8' }).filter((f) => f.endsWith('.feature'));
let problems = 0;
for (const f of files) {
  for (const finding of lintFeature(fs.readFileSync(path.join(dir, f), 'utf8'), f, { strict: true })) {
    problems++;
    console.error(`features/${f}:${finding.line}: [${finding.rule}] ${finding.message}`);
  }
}
console.log(`feature lint (strict): ${files.length} files, ${problems} findings`);
process.exit(problems ? 1 : 0);
