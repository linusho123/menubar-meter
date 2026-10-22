#!/bin/sh
# Packages an app bundle as the one install step (D83): an installer package that puts it in
# /Applications, then opens it as the user at the screen, which registers its login job with
# macOS and starts it. Usage: build-pkg.sh <Meter.app> <out.pkg>
set -eu
cd "$(dirname "$0")/.."
app=$1
out=$2
id=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root"
ditto "$app" "$work/root/Meter.app"
pkgbuild --analyze --root "$work/root" "$work/components.plist" >/dev/null
# Never relocatable: the installer must not look for another copy with the same identifier (a
# build folder, a copy in Downloads) and update that one instead, leaving two copies.
plutil -replace 0.BundleIsRelocatable -bool NO "$work/components.plist"
plutil -replace 0.BundleOverwriteAction -string upgrade "$work/components.plist"
pkgbuild --quiet --root "$work/root" --component-plist "$work/components.plist" \
  --install-location /Applications --scripts app/pkg-scripts \
  --identifier "$id.pkg" --version "$version" "$work/Meter-component.pkg"
productbuild --quiet --package "$work/Meter-component.pkg" "$out"
