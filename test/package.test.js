'use strict';
// The release packages, expanded and read: build/Meter.pkg (the one install step, D83) and
// build/check/Meter-0.0.9.pkg (the same program under the release identifier at an older
// version, for the manual log-in check's install-over-older step, D84). They are never
// installed here; the real installer is run only with the harness's own packages.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const paths = require('./support/paths');

const RELEASE_ID = 'local.menubar-meter.Meter';

function expand(pkg) {
  assert.ok(fs.existsSync(pkg), `${pkg} exists (npm run build:app)`);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-pkg-'));
  const out = path.join(dir, 'x');
  execFileSync('pkgutil', ['--expand', pkg, out]);
  const files = (d) => fs.readdirSync(d, { withFileTypes: true })
    .flatMap((e) => (e.isDirectory() ? files(path.join(d, e.name)).map((f) => `${e.name}/${f}`) : [e.name]));
  const component = path.join(out, 'Meter-component.pkg');
  const payload = execFileSync('pkgutil', ['--payload-files', pkg], { encoding: 'utf8' })
    .split('\n').filter(Boolean);
  const read = (f) => fs.readFileSync(f, 'utf8');
  const result = {
    info: read(path.join(component, 'PackageInfo')),
    distribution: read(path.join(out, 'Distribution')),
    scripts: files(path.join(component, 'Scripts')),
    payload,
  };
  fs.rmSync(dir, { recursive: true, force: true });
  return result;
}

for (const [pkg, version] of [
  [path.join(paths.root, 'build', 'Meter.pkg'), '0.1.0'],
  [path.join(paths.root, 'build', 'check', 'Meter-0.0.9.pkg'), '0.0.9'],
]) {
  test(`${path.relative(paths.root, pkg)} is the one install step for the whole Mac, version ${version}`, () => {
    const p = expand(pkg);
    assert.match(p.info, /install-location="\/Applications"/);
    assert.match(p.info, /relocatable="false"/);
    assert.match(p.info, /<upgrade-bundle>\s*<bundle id="local\.menubar-meter\.Meter"\/>/);
    assert.match(p.info, new RegExp(`identifier="${RELEASE_ID}\\.pkg"`));
    assert.match(p.info, new RegExp(`version="${version.replace(/\./g, '\\.')}"`));
    assert.match(p.info, new RegExp(`id="${RELEASE_ID}" CFBundleShortVersionString="${version.replace(/\./g, '\\.')}"`));
    // Only Meter.app. (`./._Meter.app` is macOS's own com.apple.provenance mark on the bundle
    // folder, which it puts back on anything a tracked process builds and which cannot be
    // removed; the installer applies it to Meter.app as an attribute, it is not a file.)
    assert.deepStrictEqual(
      p.payload.filter((f) => f !== '.' && f !== './._Meter.app' && !/^\.\/Meter\.app(\/|$)/.test(f)), [],
      'the payload is only Meter.app');
    assert.ok(p.payload.includes('./Meter.app/Contents/MacOS/Meter'));
    assert.deepStrictEqual(p.scripts, ['postinstall'], 'the postinstall, and no AppleDouble leftovers');
    assert.match(p.distribution, /enable_currentUserHome="false"/);
    assert.match(p.distribution, /enable_localSystem="true"/);
  });
}
