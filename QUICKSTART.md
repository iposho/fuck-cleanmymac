# Quick Start Guide 🚀

Get **fuck-cleanmymac** up and running in minutes.

## Installation (One Command)

```bash
curl -sL https://raw.githubusercontent.com/iposho/fuck-cleanmymac/main/scripts/install.sh | bash
```

That's it! The installer will:
- Clone the repository to `~/.scripts/fuck-cleanmymac`
- Link `cleaner.sh`, `health.sh`, `update.sh`, `doctor.sh` into `~/.scripts` and add it to your PATH
- Create `~/.config/fuck-cleanmymac/cleaner.conf`
- Link the SwiftBar plugin if SwiftBar is installed
- Ask if you want to set up automatic cleanup

Files it would replace are moved to `~/.scripts/backups/`, never deleted.

Then check the setup:

```bash
doctor.sh
```

## After Installation

```bash
cleaner.sh --scan      # What would be cleaned: sizes, paths, reasons (deletes nothing)
cleaner.sh             # Clean now
health.sh              # System health report
update.sh              # Update Homebrew, App Store, npm/pnpm; check macOS updates
doctor.sh              # Diagnose dependencies, permissions, config, SwiftBar, schedule
```

## Common Tasks

### See what will be cleaned

```bash
cleaner.sh --scan
```

Every category shows its size, the folder, how many items and why it is safe to remove. Skipped targets are listed with the reason (disabled in config, Docker not running, temp files too recent…).

### Review a plan, then clean exactly that

```bash
cleaner.sh --plan                                        # save the plan
open -t ~/.cache/fuck-cleanmymac/cleanup-plan.tsv        # review it
cleaner.sh --apply                                       # execute it
```

`--apply` re-checks every path. Files that changed or appeared after the plan was made are kept.

### Run cleanup

```bash
cleaner.sh
```

Takes 10–60 seconds depending on what needs cleaning.

### Check system health

```bash
health.sh
```

Shows storage & SSD health, battery, memory, CPU load, temperature, network and security status.

### Something does not work?

```bash
doctor.sh            # add --online to also check for toolkit updates
```

It checks dependencies, the installation, `cleaner.conf` (typos, invalid values), permissions (Trash, Accessibility for SwiftBar), the SwiftBar plugin, cron jobs and recent failures — and prints how to fix each problem.

### Customize behavior

```bash
nano ~/.config/fuck-cleanmymac/cleaner.conf
```

Common settings:
```bash
CLEAN_DOCKER=false          # Disable Docker cleanup
LOG_RETENTION_DAYS=180      # Keep logs for 180 days instead of 90
SHOW_NOTIFICATION=false     # Disable notifications
TEMP_FILE_AGE_DAYS=7        # Only remove temp files older than a week
```

### Set up automatic weekly cleanup

The installer asks about this. To enable it manually:

```bash
(crontab -l 2>/dev/null; echo '0 9 * * 1 ~/.scripts/cleaner.sh --no-notify') | crontab -
```

cron does not run while the Mac sleeps — pick a time when it is usually awake. To empty the Trash from cron, give `/usr/sbin/cron` Full Disk Access (`doctor.sh` tells you when it is needed).

## Logs

```bash
ls -lh ~/.scripts/logs/                      # cleaner_*.log, update.log, health.log
open "$(ls -t ~/.scripts/logs/cleaner_*.log | head -1)"   # latest cleanup report
```

## CLI Reference

```bash
cleaner.sh                  # Clean now
cleaner.sh --scan           # Preview with sizes (alias: --dry-run, -n)
cleaner.sh --plan [FILE]    # Save a cleanup plan
cleaner.sh --apply [FILE]   # Execute a saved plan
cleaner.sh -v               # Verbose (every folder, skipped targets)
cleaner.sh --no-notify      # No notification
cleaner.sh --help

health.sh                   # System health report
update.sh                   # Updates; exits non-zero if a source could not be checked
doctor.sh [--online]        # Diagnose the setup; exits non-zero on problems
```

## Uninstall

```bash
~/.scripts/fuck-cleanmymac/scripts/uninstall.sh
```

It removes only what the installer created (its symlinks, its cron jobs, the SwiftBar plugin link) and asks before deleting logs and configuration.

## Troubleshooting

### "Command not found" after installation

Open a new terminal or run `source ~/.zshrc`.

### Installation script fails

Run it from a clone to see the full output:

```bash
git clone https://github.com/iposho/fuck-cleanmymac.git
cd fuck-cleanmymac
./scripts/install.sh
```

The scripts need the whole checkout (`lib.sh` next to them) — do not copy single `.sh` files.

### Anything else

`doctor.sh` first, then the [README](README.md). Found a bug? <https://github.com/iposho/fuck-cleanmymac/issues>

## Key Features at a Glance

| Feature | Command |
|---------|---------|
| **Preview with sizes** | `cleaner.sh --scan` |
| **Plan → apply** | `cleaner.sh --plan`, then `cleaner.sh --apply` |
| **Full cleanup** | `cleaner.sh` |
| **System check** | `health.sh` |
| **Updates** | `update.sh` |
| **Setup check** | `doctor.sh` |
| **Configuration** | `~/.config/fuck-cleanmymac/cleaner.conf` |
| **Logs** | `~/.scripts/logs/` |
