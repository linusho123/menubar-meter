#!/bin/sh
# Builds the meter with Swift Package Manager (Command Line Tools, no Xcode),
# bundles it as an agent app (no Dock icon) and signs it ad hoc.
#
#   build/release/Meter.app   the app as installed: no test reading source
#   build/test/Meter.app      the same app with the test-only reading source
#                             compiled in (-DMETER_TEST_SOURCE), for Givens
#   build/meter-harness       the test harness helper (never bundled)
set -eu
cd "$(dirname "$0")/.."
VERSION=$(node -p "require('./package.json').version")

bundle() { # <swift build path> <bundle dir> <bundle id>
  bin="$1/release/Meter"
  app="$2/Meter.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp "$bin" "$app/Contents/MacOS/Meter"
  sed -e "s/__BUNDLE_ID__/$3/" -e "s/__VERSION__/$VERSION/" app/Info.plist > "$app/Contents/Info.plist"
  codesign --force --sign - "$app" >/dev/null
  echo "built $app"
}

swift build -c release --product Meter --build-path .build/release-app
bundle .build/release-app build/release local.menubar-meter

swift build -c release --product Meter --build-path .build/test-app -Xswiftc -DMETER_TEST_SOURCE
bundle .build/test-app build/test local.menubar-meter.test-source

swift build -c release --product meter-harness --build-path .build/harness
mkdir -p build
cp .build/harness/release/meter-harness build/meter-harness
codesign --force --sign - build/meter-harness >/dev/null
echo "built build/meter-harness"
