# P6: the one manual log-in check (Q1)

The visionary's ruling on Q1 (2026-10-21): the login steps of D42, D83, D84 and D104 are bound
to macOS's login-item registry, plus this one real log-in, checked by hand and recorded in the
phase report. The automated scenarios never log out (that would end every terminal session).

One log-out and log-in covers every step that needs a real log-in, in this order:

| Step | What | Rule |
|---|---|---|
| 2 | install from nothing, through the installer's root postinstall | D83 |
| 3 | install the newer version over the older copy | D84 |
| 4 | Quit Meter: gone at once, still gone a minute later | D65, D104 |
| 5 and 6 | log out and in: the newer meter appears by itself, although it was quit | D42, D104, D83, D84 ("at the next login") |

Nothing needs a second log-in: a quit lasts only until the next log-in, so step 4's quit and
step 6's appearing are one log-in apart, and the newer version is the one that appears.

**Logging out ends every Terminal session, the build session too.** So every step appends what
macOS shows to `~/p6-login-check.txt`; after the log-in, start a new session and give it that
file. Save your work first.

It uses the real package: `Meter.app` goes into `/Applications` for the whole Mac and the
installer asks for an administrator password. `scripts/login-check.sh` is read-only; it asks for
your password too (for `sudo sfltool dumpbtm`, the login-item registry) unless sudo remembers it.

## 1. Prepare (Terminal)

```
cd ~/gitrepos/menubar-meter && npm run build:app
sh scripts/login-check.sh "1 before" | tee ~/p6-login-check.txt
```

**Expect:** `version: not installed`, `job: not loaded`, `processes: none`, `copies: none`,
`LaunchAgent file: none`, `registry: no record`. If anything is installed or running, take it
back first (the last section).

## 2. Install from nothing (D83, the root postinstall)

```
open build/check/Meter-0.0.9.pkg
```

Click Continue, Install, give the password, Close.

**Expect:** the meter's item appears in the menu bar as the installer finishes, and no window
asks for anything (a macOS "Background Items Added" notice may show; that is macOS's own).

```
sh scripts/login-check.sh "2 installed 0.0.9" | tee -a ~/p6-login-check.txt
```

**Expect:** `version: 0.0.9`; `state = running`; `program = /Applications/Meter.app/Contents/MacOS/Meter`;
the job's process user is your own name, not `root`; ppid 1; `processes: 1`; `copies:
/Applications/Meter.app` only; the registry has `Disposition: [enabled, ...` and `Executable
Path: /Applications/Meter.app/Contents/MacOS/Meter`.

## 3. Install the newer version over it (D84)

```
open build/Meter.pkg
```

Click through as before.

**Expect:** the item stays (or blinks once) in the menu bar.

```
sh scripts/login-check.sh "3 installed 0.1.0" | tee -a ~/p6-login-check.txt
```

**Expect:** `version: 0.1.0`; `state = running`; a pid different from step 2's; user your own
name; `processes: 1`; `copies: /Applications/Meter.app` only; the registry enabled as in step 2.
Click the item: the panel's last rows are `Open Activity Monitor…` and `Quit Meter`, and nothing
offers an update.

## 4. Quit Meter (D65, D104)

Click `Quit Meter`. **Expect:** the item leaves the menu bar at once. Do not open the meter
again.

```
sleep 60; sh scripts/login-check.sh "4 a minute after Quit" | tee -a ~/p6-login-check.txt
```

**Expect:** `state = not running` (or `job: loaded` with `pid = none`); `last exit code = 0`;
`processes: none`; and no meter in the menu bar.

## 5. Log out and in

Apple menu, `Log Out <you>…`; untick "Reopen windows when logging back in"; Log Out. Log back
in. Do not open the meter.

**Expect:** the meter's item appears in the menu bar by itself within a few seconds of the
desktop. (Logging out sends the meter a terminate request, which counts as a quit, as Activity
Monitor's Quit does; a quit lasts only until the next log-in, which loads the job afresh.)

## 6. Record the log-in (a new Terminal window)

```
cd ~/gitrepos/menubar-meter
{ sh scripts/login-check.sh "6 after log-in"; last -1 "$USER"; } | tee -a ~/p6-login-check.txt
```

**Expect:** `version: 0.1.0`; `state = running`; `runs = 1`; user your own name; ppid 1; its
start time a few seconds after the log-in time `last` prints; `processes: 1`; registry enabled.

Then start a build session and say: "P6 login check done, read ~/p6-login-check.txt", with a
yes or no for each of these:

- step 2: the item came right after the installer with nothing to fill in;
- step 3: the newer one replaced it;
- step 4: it left at once and stayed gone;
- step 5: it came back by itself at the log-in.

## Before the next `npm test`

The installed meter holds Control-Option-Command-M and starts at every log-in, so click `Quit
Meter` before any test run (the harness refuses to run beside a meter it did not start), or take
it back.

## Taking it back (only if wanted; clean removal is not scoped, D82)

```
launchctl bootout gui/$(id -u)/local.menubar-meter.Meter
rm ~/Library/LaunchAgents/local.menubar-meter.Meter.plist
sudo rm -rf /Applications/Meter.app && sudo pkgutil --forget local.menubar-meter.Meter.pkg
```
