#!/bin/sh
# Builds the meter with Swift Package Manager (Command Line Tools, no Xcode), bundles it as an
# agent app and signs it ad hoc.
#   build/Meter.app        the release app: no test reading source compiled in
#   build/test/Meter.app   the test app: the test reading source compiled in (-DMETER_TEST_SOURCE)
# and builds the harness helpers (meter-ax, meter-neighbor, meter-gpu-load) into .build/release.
set -eu
cd "$(dirname "$0")/.."

bundle() { # <binary> <bundle path>
  rm -rf "$2"
  mkdir -p "$2/Contents/MacOS"
  cp app/Info.plist "$2/Contents/Info.plist"
  cp "$1" "$2/Contents/MacOS/Meter"
  codesign --force --sign - "$2" >/dev/null 2>&1
}

swift build -c release --product Meter
swift build -c release --product meter-ax
swift build -c release --product meter-neighbor
swift build -c release --product meter-gpu-load
bundle .build/release/Meter build/Meter.app

swift build -c release --product Meter --scratch-path .build/test -Xswiftc -DMETER_TEST_SOURCE
bundle .build/test/release/Meter build/test/Meter.app

echo "built build/Meter.app and build/test/Meter.app"
