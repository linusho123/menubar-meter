#!/bin/sh
# Stops the soak and removes its LaunchAgent; the samples and the report are kept.
set -u
label="${METER_SOAK_LABEL:-local.menubar-meter.soak}"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$label.plist"
echo "soak stopped; kept $HOME/Library/Logs/menubar-meter-checks"
