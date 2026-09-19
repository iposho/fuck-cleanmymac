# Changelog

## 2.4.0 (2026-09-19)

### New

- **Cleanup scan** — `cleaner.sh --scan` (alias `--dry-run`): size of every category, exact folders, item counts, why each target is safe to remove, and every skipped target with its reason
- **Plan → apply** — `cleaner.sh --plan` saves the exact files to remove (with modification times); `cleaner.sh --apply` re-validates every folder and removes only files unchanged since the plan. Commands are whitelisted ids, tampered or foreign plans are refused. A normal run uses the same engine
- **doctor.sh** — diagnoses dependencies, installation, configuration (typos, invalid values), permissions (Trash/Full Disk Access, Accessibility), the SwiftBar plugin, cron schedule and recent failures, with a fix for each problem; `--online` checks for toolkit updates
- **SwiftBar** — *Scan*, *Create / Review / Apply Plan* in Clean Up; *Check Setup (doctor)*
- **tests/run.sh** — end-to-end tests in a throw-away HOME (install, plugin, scan/plan/apply, update failures, keyboard lock, doctor, uninstall)

### Fixed

- `update.sh`: a failed check (Homebrew, App Store, npm, pnpm, macOS) was reported as "up to date"; it is now "could not check" with the reason in the log, and the script exits non-zero
- Keyboard unlock reported success before the lock process had stopped; unlock now confirms the stop (SIGTERM, then SIGKILL) and reports a failure otherwise. Two simultaneous locks are prevented with an exclusive lock file
- Installer deleted existing files before linking; they are now moved to `~/.scripts/backups/`. Uninstall removes only its own symlinks
- Installer `chmod +x` made the installed copy look modified and blocked updates (`core.fileMode=false` now)
- Cleanup refused every path when `HOME` contained a symlink
- Health notification showed values twice (`SSD wear: 7%7`)
- QUICKSTART pointed to a non-existent `/main/install.sh`; manual install copied scripts without `lib.sh`

### Changed

- `fc_setup_path` appends missing tool folders instead of overriding the caller's `PATH`
- Installer checks Python 3.8+ and test-runs the SwiftBar plugin before linking it


## 2.3.0 (2026-09-19)

### New

- **SwiftBar: Keyboard Cleaning Mode** — lock the keyboard for 1 min, 5 min or until unlocked, countdown in the menu bar, ⌘⌃⌥K or menu unlock, display kept awake, Accessibility permission check with a shortcut to Settings
- **SwiftBar menu redesign** — *Clean Up* submenu with dry-run preview and last-run summary, Top CPU + Top Memory, System Tools submenu, Disk Utility and Keyboard Cleaning Mode as top-level items, settings shortcut
- **cleaner.sh** — one grouped log line per app, iOS DeviceSupport + old iPhone/iPad firmware, `uv cache prune`, all Chrome/Brave/Edge/Arc profiles, more Electron apps (Windsurf, Discord, Figma, Obsidian, Postman), Xcode simulator caches, per-run counters, `TEMP_FILE_AGE_DAYS`
- **health.sh** — SMART status, power-on hours, media errors, SSD temperature fallback, memory pressure, `HEALTH_EXTERNAL_IP=false`
- **lib.sh** — single-instance lock, log rollover at 1 MB, nvm / pnpm / bun / cargo on `PATH` for cron
- **install.sh** — `--no-pull`, `SWIFTBAR_PLUGIN_DIR`, plugin installed as a symlink to the repository

### Fixed

- Keyboard lock never worked: `fork()` after loading CoreFoundation, 64-bit pointer truncated by ctypes, errors hidden from SwiftBar, unlock delayed until the next key press, `keyboard-lock.py` run by SwiftBar as a separate plugin
- SwiftBar actions broke on paths with spaces (`Application Support`); a submenu parent cannot be clicked
- RAM was overstated: "stored in compressor" (uncompressed size) was counted instead of RAM occupied by the compressor
- SSD wear was never shown (`smartctl -i` has no health data; NVMe drives do not print "SMART support")
- Firewall status was "Unknown"; battery "~0 years" estimate; empty `Time Remaining: 0:00`
- `/tmp` cleanup deleted ssh-agent / tmux sockets and files of running programs
- `~/Library/Caches` always reported ❌ because of a few protected folders (now ⚠️ partial)
- Telegram media cache was never found (`stable/account-*`); Arc cache path; Chrome only cleaned the Default profile
- `gem cleanup` removed old gem versions (not a cache) — dropped
- Log rotation deleted logs during `--dry-run`
- Config file overrode `--verbose` / `--no-notify`
- `update.sh` under cron used Homebrew's npm instead of the nvm one, cut scoped npm names (`@scope/pkg` → `pkg`), could not parse pnpm's table output, reported partial Homebrew failures as a total failure
- `curl … | bash` install: `read` consumed the rest of the script
- Installer reported "Repository updated" even when `git pull` failed; overwrote a custom SwiftBar plugin folder
- Uninstall left cron entries for `update.sh` / `health.sh`
- `deploy.sh` required pushing to GitHub; now deploys local commits

### Changed

- SwiftBar plugin reads CPU / memory from the kernel (no `ps`/`vm_stat`/`sysctl` per refresh): ~150 ms → ~40 ms
- Faster `fc_run_timeout` polling (100 ms), no `tee` per log line, subprocess-free `fc_count_lines`
- Health report no longer runs `system_profiler`

## 2.2.2 (2026-06-22)

### New

- **Keyboard Lock** — SwiftBar menu action to block keyboard input for cleaning; unlock via menu or ⌘⌃⌥K; mouse and display stay active

## 2.2.1 (2026-06-22)

### New

- **VERSION file** — toolkit version tracked in repo root; shown in SwiftBar dropdown menu
- **CPU temperature in menu bar** — SwiftBar status line shows CPU temp when `osx-cpu-temp` or `istats` is available
- **CPU temperature in health notification** — summary notification includes temp reading
- **swiftbar/.swiftbarignore** — excludes README and cache files when repo `swiftbar/` folder is used as SwiftBar plugin directory

### Fixed

- **update.sh / health.sh logging** — both scripts now write to `~/.scripts/logs/update.log` and `health.log` on every run (interactive and cron); previously logs were only created when cron redirected stdout
- **SwiftBar log links** — log entries and logs folder use `/usr/bin/open` for reliable file opening on macOS
- **SwiftBar README plugin error** — install/deploy now set plugin directory to `~/Library/Application Support/SwiftBar/Plugins` and remove accidental `README.md` plugin bundles

### Changed

- Cron examples for `update.sh` and `health.sh` no longer need `>> log` redirect (scripts handle logging internally)
- Added `fc_init_run_log()` helper in `lib.sh` for shared run logging

## 2.2.0 (2026-04-14)

### New

- **Spotify cache cleaning** — clears `com.spotify.client` and `PersistentCache`
- **Chrome cache cleaning** — enabled under `CLEAN_BROWSER_CACHES`
- **deploy.sh** — syncs local repo to installed copy at `~/.scripts/fuck-cleanmymac` via `fetch + reset`; supports `--push` flag
- **uninstall.sh** — dedicated uninstaller wrapper
- **SwiftBar logs submenu** — collapsible submenus for processes and logs (cleanup, update, health); pipe character escaping in log lines
- **SwiftBar script path fallback** — when plugin is a copy (not symlink), falls back to `~/.scripts/` to find scripts

### Fixed

- **Path validation** — `eval echo` replaced with safe `${path/#\~/$HOME}` expansion; temp dir patterns tightened to reject `/tmp-evil` style paths
- **macOS realpath** — removed unsupported `-m` flag
- **npm cache** — fallback to manual `~/.npm` removal when `npm cache clean` fails or npm is not installed
- **Temp dir cleanup** — best-effort mode for `/tmp` and `/var/tmp` (skips system-locked files instead of reporting failure)
- **deploy.sh** — uses `fetch + reset --hard` instead of `pull` to avoid merge conflicts in installed copy
- **Log summary extraction** — matches both `SUMMARY` and `ИТОГО` keywords

### Changed

- Moved `install.sh`, `deploy.sh`, `uninstall.sh` into `scripts/` directory
- Unified summary marker to `SUMMARY:` across all scripts (update.sh was `ИТОГО`)
- SwiftBar UI translated to English
- Removed `cleaner.conf` ghost options (`ALLOWED_PATHS`, `EXCLUDE_PATHS`, `MAX_DEPTH`, `MIN_FILE_AGE_DAYS`) that were never implemented
- Deleted outdated `COMPLETION_REPORT.md` and `STATUS.md`
- Updated `README.md`: project structure, deploy workflow, correct config options, cron examples
- Updated `QUICKSTART.md`: correct config values (`false` not `"no"`), fixed cron example

## 2.1.0 (2024-03-31)

- **Configuration file** (`cleaner.conf`) — multi-location search, 10+ toggles for cleaning targets
- **Dry-run mode** (`--dry-run`) — preview what will be deleted with `🏜 [DRY-RUN]` prefix
- **CLI flags** — `--dry-run`, `--verbose`, `--no-notify`, `--help`
- **SwiftBar plugin** — real-time CPU, RAM, disk monitoring in menu bar; process list with kill action
- Full English translation of all scripts, comments, and documentation
- Added `load_config()`, `parse_arguments()`, `show_help()`, `debug_log()` to cleaner.sh
- Timestamped log files with 90-day auto-rotation
- Path validation blocks system directories (`/`, `/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/private`)

---

**Compatibility**: macOS 10.12+ / bash 4.0+
