#!/bin/bash
# fuck-cleanmymac Uninstallation Script
# This is a wrapper around install.sh --uninstall

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    echo "❌ Error: install.sh not found at $INSTALL_SCRIPT"
    echo "Please ensure you have the full repository cloned."
    exit 1
fi

# Execute uninstallation
"$INSTALL_SCRIPT" --uninstall "$@"
