#!/usr/bin/env bash
# =============================================================================
# Hermes Dashboard systemd user service — auto-start at boot
# =============================================================================
# Installs a user-level systemd service that starts the Hermes dashboard
# automatically on boot, without requiring a desktop login.
#
# Usage:
#   ./deploy-dashboard-user-service.sh
#
# Requires `loginctl enable-linger $USER` to survive boot without login.
# Run this as your normal user (not sudo).
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

echo "🔧 Hermes Dashboard — systemd User Service Install"
echo ""

# --- Detect paths ---
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
if [ ! -d "$HERMES_HOME" ]; then
    echo "❌ HERMES_HOME ($HERMES_HOME) not found. Set HERMES_HOME or run from the right user."
    exit 1
fi

VENV_PATH=$(find "$HERMES_HOME/hermes-agent" -path "*/venv/bin/python" -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null | xargs dirname 2>/dev/null || true)
if [ -z "$VENV_PATH" ]; then
    echo "⚠️  Could not auto-detect venv path."
    read -r -p "Enter full path to hermes-agent virtualenv: " VENV_PATH
fi

VENV_PATH="${VENV_PATH:-$HERMES_HOME/hermes-agent/venv}"
USERNAME=$(whoami)

echo "   HERMES_HOME : $HERMES_HOME"
echo "   VENV_PATH   : $VENV_PATH"
echo "   USERNAME    : $USERNAME"
echo ""

# --- Enable linger (so user services survive boot) ---
if ! loginctl show-user "$USERNAME" 2>/dev/null | grep -q "Linger=yes"; then
    echo "🔓 Enabling linger for $USERNAME..."
    sudo loginctl enable-linger "$USERNAME"
else
    echo "✅ Linger already enabled"
fi

# --- Deploy service file ---
echo "📝 Installing user service..."
mkdir -p "$HOME/.config/systemd/user"
sed -e "s|HERMES_HOME|$HERMES_HOME|g" \
    -e "s|VENV_PATH|$VENV_PATH|g" \
    -e "s/USERNAME/$USERNAME/g" \
    "$CONFIG_DIR/hermes-dashboard.service" \
    > "$HOME/.config/systemd/user/hermes-dashboard.service"

systemctl --user daemon-reload
systemctl --user enable --now hermes-dashboard.service

echo ""
echo "✅ Dashboard user service installed!"
echo ""
echo "   Check status: systemctl --user status hermes-dashboard.service"
echo "   View logs:    journalctl --user -u hermes-dashboard.service -f"
