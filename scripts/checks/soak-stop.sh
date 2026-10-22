#!/bin/sh
# Stops the soak and removes its LaunchAgent; the samples and the report are kept.
set -u
launchctl bootout "gui/$(id -u)/local.menubar-meter.soak" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/local.menubar-meter.soak.plist"
echo "soak stopped; kept $HOME/Library/Logs/menubar-meter-checks"
