# Quick Start Guide 🚀

Get **fuck-cleanmymac** up and running in minutes.

## Installation (One Command)

```bash
curl -sL https://raw.githubusercontent.com/iposho/fuck-cleanmymac/main/install.sh | bash
```

That's it! The installer will:
- Clone the repository
- Create necessary directories
- Set up symlinks in `~/.scripts`
- Add scripts to your PATH
- Ask if you want to set up automatic cleanup

## After Installation

You can now use the scripts from anywhere:

```bash
# See what will be cleaned (safe to run)
cleaner.sh --dry-run

# Run actual cleanup
cleaner.sh

# Check system health
health.sh

# Check for updates
update.sh
```

## Common Tasks

### Preview Before Cleaning

Always preview first with `--dry-run`:

```bash
cleaner.sh --dry-run
```

Output shows exactly what will be deleted with `🔍` prefix.

### Run Cleanup

```bash
cleaner.sh
```

Takes 5-30 seconds depending on what needs cleaning.

### Check System Health

```bash
health.sh
```

Shows:
- 💾 Storage & SSD health
- 🔋 Battery status
- 🧠 Memory usage
- ⚡ CPU load
- 🌡️ Temperature
- 🌐 Network info
- 🔒 Security status

### Customize Behavior

Edit the configuration file:

```bash
nano ~/.config/fuck-cleanmymac/cleaner.conf
```

Common settings:
```bash
# Disable Docker cleanup
CLEAN_DOCKER=false

# Keep logs for 180 days instead of 90
LOG_RETENTION_DAYS=180

# Disable notifications
SHOW_NOTIFICATION=false
```

### Set Up Automatic Weekly Cleanup

During installation, you'll be asked about this. To enable it manually:

```bash
# cleaner.sh writes its own log, no >> redirect needed
0 9 * * 1 ~/.scripts/cleaner.sh 2>&1
```

Add to crontab with: `crontab -l | { cat; echo '0 9 * * 1 ~/.scripts/cleaner.sh 2>&1'; } | crontab -`

## Daily Workflow

### Morning Check (2 minutes)

```bash
# Check system health
health.sh

# Check for updates
update.sh
```

### Weekly Cleanup (5 minutes)

```bash
# Preview what will be cleaned
cleaner.sh --dry-run

# Run if preview looks good
cleaner.sh
```

### View Logs

```bash
# See latest cleanup logs
ls -lh ~/.scripts/logs/

# View latest log
tail -f ~/.scripts/logs/cleaner_*.log
```

## CLI Options Quick Reference

```bash
cleaner.sh                      # Run full cleanup
cleaner.sh --dry-run            # Preview (safe)
cleaner.sh --dry-run --verbose  # Detailed preview
cleaner.sh --no-notify          # No notifications
cleaner.sh --help               # Show all options

health.sh                       # System health report
update.sh                       # Check for updates
```

## Uninstall

```bash
./install.sh --uninstall
```

Or manually:

```bash
rm -rf ~/.scripts/fuck-cleanmymac
rm -f ~/.scripts/cleaner.sh ~/.scripts/health.sh ~/.scripts/update.sh
rm -rf ~/.config/fuck-cleanmymac
rm -rf ~/.scripts/logs
```

## Troubleshooting

### "Command not found" after installation

Restart your terminal or run:

```bash
source ~/.zshrc
```

### Installation script fails

Try manual installation:

```bash
git clone https://github.com/iposho/fuck-cleanmymac.git
cd fuck-cleanmymac
chmod +x *.sh
./cleaner.sh --dry-run
```

### Need more features?

Check out the full documentation:
- 📖 **README.md** - Complete feature list
- ⚙️ **Configuration** - All config options
- 🔧 **Troubleshooting** - Common issues

### Want to help?

Found a bug? Have a feature request?

Open an issue: <https://github.com/iposho/fuck-cleanmymac/issues>

## Next Steps

1. ✅ Run `cleaner.sh --dry-run` to see what it does
2. ✅ Read the full README.md for advanced features
3. ✅ Customize `~/.config/fuck-cleanmymac/cleaner.conf`
4. ✅ Set up automatic cleanup (optional)
5. ✅ Install optional tools (smartmontools, osx-cpu-temp)

## Key Features at a Glance

| Feature | Command |
|---------|---------|
| **Safe Preview** | `cleaner.sh --dry-run` |
| **Full Cleanup** | `cleaner.sh` |
| **System Check** | `health.sh` |
| **Updates** | `update.sh` |
| **Configuration** | Edit `~/.config/fuck-cleanmymac/cleaner.conf` |
| **Logs** | View `~/.scripts/logs/` (`update.log`, `health.log`, `cleaner_*.log`) |
| **Help** | `cleaner.sh --help` |

---

**That's it!** You now have a powerful system cleaner and health monitor. 🎉

For more info: `cleaner.sh --help` or read the full [README.md](README.md)
