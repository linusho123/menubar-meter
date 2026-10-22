#!/bin/sh
# Starts the seven-day memory soak (docs/P7-SOAK-AND-ENERGY.md): copies soak.sh to
# ~/Library/Logs/menubar-meter-checks and loads the user LaunchAgent local.menubar-meter.soak,
# which runs it now and every ten minutes. It touches nothing of the meter itself.
set -eu
dir="$HOME/Library/Logs/menubar-meter-checks"
agent="$HOME/Library/LaunchAgents/local.menubar-meter.soak.plist"
mkdir -p "$dir"
cp "$(dirname "$0")/soak.sh" "$dir/soak.sh"
chmod 755 "$dir/soak.sh"
cat >"$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.menubar-meter.soak</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$dir/soak.sh</string></array>
  <key>StartInterval</key><integer>600</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardErrorPath</key><string>$dir/soak.err</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$agent"
echo "soak started: samples in $dir/soak.ndjson, the report in $dir/soak-report.ndjson after 7 days"
