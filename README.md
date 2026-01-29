# fuck cleanmymac

A collection of useful bash and python scripts to keep your macOS clean, healthy, and up-to-date.

## 📦 What's inside?

- `cleaner.sh`: Deep cleaning script (Docker, npm, yarn, brew, Xcode, app caches).
- `health.sh`: Comprehensive system health report (SSD wear, battery cycles, RAM/CPU load, security status).
- `update.sh`: All-in-one updater (Homebrew, App Store via `mas`, npm/pnpm).
- `swiftbar/`: A Python plugin for [SwiftBar](https://swiftbar.app/) to monitor your system directly from the menu bar.

## 🚀 Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/fuck-cleanmymac.git
   cd fuck-cleanmymac
   ```

2. **Make scripts executable:**
   ```bash
   chmod +x *.sh
   ```

3. **Install dependencies:**
   To get the most out of these scripts, you'll need:
   - [Homebrew](https://brew.sh/)
   - `mas` (for App Store updates): `brew install mas`
   - `smartmontools` (for SSD health): `brew install smartmontools`
   - `osx-cpu-temp` (optional, for CPU temperature): `brew install osx-cpu-temp`

4. **SwiftBar Integration:**
   - Install [SwiftBar](https://swiftbar.app/).
   - Open SwiftBar and point it to the `swiftbar/` directory in this project.
   - It will automatically pick up `system-monitor.5s.py` and show stats in your menu bar.

## 🛠 Usage

### Cleaning the system
```bash
./cleaner.sh
```
This script clears caches for various apps (Cursor, Notion, Slack, JetBrains), cleans Docker builders, and empties the Trash.

### Checking system health
```bash
./health.sh
```
Gives you a full report on SSD life, battery condition, memory usage, and security settings (SIP, Firewall, FileVault).

### Updating everything
```bash
./update.sh
```
Updates Homebrew packages, App Store apps, global npm/pnpm packages, and checks for macOS system updates.

## 📝 Customization

The scripts are designed to be portable. 
- `cleaner.sh` logs are stored in `~/.scripts/logs`.
- The SwiftBar plugin dynamically locates the shell scripts based on its folder location.