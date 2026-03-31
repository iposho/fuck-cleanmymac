# Changelog

## Version 2.1.0 - Configuration & Dry-Run Release

### Major Features Added

#### 1. Configuration File Support (`cleaner.conf`)
- **New file**: `cleaner.conf` in project root with comprehensive configuration options
- **Config locations** (checked in order):
  - `~/.config/fuck-cleanmymac/cleaner.conf`
  - `~/.scripts/cleaner.conf`
  - `./cleaner.conf` (project directory)
- **Configurable options**:
  - Logging: `LOG_DIR`, `LOG_RETENTION_DAYS`, `VERBOSE_LOGGING`
  - Cleaning targets: `CLEAN_DOCKER`, `CLEAN_HOMEBREW`, `CLEAN_NPM`, `CLEAN_YARN`, `CLEAN_PIP`, etc.
  - Application-specific: `CLEAN_CURSOR`, `CLEAN_NOTION`, `CLEAN_SLACK`, `CLEAN_TELEGRAM`, `CLEAN_JETBRAINS`
  - System maintenance: `CLEAN_SYSTEM_CACHES`, `CLEAN_SYSTEM_LOGS`, `CLEAN_TRASH`, `CLEAN_TEMP_FILES`
  - Features: `SHOW_NOTIFICATION`, `DRY_RUN`

#### 2. Dry-Run Mode (`--dry-run` flag)
- **Safe preview**: See exactly what will be deleted without actually deleting files
- **Visual indicator**: All dry-run operations prefixed with `🔍 [DRY-RUN]`
- **Item counting**: Shows approximate count of items that would be cleaned
- **Usage**: `./cleaner.sh --dry-run` or `./cleaner.sh --dry-run --verbose`

#### 3. Enhanced Command-Line Interface
New command-line flags for `cleaner.sh`:
- `--dry-run` - Preview mode without deletions
- `--verbose` - Enable detailed logging output
- `--no-notify` - Skip notifications after cleaning
- `--help` - Show usage information

### Code Improvements

#### cleaner.sh
- **Refactored configuration loading**: `load_config()` function searches multiple config file locations
- **Improved argument parsing**: `parse_arguments()` function handles all command-line flags
- **Enhanced help system**: `show_help()` displays usage examples
- **Better logging**: Added `debug_log()` for verbose mode output
- **Conditional cleaning**: All cleanup sections now check config before executing
- **Dry-run support**: All deletion operations check `DRY_RUN` flag
- **Improved separators**: Changed from `--` to `═` for better readability
- **Better error messages**: More descriptive logging for each operation

#### health.sh
- **Complete English translation**: All messages, headers, and comments now in English
- **Improved formatting**: Better structured output sections
- **Fixed variable initialization**: Pre-initializes optional metrics to prevent `set -u` errors
- **Safer notifications**: Properly escapes special characters for AppleScript
- **Better battery detection**: Uses `pmset -g batt` instead of `system_profiler`
- **Enhanced SSD info**: Improved smartctl data extraction
- **Cleaner output**: Better visual hierarchy with consistent emoji usage

#### update.sh
- **Complete English translation**: All messages and comments now in English
- **Improved error handling**: Better checks for each package manager
- **Enhanced reporting**: More detailed update information
- **Safer notifications**: Proper string escaping for AppleScript
- **Better formatting**: Consistent with other scripts using `═` separators
- **Added pnpm support**: Now checks pnpm global packages
- **Improved macOS update detection**: Better parsing of system updates

#### swiftbar/system-monitor.5s.py
- **Complete English translation**: All comments and messages now in English
- **Improved docstring**: Added Python docstring at top of file
- **Better error handling**: More robust subprocess calls
- **Fixed process parsing**: Better handling of network process list
- **Cleaner output**: English menu labels
- **Code improvements**: Better variable naming and organization
- **Fixed formatting**: Proper GB notation instead of Russian abbreviations

#### README.md
- **Comprehensive rewrite**: Now entirely in English
- **Better structure**: Clear sections for features, installation, usage, configuration
- **Detailed examples**: Command-line usage with output examples
- **Automation guide**: Complete cron and LaunchAgent setup instructions
- **Safety documentation**: Clear safety features and warnings
- **Troubleshooting section**: Common issues and solutions
- **Dependencies listed**: Both required and optional dependencies clearly marked
- **Updated features list**: Reflects all new functionality from this release

### Technical Details

#### Path Validation Enhancements
- Maintains existing safety checks (system path blocking)
- Works with configuration file to allow custom paths
- Better logging of path validation failures

#### Logging Improvements
- Maintains timestamped log files in `~/.scripts/logs/`
- Log rotation still removes files older than `LOG_RETENTION_DAYS`
- Dry-run operations still logged for audit trail
- All operations logged with success/failure indicators (✅ / ❌)

#### Configuration File Format
- Simple key=value format (bash-compatible)
- Comments supported with `#` prefix
- Environment variables like `$HOME` supported
- Easy to customize per user or system

### Documentation Updates

- **README.md**: Complete rewrite with English content
- **cleaner.conf**: Comprehensive configuration file with all options documented
- **Inline comments**: All scripts updated with English comments
- **Help text**: Clear `--help` output in `cleaner.sh`

### Breaking Changes

None - all changes are backward compatible. Scripts work the same without config file, using sensible defaults.

### Migration Guide

For existing users:
1. No action required - scripts work with defaults
2. To customize, create `~/.config/fuck-cleanmymac/cleaner.conf` and modify settings
3. To see what would be cleaned before running, use `./cleaner.sh --dry-run`

### Files Modified

- `cleaner.sh` - Major refactoring with config support and dry-run mode
- `health.sh` - Complete English translation and improvements
- `update.sh` - English translation and enhancements
- `README.md` - Comprehensive rewrite
- `swiftbar/system-monitor.5s.py` - English translation

### Files Added

- `cleaner.conf` - Configuration file template

### Known Limitations

- SwiftBar plugin path detection assumes standard plugin directory structure
- Some package managers (pnpm, yarn) may not report outdated packages if not installed
- macOS system updates require `sudo` for automatic installation
- Temperature monitoring requires additional tools (osx-cpu-temp or istats)
- SMART monitoring requires smartmontools installation

### Future Improvements

- Add interactive mode with confirmations
- Support for custom application cache cleanup
- Parallel execution of independent cleanup tasks
- Backup functionality before major cleanups
- Statistics dashboard
- Integration with Time Machine

### Testing Recommendations

1. Test with `--dry-run` first: `./cleaner.sh --dry-run`
2. Review configuration file before first real run
3. Check logs in `~/.scripts/logs/` after running
4. Test health check: `./health.sh`
5. Test update check: `./update.sh`
6. Verify notifications appear

### Support & Issues

- Review generated logs for detailed operation information
- Use `--verbose` flag for additional debugging information
- Check README.md troubleshooting section
- Ensure all scripts are executable: `chmod +x *.sh`

---

**Release Date**: 2024
**Compatibility**: macOS 10.12+
**Bash Version**: 4.0+