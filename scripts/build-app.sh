#!/bin/sh
# Builds the meter with Swift Package Manager (Command Line Tools, no Xcode), bundles it as an
# agent app and signs it ad hoc.
#   build/Meter.app        the release app: no test reading source compiled in
#   build/test/Meter.app   the test app: the test reading source compiled in (-DMETER_TEST_SOURCE)
#   build/test/standins/Xcode.app   the harness's stand-in app (never the real Xcode): an app that
#                          records the quit request it receives
# and builds the harness helpers (meter-ax, meter-neighbor, meter-gpu-load, meter-standin) into
# .build/release.
set -eu
cd "$(dirname "$0")/.."

bundle() { # <binary> <bundle path> [identifier] [version]
  id=${3:-local.menubar-meter.Meter}
  rm -rf "$2"
  mkdir -p "$2/Contents/MacOS" "$2/Contents/Library/LaunchAgents"
  cp app/Info.plist "$2/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "$id" "$2/Contents/Info.plist"
  if [ -n "${4:-}" ]; then plutil -replace CFBundleShortVersionString -string "$4" "$2/Contents/Info.plist"; fi
  cp "$1" "$2/Contents/MacOS/Meter"
  # The login job macOS starts at every login and keeps alive after a crash, labelled by the
  # bundle's identifier, written from the meter's own rules (KeepAlive in MeterCore).
  "$1" --launch-agent-plist "$id" >"$2/Contents/Library/LaunchAgents/$id.plist"
  plutil -lint -s "$2/Contents/Library/LaunchAgents/$id.plist"
  codesign --force --sign - "$2" >/dev/null 2>&1
}

swift build -c release --product Meter
swift build -c release --product meter-ax
swift build -c release --product meter-neighbor
swift build -c release --product meter-gpu-load
swift build -c release --product meter-standin
bundle .build/release/Meter build/Meter.app

swift build -c release --product Meter --scratch-path .build/test -Xswiftc -DMETER_TEST_SOURCE
bundle .build/test/release/Meter build/test/Meter.app

# The installer: build/Meter.pkg installs the release app in /Applications, registers its login
# job and opens it (D83); the same package over an older copy replaces it (D84).
sh scripts/build-pkg.sh build/Meter.app build/Meter.pkg
# The harness's packages: the test app under its own identifier (never the installed meter's),
# an older and a newer version, installed only into scratch folders.
pkgtest=local.menubar-meter.Meter.pkgtest
mkdir -p build/test/pkg
for v in 0.0.1 0.0.2; do
  bundle .build/test/release/Meter "build/test/pkg/$v/Meter.app" "$pkgtest" "$v"
  sh scripts/build-pkg.sh "build/test/pkg/$v/Meter.app" "build/test/pkg/Meter-$v.pkg"
done

# The stand-in app: the stand-in program bundled as an app named Xcode, with its own identifier.
standin=build/test/standins/Xcode.app
rm -rf "$standin"
mkdir -p "$standin/Contents/MacOS"
cp .build/release/meter-standin "$standin/Contents/MacOS/Xcode"
cat >"$standin/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Xcode</string>
  <key>CFBundleIdentifier</key><string>local.menubar-meter.standin.xcode</string>
  <key>CFBundleName</key><string>Xcode</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$standin" >/dev/null 2>&1

echo "built build/Meter.app, build/Meter.pkg and build/test/Meter.app"
