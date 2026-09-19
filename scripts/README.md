# 🛠 Setup & Development Scripts

This directory contains the scripts responsible for the lifecycle and deployment of the **fuck-cleanmymac** toolkit.

## Scripts Overview

### 📥 [install.sh](install.sh)
The main installation script. It automates the setup process including directory creation, symlinking, and optional dependency installation.

**Usage:**
```bash
./scripts/install.sh [OPTIONS]
```

**Options:**
- `--skip-deps`: Skip optional dependency installation (smartmontools, mas, etc.).
- `--skip-cron`: Skip setting up the automatic weekly cleanup job.
- `--skip-swiftbar`: Skip SwiftBar plugin installation.
- `--no-pull`: Do not update the installed repository (used by `deploy.sh`).
- `--uninstall`: Alias for running the uninstallation logic.
- `--help`: Show all available options.

---

### 🧹 [uninstall.sh](uninstall.sh)
A dedicated script to safely remove the toolkit from your system.

**Usage:**
```bash
./scripts/uninstall.sh
```
It will remove symlinks, cron jobs, and SwiftBar plugins. It asks for confirmation before deleting persistent data like logs and configuration.

---

### 📤 [deploy.sh](deploy.sh)
A development utility to deploy the local `main` branch (committed changes only, no network needed) to the installed copy in `~/.scripts/fuck-cleanmymac`, then refresh symlinks and the SwiftBar plugin link.

**Usage:**
```bash
./scripts/deploy.sh [--push]
```
- `--push`: Pushes changes to the remote GitHub repository before deploying locally.

The installer reads prompts from the terminal, so `curl … | bash` works; without a terminal every question is answered "no". Set `SWIFTBAR_PLUGIN_DIR` to install the plugin into a different folder.

## Troubleshooting Installation

1. **Permission Denied**: Ensure scripts are executable:
   ```bash
   chmod +x scripts/*.sh
   ```
2. **Path Issues**: If `cleaner.sh` is not found, ensure `~/.scripts` is in your `$PATH`. The installer attempts to add it to your `.zshrc` or `.bashrc` automatically.
3. **SwiftBar Plugin**: If the plugin doesn't appear, try refreshing SwiftBar or checking the Plugin directory manually: `~/Library/Application Support/SwiftBar/Plugins`.
