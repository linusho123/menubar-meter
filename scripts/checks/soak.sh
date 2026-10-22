#!/bin/sh
# The seven-day memory soak (D76, Q2): run every ten minutes by the user's LaunchAgent
# local.menubar-meter.soak (soak-start.sh). Each run reads the installed meter with macOS's own
# tools and appends one line to soak.ndjson:
#   {"at": <epoch s>, "program": <path>, "pid": <pid>, "started": <ps lstart>, "stat": <ps state>,
#    "cpu": <ps time>, "footprint": <phys_footprint bytes, which Activity Monitor's Memory column
#    shows>, "version": <the installed app's version>, "sha": <sha256 of the executable>,
#    "sleeptime": <kern.sleeptime sec, the last sleep>, "waketime": <kern.waketime sec, the last wake>}
# or {"at": <epoch s>, "program": null} when no installed meter runs, or {"at": <epoch s>,
# "error": <why>} when the run could not take a reading: no exit is silent. Once one meter process
# has run seven days (by its own start time, a restart resets the count), every line from that
# process's first reading to this one is copied to soak-report.ndjson, null and error lines
# included so a restart or a hole stays visible, and the soak stops reading. It only reads: it
# never signals the meter. The harness's own check of this script (test/checks.test.js) points it
# elsewhere with METER_CHECKS_DIR, METER_SOAK_PROGRAM and METER_SOAK_SECONDS; the LaunchAgent sets
# none of them, and a report about any program but the installed meter binds nothing.
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
fail() {
  printf '{"at":%s,"error":"%s"}\n' "$now" "$1" >>"$log"
  exit 0
}
pid=$(ps -axo pid=,comm= | awk -v p="$program" '$2 == p { print $1; exit }')
if [ -z "$pid" ]; then
  printf '{"at":%s,"program":null}\n' "$now" >>"$log"
  exit 0
fi
squeeze() { sed 's/  */ /g; s/^ //; s/ $//'; }
started=$(ps -o lstart= -p "$pid" | squeeze)
row=$(ps -o stat=,time= -p "$pid" | squeeze)
stat=${row%% *}
cpu=${row#* }
footprint=$(footprint -f bytes --noCategories -p "$pid" 2>/dev/null | sed -n 's/.*phys_footprint: \([0-9][0-9]*\) B.*/\1/p' | head -1)
version=$(plutil -extract CFBundleShortVersionString raw "${program%/MacOS/*}/Info.plist" 2>/dev/null)
sha=$(shasum -a 256 "$program" 2>/dev/null | cut -d' ' -f1)
sleeptime=$(sysctl -n kern.sleeptime 2>/dev/null | sed -n 's/.*sec = \([0-9][0-9]*\).*/\1/p')
waketime=$(sysctl -n kern.waketime 2>/dev/null | sed -n 's/.*sec = \([0-9][0-9]*\).*/\1/p')
# The process must still be the one whose start time was read.
[ "$(ps -o lstart= -p "$pid" | squeeze)" = "$started" ] || fail "the process at pid $pid changed while it was read"
[ -n "$started" ] && [ -n "$row" ] || fail "ps read no start time or state for pid $pid"
[ -n "$footprint" ] || fail "footprint read no phys_footprint for pid $pid"
[ -n "$sleeptime" ] && [ -n "$waketime" ] || fail "sysctl read no kern.sleeptime or kern.waketime"
key=$(printf '"program":"%s","pid":%s,"started":"%s"' "$program" "$pid" "$started")
printf '{"at":%s,%s,"stat":"%s","cpu":"%s","footprint":%s,"version":"%s","sha":"%s","sleeptime":%s,"waketime":%s}\n' \
  "$now" "$key" "$stat" "$cpu" "$footprint" "$version" "$sha" "$sleeptime" "$waketime" >>"$log"
since=$(date -j -f '%a %b %d %T %Y' "$started" +%s 2>/dev/null) || fail "date could not read the start time $started"
if [ $((now - since)) -ge "$needed" ]; then
  # From this process's first reading to now, every line (null and error lines too).
  first=$(grep -nF "$key" "$log" | head -1 | cut -d: -f1)
  tail -n "+$first" "$log" >"$report.tmp" && mv "$report.tmp" "$report"
fi
