#!/bin/sh
# Packages an app bundle as the one install step (D83): an installer package that puts it in
# /Applications, then opens it as the user at the screen, which registers its login job with
# macOS and starts it. Usage: build-pkg.sh <Meter.app> <out.pkg> [home]
# With `home` (the harness's packages only) the package may also install into the user's own
# home folder, so a test runs the real installer without an administrator password; the
# release package installs only for the whole Mac, in /Applications.
set -eu
# No AppleDouble (._*) files in the package from extended attributes.
export COPYFILE_DISABLE=1
cd "$(dirname "$0")/.."
app=$1
out=$2
id=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root"
ditto --noextattr --noqtn "$app" "$work/root/Meter.app"
xattr -cr "$work/root/Meter.app"
pkgbuild --analyze --root "$work/root" "$work/components.plist" >/dev/null
# Never relocatable: the installer must not look for another copy with the same identifier (a
# build folder, a copy in Downloads) and update that one instead, leaving two copies.
plutil -replace 0.BundleIsRelocatable -bool NO "$work/components.plist"
plutil -replace 0.BundleOverwriteAction -string upgrade "$work/components.plist"
pkgbuild --quiet --root "$work/root" --component-plist "$work/components.plist" \
  --install-location /Applications --scripts app/pkg-scripts \
  --identifier "$id.pkg" --version "$version" "$work/Meter-component.pkg"
# pkgbuild stores a file's extended attributes (macOS puts com.apple.provenance on what a
# tracked process builds) as AppleDouble files; the scripts folder must hold only the script.
pkgutil --expand "$work/Meter-component.pkg" "$work/expanded"
rm -f "$work/expanded/Scripts/._"*
rm -f "$work/Meter-component.pkg"
pkgutil --flatten "$work/expanded" "$work/Meter-component.pkg"
productbuild --quiet --synthesize --package "$work/Meter-component.pkg" "$work/dist.xml"
home=false
if [ "${3:-}" = home ]; then home=true; fi
# One step: no choices to make, the title the installer shows.
sed -i '' "s|<options |<title>Meter</title><domains enable_localSystem=\"true\" enable_currentUserHome=\"$home\" enable_anywhere=\"false\"/><options |" "$work/dist.xml"
productbuild --quiet --distribution "$work/dist.xml" --package-path "$work" "$out"
