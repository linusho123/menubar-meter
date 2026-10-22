#!/bin/sh
# The seven-day memory soak (D76, Q2): run every ten minutes by the user's LaunchAgent
# local.menubar-meter.soak (soak-start.sh). Each run reads the installed meter with macOS's own
# tools and appends one line to soak.ndjson:
#   {"at": <epoch s>, "program": <path>, "pid": <pid>, "started": <ps lstart>, "cpu": <ps time>,
#    "footprint": <phys_footprint bytes, which Activity Monitor's Memory column shows>,
#    "version": <the installed app's version>}
# or {"at": <epoch s>, "program": null} when no installed meter runs. Once one meter process has
# run seven days without a restart, every line about that process is copied to
# soak-report.ndjson, and the soak stops reading. It only reads: it never signals the meter.
# The harness's own check of this script (test/checks.test.js) points it elsewhere with
# METER_CHECKS_DIR, METER_SOAK_PROGRAM and METER_SOAK_SECONDS; the LaunchAgent sets none of them,
# and a report about any program but the installed meter binds nothing.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
dir="${METER_CHECKS_DIR:-$HOME/Library/Logs/menubar-meter-checks}"
mkdir -p "$dir"
log="$dir/soak.ndjson"
report="$dir/soak-report.ndjson"
program="${METER_SOAK_PROGRAM:-/Applications/Meter.app/Contents/MacOS/Meter}"
needed="${METER_SOAK_SECONDS:-604800}"
[ -f "$report" ] && exit 0
now=$(date +%s)
pid=$(ps -axo pid=,comm= | awk -v p="$program" '$2 == p { print $1; exit }')
if [ -z "$pid" ]; then
  printf '{"at":%s,"program":null}\n' "$now" >>"$log"
  exit 0
fi
started=$(ps -o lstart= -p "$pid" | sed 's/  */ /g; s/^ //; s/ $//')
cpu=$(ps -o time= -p "$pid" | tr -d ' ')
footprint=$(footprint -f bytes --noCategories -p "$pid" 2>/dev/null | sed -n 's/.*phys_footprint: \([0-9][0-9]*\) B.*/\1/p')
version=$(plutil -extract CFBundleShortVersionString raw "${program%/MacOS/*}/Info.plist" 2>/dev/null)
# The process must still be the one whose start time was read.
[ "$(ps -o lstart= -p "$pid" | sed 's/  */ /g; s/^ //; s/ $//')" = "$started" ] || exit 0
[ -n "$footprint" ] || exit 0
key=$(printf '"program":"%s","pid":%s,"started":"%s"' "$program" "$pid" "$started")
printf '{"at":%s,%s,"cpu":"%s","footprint":%s,"version":"%s"}\n' \
  "$now" "$key" "$cpu" "$footprint" "$version" >>"$log"
since=$(date -j -f '%a %b %d %T %Y' "$started" +%s 2>/dev/null) || exit 0
if [ $((now - since)) -ge "$needed" ]; then
  grep -F "$key" "$log" >"$report.tmp" && mv "$report.tmp" "$report"
fi
