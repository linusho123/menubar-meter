'use strict';
// npm run scope: the strict feature lints over every feature file, then the strict docket lint.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { lintFeature } = require('gherkin-node-test');

const dir = path.join(__dirname, '..', 'features');
let findings = 0;
for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.feature')).sort()) {
  for (const f of lintFeature(fs.readFileSync(path.join(dir, file), 'utf8'), file, { strict: true })) {
    console.log(`features/${file}:${f.line}: [${f.rule}] ${f.message}`);
    findings++;
  }
}
console.log(`feature lint (strict): ${findings} findings`);
try {
  execFileSync('npx', ['docketry', 'lint', 'features/DOCKET.md', '--corpus', 'features', '--strict'], {
    cwd: path.join(__dirname, '..'), stdio: 'inherit',
  });
} catch {
  process.exit(1);
}
process.exit(findings === 0 ? 0 : 1);
