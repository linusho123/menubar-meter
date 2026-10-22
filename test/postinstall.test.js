'use strict';
// The package's postinstall, run with shims for the commands it calls: it opens the new copy as
// the user at the screen, and never as root (no console user, root, or the login window).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const paths = require('./support/paths');

const SCRIPT = path.join(paths.root, 'app', 'pkg-scripts', 'postinstall');

/** Runs the postinstall as `uid` with `consoleUser` owning /dev/console; returns what it called. */
function run({ uid, consoleUser }) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'meter-postinstall-'));
  try {
    const log = path.join(dir, 'log');
    fs.writeFileSync(log, '');
    const shim = (name, body) => {
      fs.writeFileSync(path.join(dir, name), `#!/bin/sh\n${body}\n`, { mode: 0o755 });
    };
    shim('id', `if [ "$1" = "-u" ] && [ -z "$2" ]; then echo ${uid}; elif [ "$1" = "-u" ] && [ -n "$2" ]; then echo 501; else exit 1; fi`);
    shim('stat', `echo "${consoleUser}"`);
    for (const name of ['launchctl', 'sudo', 'open']) shim(name, `echo "${name} $*" >> "${log}"`);
    const r = spawnSync('/bin/sh', [SCRIPT, 'pkg', dir], {
      encoding: 'utf8', env: { PATH: dir }, timeout: 20000,
    });
    return { status: r.status, calls: fs.readFileSync(log, 'utf8').split('\n').filter(Boolean), dir, stderr: r.stderr };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('as root, with nobody at the screen, the postinstall opens nothing', () => {
  for (const consoleUser of ['root', 'loginwindow', '']) {
    const r = run({ uid: 0, consoleUser });
    assert.strictEqual(r.status, 0, `exits 0 for console user "${consoleUser}"`);
    assert.deepStrictEqual(r.calls, [], `no launchctl, sudo or open for console user "${consoleUser}"`);
  }
});

test('as root, with a user at the screen, it opens the new copy as that user', () => {
  const r = run({ uid: 0, consoleUser: 'linus' });
  assert.strictEqual(r.status, 0);
  assert.strictEqual(r.calls.length, 1);
  assert.match(r.calls[0], /^launchctl asuser 501 sudo -u linus open -n .*\/Meter\.app$/);
});

test('not as root, it opens the new copy itself', () => {
  const r = run({ uid: 501, consoleUser: 'linus' });
  assert.strictEqual(r.status, 0);
  assert.strictEqual(r.calls.length, 1);
  assert.match(r.calls[0], /^open -n .*\/Meter\.app$/);
});
