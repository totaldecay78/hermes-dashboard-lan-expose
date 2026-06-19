#!/usr/bin/env bash
# =============================================================================
# Hermes Dashboard LAN Expose — OS auto-detection bootstrap
# =============================================================================
# Detects the current OS and delegates to the correct platform script.
# Hermes agents: run this at the repo root, it figures out the rest.
#
# Usage:
#   sudo ./deploy.sh
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

OS="$(uname -s 2>/dev/null || echo 'Unknown')"

case "$OS" in
    Linux)
        echo "🔧 Detected Linux → delegating to linux/deploy.sh"
        exec "$SCRIPT_DIR/linux/deploy.sh" "$@"
        ;;
    *)
        echo "❌ Unsupported OS: $OS"
        echo "   Linux:   run linux/deploy.sh"
        echo "   Windows: run windows/deploy.ps1 (as Administrator in PowerShell)"
        exit 1
        ;;
esac
