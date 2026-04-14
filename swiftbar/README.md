# 📊 SwiftBar Plugin

Real-time macOS system monitor for your menu bar. Built with Python, this plugin provides at-a-glance visibility into your system's performance and quick access to maintenance tools.

## Features

- **Menu bar**: CPU usage %, RAM used/total, free disk space
- **Quick actions**: Cleanup, Update, Health Check, Disk Utility
- **Processes submenu**: network-connected processes with kill action
- **Logs submenu**: cleanup, update, and health logs with timestamps and direct file links

## Installation

### Automatic (via installer)
The [scripts/install.sh](../scripts/install.sh) script installs this plugin automatically if SwiftBar is detected on your system.

### Manual Installation
If you prefer to install it manually:

1. **Create Plugins Directory** (if it doesn't exist):
   ```bash
   mkdir -p ~/Library/Application\ Support/SwiftBar/Plugins
   ```
2. **Copy the Plugin**:
   ```bash
   cp swiftbar/system-monitor.5s.py ~/Library/Application\ Support/SwiftBar/Plugins/
   ```
3. **Make it Executable**:
   ```bash
   chmod +x ~/Library/Application\ Support/SwiftBar/Plugins/system-monitor.5s.py
   ```
4. **Refresh SwiftBar**: Click on SwiftBar icon → "Refresh All".

## Configuration

The plugin refreshes every **5 seconds** (as indicated by the `.5s` in the filename). To change the interval, simply rename the file (e.g., to `.10s.py` for 10 seconds).

---

**Made with ❤️ for SwiftBar users.**
