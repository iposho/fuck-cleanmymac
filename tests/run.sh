#!/bin/bash
# End-to-end tests in a throw-away HOME. No network, no sudo, nothing outside the sandbox
# is modified: git/osascript/open/crontab/defaults/brew/mas/npm/softwareupdate are stubbed.
#
# Usage: tests/run.sh [-k]   (-k keeps the sandbox for inspection)

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEEP=false
[[ "${1:-}" == "-k" ]] && KEEP=true

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/fcm-tests.XXXXXX")
REAL_HOME="$HOME"
export HOME="$SANDBOX/home"
STUBS="$SANDBOX/stubs"
mkdir -p "$HOME" "$STUBS"
export PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin"
export FC_NO_NOTIFY=true HEALTH_EXTERNAL_IP=false PYTHONDONTWRITEBYTECODE=1

cleanup() {
    if [[ "$KEEP" == true ]]; then
        echo "Sandbox kept: $SANDBOX"
    else
        chmod -R u+w "$SANDBOX" 2>/dev/null
        rm -rf "$SANDBOX"
    fi
}
trap cleanup EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$1"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/      /' | tail -15; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
contains() { printf '%s' "$1" | grep -qF -- "$2"; }
section() { printf '\n▶ %s\n' "$1"; }

stub() {  # stub <name> <body>
    printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"
    chmod +x "$STUBS/$1"
}
stub osascript 'exit 0'
stub open 'echo "open $*" >> "$HOME/open.log"'
stub defaults 'exit 1'          # no SwiftBar preferences
stub crontab 'if [ "$1" = -l ]; then cat "$HOME/crontab" 2>/dev/null; else cat > "$HOME/crontab"; fi'

# A snapshot of the working tree as a local git repo = what the installer clones.
SNAPSHOT="$SANDBOX/snapshot"
mkdir -p "$SNAPSHOT"
rsync -a --exclude .git --exclude .history --exclude '__pycache__' --exclude .DS_Store "$REPO/" "$SNAPSHOT/"
git -C "$SNAPSHOT" init -q -b main
git -C "$SNAPSHOT" -c user.email=t@t -c user.name=t add -A
git -C "$SNAPSHOT" -c user.email=t@t -c user.name=t commit -qm snapshot
INSTALL_DIR="$HOME/.scripts/fuck-cleanmymac"
PLUGINS="$SANDBOX/Plugins"

# ---------------------------------------------------------------------------
section "install into an empty HOME"
mkdir -p "$HOME/.scripts" "$PLUGINS/$(printf 'system-monitor.5s.py')"
echo "my own script" > "$HOME/.scripts/health.sh"             # foreign file → backup
echo "x" > "$PLUGINS/system-monitor.5s.py/system-monitor.5s.py" # old per-plugin folder → backup
echo "other" > "$PLUGINS/other.1m.sh"
touch "$HOME/.zshrc"

out=$(FC_REPO_URL="$SNAPSHOT" SWIFTBAR_PLUGIN_DIR="$PLUGINS" \
    bash "$SNAPSHOT/scripts/install.sh" --skip-deps --skip-cron < /dev/null 2>&1)
rc=$?
check "installer exits 0" test "$rc" -eq 0
[[ "$rc" -eq 0 ]] || bad "installer output" "$out"
check "repository cloned" test -f "$INSTALL_DIR/lib.sh"
for s in cleaner health update; do
    check "~/.scripts/$s.sh → installed copy" test "$(readlink "$HOME/.scripts/$s.sh")" = "$INSTALL_DIR/$s.sh"
done
check "foreign health.sh backed up, not deleted" \
    bash -c 'grep -qx "my own script" "$HOME"/.scripts/backups/*/health.sh'
check "config created" test -f "$HOME/.config/fuck-cleanmymac/cleaner.conf"
check "PATH line added to .zshrc" grep -q '.scripts' "$HOME/.zshrc"
if [[ -d /Applications/SwiftBar.app || -d "$REAL_HOME/Applications/SwiftBar.app" ]]; then
    check "plugin is a symlink into the install" \
        test "$(readlink "$PLUGINS/system-monitor.5s.py")" = "$INSTALL_DIR/swiftbar/system-monitor.5s.py"
    check "old plugin folder backed up" \
        bash -c 'test -f "$HOME"/.scripts/backups/*/system-monitor.5s.py/system-monitor.5s.py'
    check "other plugins untouched" test -f "$PLUGINS/other.1m.sh"
    check "plugin test run reported" contains "$out" "Plugin test run OK"
else
    echo "  - SwiftBar.app not installed: plugin checks skipped"
fi

check "doctor.sh linked" test "$(readlink "$HOME/.scripts/doctor.sh")" = "$INSTALL_DIR/doctor.sh"
chmod 644 "$INSTALL_DIR/lib.sh"; chmod 755 "$INSTALL_DIR/lib.sh"
check "installed tree stays clean after chmod (updates not blocked)" \
    test -z "$(git -C "$INSTALL_DIR" status --porcelain --untracked-files=no)"

section "re-install is idempotent"
out=$(FC_REPO_URL="$SNAPSHOT" SWIFTBAR_PLUGIN_DIR="$PLUGINS" \
    bash "$INSTALL_DIR/scripts/install.sh" --no-pull --skip-deps --skip-cron < /dev/null 2>&1)
check "second run exits 0" test $? -eq 0
check "no new backups for our own symlinks" bash -c '! printf "%s" "$1" | grep -q "moved to"' _ "$out"

# ---------------------------------------------------------------------------
section "SwiftBar plugin"
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin /usr/bin/python3 "$INSTALL_DIR/swiftbar/system-monitor.5s.py" 2>&1)
check "runs with system python and a minimal PATH" test $? -eq 0
check "menu bar line has no colour override" bash -c 'printf "%s\n" "$1" | head -1 | grep -q "| size=11$"' _ "$out"
check "paths in actions are quoted" bash -c '! printf "%s" "$1" | grep -E "bash=/[^\" ]* [^|]*param" | grep -v "bash=/usr/bin/open" | grep -q .' _ "$out"

# ---------------------------------------------------------------------------
section "cleaner: scan, plan, apply"
C="$HOME/Library/Caches"
mkdir -p "$C/keep-me" "$C/old" "$HOME/.Trash"
dd if=/dev/zero of="$C/old/blob" bs=1024 count=2048 2>/dev/null
touch "$C/stable"
cat > "$HOME/.config/fuck-cleanmymac/cleaner.conf" <<'EOF'
CLEAN_DOCKER=false
CLEAN_PACKAGE_MANAGERS=false
CLEAN_TEMP_FILES=false
EOF
CLEANER="$INSTALL_DIR/cleaner.sh"

out=$(bash "$CLEANER" --scan --no-notify 2>&1)
check "scan shows size and path" bash -c 'printf "%s" "$1" | grep -qE "User caches +[0-9.]+ (KB|MB)"' _ "$out"
check "scan shows the folder and item count" contains "$out" "~/Library/Caches ("
check "scan lists disabled categories as skipped" contains "$out" "disabled in cleaner.conf"
check "scan deletes nothing" test -f "$C/old/blob"

bash "$CLEANER" --plan --no-notify > /dev/null 2>&1
PLAN="$HOME/.cache/fuck-cleanmymac/cleanup-plan.tsv"
check "plan written with private permissions" test "$(stat -f %Lp "$PLAN")" = 600
sleep 1.1
touch "$C/keep-me"             # changed after the plan → kept
touch "$C/new-after-plan"      # not in the plan → kept
out=$(bash "$CLEANER" --apply --no-notify 2>&1)
check "apply removes planned, unchanged items" test ! -e "$C/old"
check "apply keeps items changed since the plan" test -e "$C/keep-me"
check "apply keeps items created after the plan" test -e "$C/new-after-plan"
check "apply reports kept items" contains "$out" "changed since the scan — kept"
check "applied plan is archived" test -f "$PLAN.applied"

bash "$CLEANER" --plan --no-notify > /dev/null 2>&1
C_REAL=$(cd "$C" && pwd -P)
printf 'C\t90\tX\tEvil cmd\trm -rf ~\t0\tx\nT\t91\tX\tEvil dir\t/etc\t0\t1\tx\nI\t91\t0\t/etc/hosts\nT\t92\tX\tEvil item\t%s\t0\t1\tx\nI\t92\t0\t/etc/passwd\n' "$C_REAL" >> "$PLAN"
out=$(bash "$CLEANER" --apply --no-notify 2>&1)
check "unknown command id refused" contains "$out" "unknown command 'rm -rf ~' in plan — refused"
check "folder outside safe paths refused" contains "$out" "path refused by safety checks (/etc)"
check "item outside its folder refused" contains "$out" "outside ~/Library/Caches — refused"
check "/etc untouched" test -f /etc/hosts

bash "$CLEANER" --plan --no-notify > /dev/null 2>&1
chmod 666 "$PLAN"
out=$(bash "$CLEANER" --apply --no-notify 2>&1)
check "world-writable plan refused" contains "$out" "writable by others"

# ---------------------------------------------------------------------------
section "update: failed checks are never 'up to date'"
stub brew 'case "$1" in update) exit 0;; outdated) echo "Error: simulated failure" >&2; exit 2;; *) exit 0;; esac'
stub mas 'exit 0'
stub softwareupdate 'echo "No new software available." >&2; exit 0'
stub npm 'case "$1" in prefix) echo "$HOME/npm";; outdated) exit 0;; esac'
mkdir -p "$HOME/npm/lib/node_modules"
out=$(UPDATE_NPM_BINS="$STUBS/npm" bash "$INSTALL_DIR/update.sh" 2>&1; echo "rc=$?")
log=$(cat "$HOME/.scripts/logs/update.log")
check "brew failure reported" contains "$log" "Could not check Homebrew (exit code 2)"
check "brew failure reason logged" contains "$log" "simulated failure"
check "no false 'Homebrew up to date'" bash -c '! printf "%s" "$1" | grep -q "All Homebrew packages are up to date"' _ "$log"
check "summary lists failed source" contains "$log" "Could not check: Homebrew"
check "non-zero exit on failed check" contains "$out" "rc=1"
check "working sources still checked" contains "$log" "macOS is up to date"

stub brew 'case "$1" in outdated) exit 0;; *) exit 0;; esac'
stub softwareupdate 'echo "Cannot connect to the server" >&2; exit 1'
stub npm 'case "$1" in prefix) echo "$HOME/npm";; outdated) echo "npm ERR! network" >&2; exit 1;; esac'
: > "$HOME/.scripts/logs/update.log"
UPDATE_NPM_BINS="$STUBS/npm" bash "$INSTALL_DIR/update.sh" > /dev/null 2>&1
log=$(cat "$HOME/.scripts/logs/update.log")
check "npm network error is a failed check" contains "$log" "Could not check npm"
check "softwareupdate error is a failed check" contains "$log" "Could not check macOS updates"
check "brew success still reported" contains "$log" "All Homebrew packages are up to date"

stub npm 'case "$1" in prefix) echo "$HOME/npm";; outdated) echo "$HOME/npm/lib/node_modules/@s/p:@s/p@2.0.0:@s/p@1.0.0:@s/p@2.0.0:global"; exit 1;; update) exit 0;; esac'
: > "$HOME/.scripts/logs/update.log"
UPDATE_NPM_BINS="$STUBS/npm" bash "$INSTALL_DIR/update.sh" > /dev/null 2>&1
log=$(cat "$HOME/.scripts/logs/update.log")
check "npm exit 1 with results is a successful check" contains "$log" "@s/p: 1.0.0 → 2.0.0"

# ---------------------------------------------------------------------------
section "health summary"
out=$(bash "$INSTALL_DIR/health.sh" > /dev/null 2>&1; grep '^Summary:' "$HOME/.scripts/logs/health.log" | tail -1)
check "summary line present" contains "$out" "Summary: SSD wear:"
check "no duplicated values (e.g. 7%7)" bash -c '! printf "%s" "$1" | grep -qE "[0-9]%[0-9]|N/A[0-9]"' _ "$out"

# ---------------------------------------------------------------------------
section "keyboard lock: unlock is confirmed, single daemon"
KL="$INSTALL_DIR/swiftbar/keyboard-lock.py"
FAKE="$SANDBOX/keyboard-lock-fake.py"
cat > "$FAKE" <<'EOF'
import fcntl, os, signal, sys, time, pathlib
d = pathlib.Path.home() / ".config/fuck-cleanmymac"; d.mkdir(parents=True, exist_ok=True)
fd = os.open(d / "keyboard-lock.lock", os.O_CREAT | os.O_RDWR, 0o600); fcntl.flock(fd, fcntl.LOCK_EX)
if sys.argv[1] == "stubborn": signal.signal(signal.SIGTERM, signal.SIG_IGN)
if sys.argv[1] != "orphan": (d / "keyboard-lock.pid").write_text(f"{os.getpid()} 0")
print("ready", flush=True); time.sleep(30)
EOF
for mode in polite stubborn; do
    python3 "$FAKE" "$mode" > /dev/null & sleep 0.5
    check "$mode: second daemon refused" bash -c '[ "$(python3 "$1" _daemon 60)" = error:already-locked ]' _ "$KL"
    python3 "$KL" unlock > /dev/null 2>&1
    check "$mode: unlock stops the daemon" test "$(python3 "$KL" status)" = unlocked
done
python3 "$FAKE" orphan > /dev/null & ORPHAN=$!; sleep 0.5
python3 -c 'import time; time.sleep(30)' keyboard-lock-decoy & DECOY=$!; sleep 0.2
echo "$DECOY 0" > "$HOME/.config/fuck-cleanmymac/keyboard-lock.pid"
python3 "$KL" unlock > /dev/null 2>&1
check "unlock fails while the lock is still held" test $? -ne 0
check "PID file kept after a failed unlock" test -f "$HOME/.config/fuck-cleanmymac/keyboard-lock.pid"
kill "$ORPHAN" "$DECOY" 2>/dev/null

# ---------------------------------------------------------------------------
section "doctor"
rm -f "$PLAN" "$HOME"/.scripts/logs/cleaner_*.log   # leftovers of the tampering tests above
out=$(SWIFTBAR_PLUGIN_DIR="$PLUGINS" bash "$INSTALL_DIR/doctor.sh" 2>&1); rc=$?
check "doctor passes on a fresh install" test "$rc" -eq 0
[[ "$rc" -eq 0 ]] || bad "doctor output" "$(printf '%s' "$out" | grep -E '❌' )"
check "doctor reports the schedule section" contains "$out" "⏰ Schedule"
echo "CLEAN_TRASHH=false" >> "$HOME/.config/fuck-cleanmymac/cleaner.conf"
echo "CLEAN_DOCKER=maybe" >> "$HOME/.config/fuck-cleanmymac/cleaner.conf"
mv "$HOME/.scripts/update.sh" "$SANDBOX/update.sh.moved"
ln -s "$SANDBOX/missing/update.sh" "$HOME/.scripts/update.sh"
printf '0 9 * * 1 %s/.scripts/nope/cleaner.sh\n' "$HOME" > "$HOME/crontab"
out=$(SWIFTBAR_PLUGIN_DIR="$PLUGINS" bash "$INSTALL_DIR/doctor.sh" 2>&1); rc=$?
check "doctor fails on problems" test "$rc" -ne 0
check "doctor flags a config typo" contains "$out" "Unknown setting 'CLEAN_TRASHH'"
check "doctor flags an invalid value" contains "$out" "CLEAN_DOCKER='maybe' must be true or false"
check "doctor flags a broken link" contains "$out" "update.sh is a broken link"
check "doctor flags a cron job with a missing script" contains "$out" "which does not exist"
rm "$HOME/.scripts/update.sh"; mv "$SANDBOX/update.sh.moved" "$HOME/.scripts/update.sh"
sed -i '' '/CLEAN_TRASHH\|CLEAN_DOCKER=maybe/d' "$HOME/.config/fuck-cleanmymac/cleaner.conf"

# ---------------------------------------------------------------------------
section "uninstall"
echo "keep" > "$HOME/.scripts/mine.sh"
printf '0 9 * * 1 %s/.scripts/cleaner.sh\n5 5 * * * /usr/bin/true\n' "$HOME" > "$HOME/crontab"
out=$(SWIFTBAR_PLUGIN_DIR="$PLUGINS" bash "$INSTALL_DIR/scripts/install.sh" --uninstall < /dev/null 2>&1)
check "our symlinks removed" test ! -e "$HOME/.scripts/cleaner.sh" -a ! -e "$HOME/.scripts/doctor.sh"
check "unrelated files kept" test -f "$HOME/.scripts/mine.sh"
check "our cron job removed, others kept" bash -c '! grep -q cleaner.sh "$HOME/crontab" && grep -q /usr/bin/true "$HOME/crontab"'
check "plugin symlink removed" test ! -e "$PLUGINS/system-monitor.5s.py"
check "other plugins untouched" test -f "$PLUGINS/other.1m.sh"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
