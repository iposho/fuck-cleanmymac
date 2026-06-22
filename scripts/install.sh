#!/bin/bash
set -euo pipefail

# ============================================================================
# fuck-cleanmymac Auto-Installation Script
# ============================================================================
# This script automates the installation of fuck-cleanmymac on macOS
#
# Features:
# - Clones or updates the repository
# - Creates necessary directories
# - Sets up configuration
# - Creates symlinks for easy access
# - Sets up cron jobs (optional)
# - Installs SwiftBar plugin (optional)
# - Installs optional dependencies
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/iposho/fuck-cleanmymac/main/scripts/install.sh | bash
#   # OR
#   ./scripts/install.sh [OPTIONS]
#
# Options:
#   --skip-deps     Skip dependency installation
#   --skip-cron     Skip cron job setup
#   --skip-swiftbar Skip SwiftBar plugin installation
#   --uninstall     Remove installation
#   --help          Show this help message
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/iposho/fuck-cleanmymac.git"
INSTALL_DIR="$HOME/.scripts/fuck-cleanmymac"
CONFIG_DIR="$HOME/.config/fuck-cleanmymac"
LOG_DIR="$HOME/.scripts/logs"
BIN_DIR="$HOME/.scripts"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo -e "  ${BLUE}$1${NC}"
    echo "════════════════════════════════════════════════════════════════"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

# Check if running on macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "This script is designed for macOS only"
        exit 1
    fi
    print_success "Running on macOS $(sw_vers -productVersion)"
}

# Check for required commands
check_dependencies() {
    print_header "Checking Dependencies"

    local missing_deps=()

    # Check for required commands
    for cmd in git bash curl; do
        if command -v "$cmd" &> /dev/null; then
            print_success "$cmd installed"
        else
            missing_deps+=("$cmd")
            print_error "$cmd not found"
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "Missing dependencies: ${missing_deps[*]}"
        print_info "Installing missing dependencies with Homebrew..."
        if command -v brew &> /dev/null; then
            brew install "${missing_deps[@]}" 2>/dev/null || true
        else
            print_error "Homebrew not found. Please install Homebrew first:"
            print_info "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
    fi
}

# ============================================================================
# Installation Functions
# ============================================================================

# Create necessary directories
create_directories() {
    print_header "Creating Directories"

    mkdir -p "$LOG_DIR"
    print_success "Created log directory: $LOG_DIR"

    mkdir -p "$CONFIG_DIR"
    print_success "Created config directory: $CONFIG_DIR"

    mkdir -p "$BIN_DIR"
    print_success "Created bin directory: $BIN_DIR"
}

# Clone or update repository
install_repository() {
    print_header "Installing Repository"

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        print_info "Repository already exists. Updating..."
        cd "$INSTALL_DIR"
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true
        print_success "Repository updated"
    else
        print_info "Cloning repository to $INSTALL_DIR..."
        git clone "$REPO_URL" "$INSTALL_DIR"
        print_success "Repository cloned"
    fi

    # Make scripts executable
    chmod +x "$INSTALL_DIR"/*.sh
    print_success "Scripts made executable"
}

# Create symlinks
create_symlinks() {
    print_header "Creating Symlinks"

    # Create symlinks in BIN_DIR
    for script in cleaner health update; do
        local src="$INSTALL_DIR/${script}.sh"
        local dst="$BIN_DIR/${script}.sh"

        if [[ -f "$src" ]]; then
            # Remove existing symlink if it exists
            rm -f "$dst"
            ln -s "$src" "$dst"
            print_success "Created symlink: $dst"
        fi
    done

    # Add BIN_DIR to PATH in shell config
    add_to_path
}

# Add BIN_DIR to PATH
add_to_path() {
    print_info "Adding scripts to PATH..."

    local shell_configs=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile")
    local path_line='export PATH="$HOME/.scripts:$PATH"'

    for config in "${shell_configs[@]}"; do
        if [[ -f "$config" ]]; then
            if grep -qF "$BIN_DIR" "$config" 2>/dev/null || grep -qF '$HOME/.scripts' "$config" 2>/dev/null; then
                print_info "PATH already configured in $config"
            else
                echo "" >> "$config"
                echo "# fuck-cleanmymac" >> "$config"
                echo "$path_line" >> "$config"
                print_success "Added to $config"
            fi
        fi
    done
}

# Copy configuration file
setup_config() {
    print_header "Setting Up Configuration"

    local config_src="$INSTALL_DIR/cleaner.conf"
    local config_dst="$CONFIG_DIR/cleaner.conf"

    if [[ -f "$config_src" ]]; then
        if [[ ! -f "$config_dst" ]]; then
            cp "$config_src" "$config_dst"
            print_success "Configuration file created at $config_dst"
            print_info "You can customize it to fit your needs"
        else
            print_info "Configuration already exists at $config_dst"
        fi
    fi
}

# Install optional dependencies
install_optional_deps() {
    print_header "Installing Optional Dependencies"

    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew not found. Skipping optional dependencies."
        return
    fi

    print_info "Checking for optional tools..."

    # smartmontools for SSD health monitoring
    if ! command -v smartctl &> /dev/null; then
        print_info "Installing smartmontools (SSD monitoring)..."
        brew install smartmontools 2>/dev/null || print_warning "Failed to install smartmontools"
    else
        print_success "smartmontools already installed"
    fi

    # osx-cpu-temp for temperature monitoring
    if ! command -v osx-cpu-temp &> /dev/null; then
        print_info "Installing osx-cpu-temp (temperature monitoring)..."
        brew install osx-cpu-temp 2>/dev/null || print_warning "Failed to install osx-cpu-temp"
    else
        print_success "osx-cpu-temp already installed"
    fi

    # mas for App Store updates
    if ! command -v mas &> /dev/null; then
        print_info "Installing mas (App Store CLI)..."
        brew install mas 2>/dev/null || print_warning "Failed to install mas"
    else
        print_success "mas already installed"
    fi

    print_success "Optional dependencies checked"
}

# Install SwiftBar plugin
install_swiftbar() {
    print_header "Setting Up SwiftBar Plugin"

    local swiftbar_dir="$HOME/Library/Application Support/SwiftBar/Plugins"
    local plugin_src="$INSTALL_DIR/swiftbar/system-monitor.5s.py"
    local plugin_dst="$swiftbar_dir/system-monitor.5s.py"

    if command -v swiftbar &> /dev/null || [[ -d "/Applications/SwiftBar.app" ]] || [[ -d "$HOME/Applications/SwiftBar.app" ]]; then
        mkdir -p "$swiftbar_dir"

        if [[ -f "$plugin_src" ]]; then
            if [[ -d "$plugin_dst" ]]; then
                cp "$plugin_src" "$plugin_dst/$(basename "$plugin_dst")"
                chmod +x "$plugin_dst/$(basename "$plugin_dst")"
            else
                cp "$plugin_src" "$plugin_dst"
                chmod +x "$plugin_dst"
            fi
            if [[ -f "$INSTALL_DIR/swiftbar/keyboard-lock.py" ]]; then
                cp "$INSTALL_DIR/swiftbar/keyboard-lock.py" "$swiftbar_dir/keyboard-lock.py"
                chmod +x "$swiftbar_dir/keyboard-lock.py"
            fi
            rm -rf "$swiftbar_dir/README.md"
            defaults write com.ameba.SwiftBar PluginDirectory "$swiftbar_dir" 2>/dev/null || true
            print_success "SwiftBar plugin installed"
            print_info "Plugin directory set to: $swiftbar_dir"
            print_info "Restart SwiftBar to see the plugin"
        fi
    else
        print_warning "SwiftBar not found. Skipping plugin installation."
        print_info "Install SwiftBar from: https://swiftbar.app"
    fi
}

# Setup cron job
setup_cron() {
    print_header "Setting Up Cron Job (Optional)"

    echo ""
    read -p "  Do you want to set up automatic weekly cleanup? (y/N): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local cron_entry="0 2 * * 0 $BIN_DIR/cleaner.sh --no-notify >> $LOG_DIR/cron.log 2>&1"

        # Check if cron entry already exists
        if crontab -l 2>/dev/null | grep -q "cleaner.sh"; then
            print_warning "Cron job already exists"
        else
            (crontab -l 2>/dev/null || true; echo "$cron_entry") | crontab -
            print_success "Cron job created (weekly at 2:00 AM)"
            print_info "Edit with: crontab -e"
        fi
    else
        print_info "Cron job skipped"
    fi
}

# ============================================================================
# Uninstallation
# ============================================================================

uninstall() {
    print_header "Uninstalling fuck-cleanmymac"

    # Remove symlinks
    for script in cleaner health update; do
        rm -f "$BIN_DIR/${script}.sh"
        print_info "Removed symlink: $BIN_DIR/${script}.sh"
    done

    # Remove cron jobs
    crontab -l 2>/dev/null | grep -v "cleaner.sh" | crontab - 2>/dev/null || true
    print_info "Removed cron jobs"

    # Remove SwiftBar plugin
    rm -f "$HOME/Library/Application Support/SwiftBar/Plugins/system-monitor.5s.py"
    print_info "Removed SwiftBar plugin"

    # Ask about removing data
    echo ""
    read -p "  Do you want to remove logs and configuration? (y/N): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$LOG_DIR" "$CONFIG_DIR" "$INSTALL_DIR"
        print_success "Removed all data"
    else
        print_info "Kept logs and configuration"
    fi

    print_success "Uninstallation complete!"
}

# ============================================================================
# Main
# ============================================================================

show_help() {
    cat << EOF
fuck-cleanmymac Auto-Installation Script
=========================================

Usage: $0 [OPTIONS]

Options:
  --skip-deps      Skip dependency installation
  --skip-cron      Skip cron job setup
  --skip-swiftbar  Skip SwiftBar plugin installation
  --uninstall      Remove installation
  --help           Show this help message

Examples:
  # Interactive installation (recommended)
  $0

  # Non-interactive with defaults
  $0 --skip-deps --skip-cron --skip-swiftbar

  # Uninstall
  $0 --uninstall

Quick Install:
  curl -sL https://raw.githubusercontent.com/iposho/fuck-cleanmymac/main/scripts/install.sh | bash

EOF
}

main() {
    # Parse arguments
    local skip_deps=false
    local skip_cron=false
    local skip_swiftbar=false
    local do_uninstall=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-deps)
                skip_deps=true
                shift
                ;;
            --skip-cron)
                skip_cron=true
                shift
                ;;
            --skip-swiftbar)
                skip_swiftbar=true
                shift
                ;;
            --uninstall)
                do_uninstall=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Handle uninstall
    if [[ "$do_uninstall" == true ]]; then
        uninstall
        exit 0
    fi

    # Print welcome
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           fuck-cleanmymac Installation Script               ║"
    echo "║                  Version 2.1.0                               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # Run installation steps
    check_macos
    check_dependencies
    create_directories
    install_repository
    create_symlinks
    setup_config

    if [[ "$skip_deps" == false ]]; then
        install_optional_deps
    fi

    if [[ "$skip_swiftbar" == false ]]; then
        install_swiftbar
    fi

    if [[ "$skip_cron" == false ]]; then
        setup_cron
    fi

    # Print summary
    print_header "Installation Complete!"

    echo ""
    echo "  Usage:"
    echo "    ~/.scripts/cleaner.sh        # Run cleanup"
    echo "    ~/.scripts/cleaner.sh --dry-run  # Preview"
    echo "    ~/.scripts/health.sh         # System health"
    echo "    ~/.scripts/update.sh         # Check updates"
    echo ""
    echo "  Or add to PATH and run from anywhere:"
    echo "    cleaner.sh --help"
    echo "    health.sh"
    echo "    update.sh"
    echo ""
    echo "  Configuration:"
    echo "    $CONFIG_DIR/cleaner.conf"
    echo ""
    echo "  Logs:"
    echo "    $LOG_DIR/"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

# Run main function
main "$@"
