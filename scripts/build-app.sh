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
  mkdir -p "$2/Contents/MacOS"
  cp app/Info.plist "$2/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "$id" "$2/Contents/Info.plist"
  if [ -n "${4:-}" ]; then plutil -replace CFBundleShortVersionString -string "$4" "$2/Contents/Info.plist"; fi
  cp "$1" "$2/Contents/MacOS/Meter"
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
# The harness's packages: the release program under its own identifier (never the installed
# meter's), an older and a newer version, installed only into the user's home folder. Their
# bundles are made in a temporary folder and removed, so no second copy is left about.
pkgtest=local.menubar-meter.Meter.pkgtest
rm -rf build/test/pkg
mkdir -p build/test/pkg
staging=$(mktemp -d)
for v in 0.0.1 0.0.2; do
  bundle .build/release/Meter "$staging/$v/Meter.app" "$pkgtest" "$v"
  sh scripts/build-pkg.sh "$staging/$v/Meter.app" "build/test/pkg/Meter-$v.pkg" home
done
rm -rf "$staging"

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
