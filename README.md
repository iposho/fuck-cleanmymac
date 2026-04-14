# fuck-cleanmymac 🧹

![Hero poster](preview.webp)

A comprehensive macOS system cleaner and health monitor toolkit designed to safely free up disk space, monitor system health, and provide automated maintenance.

## Features

### 🧹 **Cleaning (`cleaner.sh`)**
- **Safe path validation** - prevents accidental deletion of system directories
- **Dry-run mode** (`--dry-run`) - preview what will be deleted without actually deleting
- **Docker cleanup** - removes unused containers, images, and volumes
- **Package manager caches** - cleans npm, yarn, Homebrew, pip, gem caches
- **Application caches** - targets Cursor, Notion, Slack, Telegram, Spotify, JetBrains IDEs
- **System maintenance** - cleans user caches, logs, and trash
- **Logging** - timestamped logs with automatic rotation (90 days retention)
- **Notifications** - displays system notifications when cleanup completes
- **Configuration file** - customize cleaning behavior via `cleaner.conf`

### 🏥 **Health Monitor (`health.sh`)**
- **System information** - displays Mac model, CPU, memory, OS version, uptime
- **Storage health** - shows SSD wear level, data written/read (via smartctl)
- **Battery status** - reports cycle count, capacity, health assessment, estimated lifespan
- **Memory usage** - detailed RAM breakdown (wired, active, inactive, free)
- **CPU load** - displays load average and top 5 CPU-consuming processes
- **Temperature monitoring** - CPU temperature (if tools available)
- **Network info** - local and external IP addresses
- **Security status** - Firewall, FileVault, System Integrity Protection status
- **System notifications** - sends summary to Notification Center

### ⚡ **Update Utility (`update.sh`)**
- **Homebrew updates** - upgrades installed packages
- **App Store updates** - updates apps via `mas` (if installed)
- **Node package updates** - updates global `npm` / `pnpm` packages
- **System updates** - checks available macOS updates (`softwareupdate -l`)
- **Safe execution** - error handling and notifications

### 📊 **SwiftBar Plugin**
- Real-time system monitoring in macOS menu bar (CPU, RAM, disk)
- Quick access to cleaning, update, and health check functions
- Collapsible submenus for network processes and operation logs
- Automatic refresh (configurable interval)

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
- ✅ Set up symlinks in `~/.scripts` for easy access
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
cleaner.sh --dry-run            # Preview what will be cleaned
health.sh                       # Check system health
update.sh                       # Check for updates
```

#### Update Existing Installation
To update an existing installation:
```bash
cd ~/.scripts/fuck-cleanmymac
git pull origin main
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
> The uninstaller will ask for confirmation before deleting logs and configuration files.

---

### Manual Installation

If you prefer to set up manually or the auto-installer doesn't work for you:

#### 1. Clone the repository
```bash
git clone https://github.com/iposho/fuck-cleanmymac.git
cd fuck-cleanmymac
chmod +x cleaner.sh health.sh update.sh
```

#### 2. Optional: Add to PATH
```bash
mkdir -p ~/.scripts
cp cleaner.sh health.sh update.sh ~/.scripts/
export PATH="$HOME/.scripts:$PATH"
```

#### 3. SwiftBar Plugin (Optional)
See [swiftbar/README.md](swiftbar/README.md) for manual installation instructions and feature details.

## Usage

### Basic Cleaning
```bash
./cleaner.sh
```

### Dry-run Mode (Preview)
Preview what will be deleted without actually deleting:
```bash
./cleaner.sh --dry-run
```

### With Options
```bash
./cleaner.sh --dry-run --verbose    # Detailed preview
./cleaner.sh --no-notify             # Skip notifications
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
- **CLEAN_APP_CACHES** - Cursor, Notion, Slack, Telegram, Spotify, JetBrains (default: true)
- **CLEAN_PACKAGE_MANAGERS** - npm, yarn, Homebrew, pip, gem (default: true)
- **CLEAN_BROWSER_CACHES** - Chrome cache (default: true)
- **CLEAN_TRASH** - empty Trash (default: true)
- **CLEAN_TEMP_FILES** - `/tmp`, `/var/tmp` (default: true)
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
0 12 * * 5 ~/.scripts/update.sh >> ~/.scripts/logs/update.log 2>&1
```

### Monthly Health Check (1st of month at 12 PM)

```bash
0 12 1 * * ~/.scripts/health.sh >> ~/.scripts/logs/health.log 2>&1
```

> **Tip:** use `crontab -l` to view and `crontab -` with a pipe to edit without vim.

## Safety Features

### Path Validation
- Prevents deletion outside user's home directory (`$HOME`)
- Blocks dangerous system paths: `/`, `/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/private`
- Explicitly allows system temp directories (`/tmp`, `/var/tmp`) for safe cleanup
- Validates all paths before deletion

### Dry-run Mode
- Preview exactly what will be deleted
- No files are actually modified
- Safe to test new configurations

### Logging
- Every cleanup operation is logged with timestamp
- Includes success/failure status for each action
- Auto-rotates old logs

### Pre-checks
- Validates directories exist before deletion
- Checks Docker daemon availability
- Confirms package managers are installed before running

## Logging

Logs are saved to: `~/.scripts/logs/cleaner_YYYYMMDD_HHMMSS.log`

View recent logs:
```bash
tail -f ~/.scripts/logs/cleaner_*.log
```

List all logs:
```bash
ls -lh ~/.scripts/logs/
```

## Troubleshooting

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

- Full cleanup typically takes 5-30 seconds depending on system state
- Dry-run is slightly faster as it doesn't delete files
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
./scripts/deploy.sh          # fetch + reset installed copy to match GitHub
./scripts/deploy.sh --push   # push local changes first, then deploy
```

The script also copies the SwiftBar plugin if it's installed as a regular file (not a symlink).

## Project Structure

```text
fuck-cleanmymac/
├── cleaner.sh              # Main cleanup script
├── health.sh               # System health monitor
├── update.sh               # Package & system updater
├── lib.sh                  # Shared shell helpers (PATH, notify, logging)
├── cleaner.conf            # Configuration template
├── swiftbar/
│   └── system-monitor.5s.py  # SwiftBar menu bar plugin
├── scripts/
│   ├── install.sh          # Auto-installer
│   ├── uninstall.sh        # Uninstaller
│   └── deploy.sh           # Dev → installed copy sync
└── README.md
```

## Contributing

Contributions are welcome! Please:
1. Test changes thoroughly
2. Preserve safety features
3. Update documentation
4. Follow bash best practices

## License

MIT License - feel free to use and modify

## Disclaimer

These scripts perform system maintenance operations. While extensive safety checks are implemented:
- Always run `--dry-run` first to preview changes
- Keep system backups
- Test in non-critical environments first
- Use at your own risk

## Support

For issues, questions, or suggestions:
1. Check troubleshooting section above
2. Review logs for detailed error information
3. Test with `--dry-run` mode
4. Open an issue with error logs

---

**Made with ❤️ for macOS users who want a cleaner system**
