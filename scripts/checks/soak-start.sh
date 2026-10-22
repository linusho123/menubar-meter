#!/bin/sh
# Starts the seven-day memory soak (docs/P7-SOAK-AND-ENERGY.md): copies soak.sh to
# ~/Library/Logs/menubar-meter-checks and loads the user LaunchAgent local.menubar-meter.soak,
# which runs it now and every ten minutes. It touches nothing of the meter itself. It refuses unless
# /Applications/Meter.app is installed and is this checkout's version (the P7 build, app/Info.plist),
# and starting again replaces the loaded job, so it can be run twice. The harness's check of this
# script points it elsewhere with METER_SOAK_APP and METER_SOAK_LABEL; the user sets neither.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
app="${METER_SOAK_APP:-/Applications/Meter.app}"
label="${METER_SOAK_LABEL:-local.menubar-meter.soak}"
here="$(cd "$(dirname "$0")" && pwd)"
[ -f "$app/Contents/Info.plist" ] || { echo "soak-start: Meter is not installed at $app; install build/Meter.pkg first (docs/P7-SOAK-AND-ENERGY.md, step 0)" >&2; exit 1; }
want=$(plutil -extract CFBundleShortVersionString raw "$here/../../app/Info.plist")
have=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
[ "$have" = "$want" ] || { echo "soak-start: the installed Meter is version $have, not the P7 build $want; install build/Meter.pkg first (docs/P7-SOAK-AND-ENERGY.md, step 0)" >&2; exit 1; }
dir="$HOME/Library/Logs/menubar-meter-checks"
agent="$HOME/Library/LaunchAgents/$label.plist"
mkdir -p "$dir" "$HOME/Library/LaunchAgents"
cp "$here/soak.sh" "$dir/soak.sh"
chmod 755 "$dir/soak.sh"
cat >"$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$dir/soak.sh</string></array>
  <key>StartInterval</key><integer>600</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardErrorPath</key><string>$dir/soak.err</string>
</dict>
</plist>
PLIST
# A job already loaded is replaced, not an error.
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$agent"
echo "soak started: samples in $dir/soak.ndjson, the report in $dir/soak-report.ndjson after 7 days"
