#!/bin/sh
# Prints the state docs/P6-LOGIN-CHECK.md records at each step. Read-only: it changes nothing.
# Usage: sh scripts/login-check.sh "<tag>"
label=${METER_LABEL:-local.menubar-meter.Meter}
app=${METER_APP:-/Applications/Meter.app}
agent="$HOME/Library/LaunchAgents/$label.plist"
echo "== ${1:-check} ($(date '+%Y-%m-%d %H:%M:%S'))"

if [ -f "$app/Contents/Info.plist" ]; then
  echo "version: $(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
else
  echo "version: not installed"
fi

out=$(launchctl print "gui/$(id -u)/$label" 2>/dev/null) || out=""
if [ -z "$out" ]; then
  echo "job: not loaded"
else
  field() { printf '%s\n' "$out" | sed -n "s/^	$1 = //p" | head -1; }
  pid=$(field pid)
  echo "job: loaded"
  echo "  state = $(field state)"
  echo "  program = $(field program)"
  echo "  pid = ${pid:-none}"
  echo "  runs = $(field runs)"
  echo "  last exit code = $(field 'last exit code')"
  if [ -n "$pid" ]; then
    echo "  job's process: $(ps -o user= -o pid= -o ppid= -o lstart= -p "$pid" | sed 's/  */ /g') (user pid ppid started)"
  fi
fi

procs=$(ps -axo user=,pid=,ppid=,lstart=,comm= | grep -E '/Meter\.app/Contents/MacOS/Meter$' | sed 's/  */ /g')
if [ -z "$procs" ]; then
  echo "processes: none"
else
  echo "processes: $(printf '%s\n' "$procs" | wc -l | tr -d ' ') (user pid ppid started program)"
  printf '%s\n' "$procs" | sed 's/^/  /'
fi

copies=$(ls -d "$(dirname "$app")"/Meter*.app 2>/dev/null)
if [ -z "$copies" ]; then echo "copies: none"; else echo "copies: $copies" | tr '\n' ' '; echo; fi

echo "LaunchAgent file: $([ -f "$agent" ] && echo "$agent" || echo none)"
record=$( (sudo -n /usr/bin/sfltool dumpbtm 2>/dev/null || sudo /usr/bin/sfltool dumpbtm) |
  awk -v url="URL: file://$agent" '
    /^ *#[0-9]+:$/ { if (keep) printf "%s", rec; rec = ""; keep = 0; next }
    { rec = rec $0 "\n" }
    { line = $0; sub(/^ +/, "", line); if (line == url) keep = 1 }
    END { if (keep) printf "%s", rec }' |
  grep -E '^ *(Disposition|URL|Executable Path):')
if [ -z "$record" ]; then echo "registry: no record"; else echo "registry:"; printf '%s\n' "$record" | sed 's/^ */  /'; fi
