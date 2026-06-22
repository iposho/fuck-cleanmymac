# Changelog

## 2.2.1 (2026-06-22)

### New

- **VERSION file** — toolkit version tracked in repo root; shown in SwiftBar dropdown menu
- **CPU temperature in menu bar** — SwiftBar status line shows CPU temp when `osx-cpu-temp` or `istats` is available
- **CPU temperature in health notification** — summary notification includes temp reading

### Fixed

- **update.sh / health.sh logging** — both scripts now write to `~/.scripts/logs/update.log` and `health.log` on every run (interactive and cron); previously logs were only created when cron redirected stdout
- **SwiftBar log links** — log entries and logs folder use `/usr/bin/open` for reliable file opening on macOS

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
