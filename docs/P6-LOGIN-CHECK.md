# P6 — the one manual log-in check (Q1)

The visionary's ruling on Q1 (2026-10-21): the login steps of D42, D83, D84 and D104 are bound
to macOS's login-item registry, plus this one real log-in, checked by hand and recorded in the
phase report. The automated scenarios never log out (that would end every terminal session).

It uses the real package, so it installs the meter for the whole Mac, in `/Applications`; the
installer asks for an administrator password. Nothing else on the Mac is changed.

## 1. Install (D83)

1. Build: `npm run build:app` in the repository (makes `build/Meter.pkg`).
2. Double-click `build/Meter.pkg` and click through the installer.
3. **Expect:** the meter's item appears in the menu bar as the installer finishes, with nothing
   to fill in (any macOS notice that a background item was added may show; that is macOS's own).

## 2. Quit, then the next log-in (D104, D42)

1. Open the panel and click `Quit Meter`. **Expect:** the item leaves at once and does not come
   back within a minute.
2. Restart the Mac (or log out and back in). Do not open the meter.
3. **Expect:** the meter's item appears in the menu bar by itself after the log-in.

## 3. Record what macOS shows

After the log-in, in Terminal:

```sh
launchctl print gui/$(id -u)/local.menubar-meter.Meter | grep -E '^\t(state|pid|runs|last exit code) ='
ps -o pid=,ppid=,lstart=,comm= -p "$(launchctl print gui/$(id -u)/local.menubar-meter.Meter | awk '$1=="pid"{print $3}')"
sudo -n /usr/bin/sfltool dumpbtm | grep -B6 -A4 'LaunchAgents/local.menubar-meter.Meter.plist' | grep -E 'Type|Disposition|URL|Executable'
```

**Expect:** `state = running`; the process's parent is `1` (launchd), started at the log-in, its
program `/Applications/Meter.app/Contents/MacOS/Meter`; the registry lists a legacy agent,
`[enabled, …]`, for `~/Library/LaunchAgents/local.menubar-meter.Meter.plist`.

Paste the three outputs and a yes or no for steps 1.3, 2.1 and 2.3 into the phase report.

## Taking it back afterwards (only if wanted; clean removal is not scoped, D82)

```sh
launchctl bootout gui/$(id -u)/local.menubar-meter.Meter
rm ~/Library/LaunchAgents/local.menubar-meter.Meter.plist
```

then drag `/Applications/Meter.app` to the Trash.
