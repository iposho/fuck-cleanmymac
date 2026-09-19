# fuck-cleanmymac 🧹

![Hero poster](preview.webp)

A comprehensive macOS system cleaner and health monitor toolkit designed to safely free up disk space, monitor system health, and provide automated maintenance.

## Features

### 🧹 **Cleaning (`cleaner.sh`)**
- **Safe path validation** - prevents accidental deletion of system directories
- **Scan** (`--scan`, alias `--dry-run`) - size of every category, the exact folders, item counts, why each is safe to remove, and what was skipped and why
- **Plan → apply** (`--plan`, `--apply`) - save the list of files to remove, review it, then execute exactly that plan; paths are re-validated and anything changed since the plan is kept
- **Docker cleanup** - removes unused containers, images, build cache and anonymous volumes (named volumes are kept)
- **Package manager caches** - cleans npm, yarn, pnpm, bun, Homebrew, pip, cargo, Xcode DerivedData
- **Application caches** - Cursor, VS Code, Windsurf, Slack, Notion, Discord, Figma, Telegram media, Spotify, JetBrains, Zed
- **Browser caches** - every profile of Chrome, Arc, Brave, Edge + Firefox (cookies and history are kept)
- **System maintenance** - cleans user caches, logs, trash and stale temp files
- **Safe temp cleanup** - only your own `/tmp` entries older than 2 days; sockets (ssh-agent, tmux) are never touched
- **Honest reporting** - partially cleaned folders (locked / SIP-protected items) are reported as ⚠️, not ❌
- **Single instance** - cron and a manual run cannot clean at the same time
- **Logging** - timestamped logs with automatic rotation (90 days retention)
- **Notifications** - displays system notifications when cleanup completes
- **Configuration file** - customize cleaning behavior via `cleaner.conf`

### 🏥 **Health Monitor (`health.sh`)**
- **System information** - displays Mac model, CPU, memory, OS version, uptime
- **Storage health** - SMART status, SSD wear level, data written/read, power-on hours, SSD temperature (via smartctl)
- **Battery status** - reports cycle count (vs. Apple's 1000-cycle rating), capacity, health assessment
- **Memory usage** - Activity Monitor-style breakdown (app, wired, compressed) and memory pressure
- **CPU load** - displays load average and top 5 CPU-consuming processes
- **Temperature monitoring** - CPU temperature (if tools available), SSD sensor as a fallback on Apple Silicon
- **Network info** - local and external IP addresses (`HEALTH_EXTERNAL_IP=false` skips the external lookup)
- **Security status** - Firewall, FileVault, System Integrity Protection status
- **System notifications** - sends summary to Notification Center

### ⚡ **Update Utility (`update.sh`)**
- **Homebrew updates** - upgrades installed packages
- **App Store updates** - updates apps via `mas` (if installed)
- **Node package updates** - updates global `npm` packages of every node it finds (nvm default + Homebrew) and `pnpm` globals
- **Works from cron** - finds nvm / pnpm / bun / cargo binaries without a login shell
- **System updates** - checks available macOS updates (`softwareupdate -l`)
- **Honest summary** - re-checks what is still outdated after upgrading; a source that could not be checked is reported as "could not check" with the reason in the log (never as "up to date"), and the script exits non-zero

### 🩹 **Doctor (`doctor.sh`)**
- **Dependencies** - git, Python 3.8+ for SwiftBar, Homebrew, smartctl, mas; which npm scheduled runs will use
- **Installation** - installed copy, local changes that would block updates, available updates (`--online`), command symlinks, PATH
- **Configuration** - syntax, unknown settings (typos), invalid values, disabled categories
- **Permissions** - writable log/state folders, Trash access (Full Disk Access), Accessibility for SwiftBar
- **SwiftBar** - running, plugin link, disabled plugin, leftover copies, plugin test run and refresh time
- **Schedule** - cron jobs and LaunchAgents, missing scripts, last runs and their failures
- **State** - running jobs, stale locks, saved cleanup plan
- Every problem comes with a fix; exits non-zero when something is broken

### 📊 **SwiftBar Plugin**
- Real-time CPU, RAM and free disk in the menu bar
- Clean Up (Clean Now, Scan, Create / Review / Apply Plan, last-run summary), Update, Health Report, Check Setup
- **Keyboard Cleaning Mode** - block the keyboard (1 min, 5 min or until you unlock it) to wipe it
- Top CPU / Top Memory processes with a quit action, logs, handy tools
- Lightweight: reads CPU/RAM directly from the kernel (~40 ms per refresh)

**[📊 Detailed SwiftBar Guide](swiftbar/README.md)**

## Installation

### Automatic Installation (Recommended)

The easiest way to install **fuck-cleanmymac** on macOS is using the auto-installation script:

#### One-liner Installation
```bash
curl -sL https://raw.githubusercontent.com/iposho/fuck-cleanmymac/main/scripts/install.sh | bash
```

This single command will:
- ✅ Clone the repository to `~/.scripts/fuck-cleanmymac`
- ✅ Create necessary directories (`~/.scripts`, `~/.config/fuck-cleanmymac`, `~/.scripts/logs`)
- ✅ Set up symlinks in `~/.scripts` for easy access (existing files are moved to `~/.scripts/backups/`, never deleted)
- ✅ Add scripts to your PATH (`.zshrc` or `.bashrc`)
- ✅ Copy configuration template to `~/.config/fuck-cleanmymac/cleaner.conf`
- ✅ Optionally install dependencies (smartmontools, osx-cpu-temp, mas)
- ✅ Optionally set up automatic weekly cleanup via cron
- ✅ Optionally install SwiftBar menu bar plugin

> [!TIP]
> **[🛠 Detailed Setup & Deployment Guide](scripts/README.md)**  
> See the `scripts` documentation for all installation flags and deployment workflows.

#### Non-Interactive Installation
If you prefer to skip interactive prompts, you can specify options:

```bash
./scripts/install.sh --skip-deps --skip-cron --skip-swiftbar
```

```bash
./scripts/install.sh --help             # Show all available options
```

See [scripts/README.md](scripts/README.md) for a full breakdown of installation and uninstallation options.

#### After Installation
Once installed, you can use the scripts from anywhere:

```bash
cleaner.sh                      # Run cleanup
cleaner.sh --scan               # Preview: sizes, paths, reasons
health.sh                       # Check system health
update.sh                       # Check for updates
doctor.sh                       # Check the setup
```

#### Update Existing Installation
To update an existing installation (SwiftBar: *Update fuck-cleanmymac*):
```bash
~/.scripts/fuck-cleanmymac/scripts/install.sh --skip-deps --skip-cron
```

Or reinstall:
```bash
curl -sL https://raw.githubusercontent.com/iposho/fuck-cleanmymac/main/scripts/install.sh | bash
```

### Uninstallation

If you want to remove the toolkit and all its components (symlinks, cron jobs, etc.), use the uninstallation script:

#### Using the dedicated script
```bash
./scripts/uninstall.sh
```

#### Using the installation script flag
```bash
./scripts/install.sh --uninstall
```

> [!NOTE]
> The uninstaller removes only what the installer created (its symlinks, its cron jobs, the SwiftBar plugin link) and asks before deleting logs and configuration files.

---

### Manual Installation

If you prefer to set up manually or the auto-installer doesn't work for you:

The scripts share `lib.sh` and read `VERSION` from their own folder, so keep the checkout in one piece and **link** the scripts instead of copying them (symlinks are resolved to the checkout).

#### 1. Clone the repository
```bash
git clone https://github.com/iposho/fuck-cleanmymac.git ~/.scripts/fuck-cleanmymac
```

#### 2. Link the commands and add them to PATH
```bash
for s in cleaner health update doctor; do
    ln -sf ~/.scripts/fuck-cleanmymac/$s.sh ~/.scripts/$s.sh
done
echo 'export PATH="$HOME/.scripts:$PATH"' >> ~/.zshrc
mkdir -p ~/.config/fuck-cleanmymac
cp -n ~/.scripts/fuck-cleanmymac/cleaner.conf ~/.config/fuck-cleanmymac/
```

#### 3. Check the result
```bash
~/.scripts/doctor.sh
```

#### 4. SwiftBar Plugin (Optional)
See [swiftbar/README.md](swiftbar/README.md) for manual installation instructions and feature details.

## Usage

### Basic Cleaning
```bash
./cleaner.sh
```

### Scan (Preview)
See what would be cleaned — nothing is deleted:
```bash
./cleaner.sh --scan          # alias: --dry-run, -n
```

```text
🌐 Browsers — 483 MB
   • Chrome cache (all profiles)            483 MB
      33 folders, 483 items — browser cache; cookies, history and passwords are kept
🗑  System — 1.3 GB
   • User caches                            1.3 GB
      ~/Library/Caches (412 items) — app caches, rebuilt automatically
⏭  Skipped
   • Docker: daemon is not running
   • Temporary files (/tmp): 5 entries kept (newer than 2 days, sockets, system or other users' files)
📊 Reclaimable: ~1.8 GB in 36 targets (895 files/folders)
```

### Plan → Apply
Save the exact list of files, review it, then execute it:
```bash
./cleaner.sh --plan                                   # writes ~/.cache/fuck-cleanmymac/cleanup-plan.tsv
open -t ~/.cache/fuck-cleanmymac/cleanup-plan.tsv     # review
./cleaner.sh --apply                                  # execute the plan
```

When applying, every folder is re-validated (safe location, still a real folder, not replaced by a symlink) and only files that still exist **with the same modification time** as in the plan are removed. Files that changed or appeared since are kept and reported. Cleanup commands are stored as ids from a fixed whitelist (e.g. `npm_cache`), never as shell text, and plans that are not yours or are writable by others are refused. The applied plan is renamed to `*.applied`.

### With Options
```bash
./cleaner.sh --scan --verbose    # List every folder and skipped target
./cleaner.sh --no-notify         # Skip notifications
```

### Help
```bash
./cleaner.sh --help
```

### Health Check
```bash
./health.sh
```

### System Updates
```bash
./update.sh
```
Exits non-zero when a source (Homebrew, App Store, npm, pnpm, macOS) could not be checked; the reason is in `~/.scripts/logs/update.log`.

### Setup Check
```bash
./doctor.sh            # --online also checks GitHub for toolkit updates
```

## Configuration

### Config File Location
The script looks for configuration in this order:
1. `~/.config/fuck-cleanmymac/cleaner.conf`
2. `~/.scripts/cleaner.conf`
3. `./cleaner.conf` (project directory)

### Create Custom Config
```bash
mkdir -p ~/.config/fuck-cleanmymac
cp cleaner.conf ~/.config/fuck-cleanmymac/cleaner.conf
```

### Configuration Options
Edit the config file to customize:
- **LOG_DIR** - directory for log files (default: `~/.scripts/logs`)
- **LOG_RETENTION_DAYS** - auto-delete logs older than N days (default: 90)
- **CLEAN_SYSTEM_CACHES** - user caches in `~/Library/Caches` (default: true)
- **CLEAN_APP_CACHES** - Electron apps/editors, Telegram media, Spotify, JetBrains (default: true)
- **CLEAN_PACKAGE_MANAGERS** - npm, yarn, pnpm, bun, Homebrew, pip, cargo, Xcode (default: true)
- **CLEAN_BROWSER_CACHES** - Chrome, Arc, Brave, Edge, Firefox caches (default: true)
- **CLEAN_TRASH** - empty Trash (default: true)
- **CLEAN_TEMP_FILES** - stale entries in `/tmp`, `/var/tmp` (default: true)
- **TEMP_FILE_AGE_DAYS** - minimum age of temp entries to delete (default: 2)
- **CLEAN_DOCKER** - Docker system prune (default: true)
- **SHOW_NOTIFICATION** - macOS notification after cleanup (default: true)

### Example Config
```bash
# Disable Docker cleanup
CLEAN_DOCKER=false

# Change log location
LOG_DIR="$HOME/Library/Logs/cleanmymac"

# Keep logs for 180 days instead of 90
LOG_RETENTION_DAYS=180
```

## Automation with Cron

### Weekly Cleanup (Every Monday at 9 AM)
```bash
# cleaner.sh writes its own log, no >> redirect needed
0 9 * * 1 ~/.scripts/cleaner.sh 2>&1
```

### Weekly System Updates (Every Friday at 12 PM)

```bash
# update.sh writes its own log, no >> redirect needed
0 12 * * 5 ~/.scripts/update.sh
```

### Monthly Health Check (1st of month at 12 PM)

```bash
# health.sh writes its own log, no >> redirect needed
0 12 1 * * ~/.scripts/health.sh
```

> **Tip:** use `crontab -l` to view and `crontab -` with a pipe to edit without vim.

> **Notes:** cron does not run while the Mac sleeps and does not catch up later — pick a time when the Mac is usually awake. Emptying the Trash from cron needs Full Disk Access for `/usr/sbin/cron`. `doctor.sh` checks the schedule, the scripts it points to and the last runs.

## Safety Features

### Path Validation
- Deletes only inside your home folder (symlinks resolved) or the temp folders — everything else (`/System`, `/usr`, `/etc`, `/Library`, `/Applications`, …) is refused
- Refuses `$HOME` itself, `~/Library`, `~/Library/Application Support`, `~/Documents`, `~/Desktop`, and a degenerate `HOME` such as `/`
- Temp directories (`/tmp`, `/var/tmp`) are cleaned by age and ownership only
- Validates all paths before deletion, and again when a plan is applied

### Scan, Plan and Apply
- `--scan` shows sizes, folders and reasons without modifying anything
- `--plan` records every file to remove with its modification time
- `--apply` removes only unchanged files from the plan, re-validates every folder and refuses tampered plans
- A normal run uses the same plan-and-apply engine internally

### Logging
- Every cleanup operation is logged with timestamp
- Includes success/failure status for each action
- Auto-rotates old logs; `update.log` / `health.log` roll over at 1 MB

### Pre-checks
- Validates directories exist before deletion
- Checks Docker daemon availability
- Confirms package managers are installed before running

## Logging

All maintenance scripts write logs to `~/.scripts/logs/`:

| Script | Log file |
|--------|----------|
| `cleaner.sh` | `cleaner_YYYYMMDD_HHMMSS.log` (one file per run) |
| `update.sh` | `update.log` (appended each run) |
| `health.sh` | `health.log` (appended each run) |

View recent logs:
```bash
tail -f ~/.scripts/logs/cleaner_*.log
tail -f ~/.scripts/logs/update.log
tail -f ~/.scripts/logs/health.log
```

List all logs:
```bash
ls -lh ~/.scripts/logs/
```

## Troubleshooting

Start with **`doctor.sh`** (SwiftBar: *Check Setup*): it checks dependencies, the installation, `cleaner.conf`, permissions, the SwiftBar plugin and scheduled runs, and prints a fix for every problem.

### Docker cleanup hangs
The script includes a 5-second timeout for Docker operations. If Docker is unresponsive, it will skip that step.

### Permission denied errors
Make sure scripts are executable:
```bash
chmod +x cleaner.sh health.sh update.sh
```

### Notification not showing
- Ensure `osascript` is available: `command -v osascript`
- Try running manually to see notification: `./cleaner.sh`

### Battery info not showing in health.sh
This is normal on desktop Macs without batteries. The script handles this gracefully.

### smartctl not found
To enable SSD monitoring:
```bash
brew install smartmontools
```

## Dependencies

### Required
- bash 4.0+
- macOS 10.12+
- Standard Unix utilities (find, grep, awk, sed)

### Optional
- `docker` - for Docker cleanup
- `brew` - for Homebrew cleanup
- `npm` / `yarn` - for JavaScript package manager cleanup
- `smartctl` - for SSD health monitoring (install via `brew install smartmontools`)
- `osx-cpu-temp` - for CPU temperature (install via `brew install osx-cpu-temp`)

### Update Script Note
- `update.sh` runs `npm update -g` without `sudo` by default
- To force sudo in non-interactive mode, set `NPM_USE_SUDO=true`

## Performance Notes

- Full cleanup typically takes 10-60 seconds depending on system state (Homebrew cleanup is the slowest part)
- `--scan` / `--plan` take 5-20 seconds: they measure every folder and ask Homebrew/Docker for reclaimable space
- `doctor.sh` takes about a second
- Health check completes in 2-5 seconds
- SwiftBar plugin refreshes every 5 seconds

## Security Considerations

- Scripts validate all paths before deletion
- Config files are user-readable but may contain sensitive paths
- Logs contain information about system state and cleaned items
- Keep logs private or delete after review

## Deploying Changes

If you develop locally and have the toolkit installed at `~/.scripts/fuck-cleanmymac`, use the deploy script to sync:

```bash
./scripts/deploy.sh          # deploy local commits of `main` (no push, works offline)
./scripts/deploy.sh --push   # push to GitHub first, then deploy
```

Only committed changes are deployed. The script then re-runs the installer (`--no-pull --skip-deps --skip-cron`) to refresh the command symlinks and the SwiftBar plugin symlink.

## Project Structure

```text
fuck-cleanmymac/
├── cleaner.sh              # Main cleanup script
├── health.sh               # System health monitor
├── update.sh               # Package & system updater
├── doctor.sh               # Setup diagnostics
├── lib.sh                  # Shared shell helpers (PATH, notify, logging)
├── cleaner.conf            # Configuration template
├── swiftbar/
│   ├── system-monitor.5s.py  # SwiftBar menu bar plugin
│   └── keyboard-lock.py      # Keyboard Cleaning Mode helper (not a plugin)
├── scripts/
│   ├── install.sh          # Auto-installer
│   ├── uninstall.sh        # Uninstaller
│   └── deploy.sh           # Dev → installed copy sync
├── tests/
│   └── run.sh              # End-to-end tests in a throw-away HOME
└── README.md
```

## Contributing

Contributions are welcome! Please:
1. Run `tests/run.sh` (no network, never touches your real HOME)
2. Preserve safety features
3. Update documentation
4. Follow bash best practices

## License

MIT License - feel free to use and modify

## Disclaimer

These scripts perform system maintenance operations. While extensive safety checks are implemented:
- Run `cleaner.sh --scan` (or `--plan`) first to see what will be removed
- Keep system backups
- Test in non-critical environments first
- Use at your own risk

## Support

For issues, questions, or suggestions:
1. Check troubleshooting section above
2. Review logs for detailed error information
3. Run `doctor.sh` and `cleaner.sh --scan`
4. Open an issue with error logs

---

**Made with ❤️ for macOS users who want a cleaner system**
