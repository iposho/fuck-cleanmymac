# 📊 SwiftBar Plugin

Real-time macOS system monitor for your menu bar. Built with Python, this plugin provides at-a-glance visibility into your system's performance and quick access to maintenance tools.

## Features

- **Menu bar**: CPU usage %, CPU temperature, RAM used/total, free disk space
- **Quick actions**: Cleanup, System Update (packages), Toolkit Update (scripts), Health Check, Keyboard Lock, Disk Utility
- **Processes submenu**: network-connected processes with kill action
- **Logs submenu**: cleanup, update, and health logs with timestamps and direct file links
- **Version label**: toolkit version from `VERSION` file shown at the bottom of the menu

`Toolkit Update` runs `scripts/install.sh --skip-deps --skip-cron --skip-swiftbar` to refresh the installed toolkit files non-interactively.

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

> **Important:** Point SwiftBar's plugin folder to `~/Library/Application Support/SwiftBar/Plugins`, not the repo's `swiftbar/` directory. The repo folder contains `README.md` and other non-plugin files. If you use the repo folder for development, keep `swiftbar/.swiftbarignore` in place so SwiftBar skips documentation and cache files.

### Keyboard Lock

Use **Lock Keyboard** in the menu to disable keyboard input while wiping keys. The Mac stays awake and the mouse keeps working.

- Unlock via **Unlock Keyboard** in the same menu
- Or press **⌘⌃⌥K** on the physical keyboard
- When locked, a 🔒 icon appears in the menu bar line

SwiftBar needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility) for keyboard blocking to work.

---

**Made with ❤️ for SwiftBar users.**
