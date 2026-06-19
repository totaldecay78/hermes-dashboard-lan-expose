#!/usr/bin/env bash
# =============================================================================
# Hermes Dashboard LAN Expose — complete rollback
# =============================================================================
# Removes every change made by deploy.sh.
# Usage: sudo ./rollback.sh [--port LAN_PORT] [--internal-port INTERNAL_PORT]
# =============================================================================

set -euo pipefail
LAN_PORT="${1:-9119}"
INTERNAL_PORT="${2:-9191}"

if [ "$1" = "--port" ] && [ -n "$2" ]; then
    LAN_PORT="$2"
    shift 2
fi
if [ "${1:-}" = "--internal-port" ] && [ -n "${2:-}" ]; then
    INTERNAL_PORT="$2"
    shift 2
fi

echo "🧹 Hermes Dashboard LAN Expose — Rollback"
echo ""

# 1. Remove nginx config & restart
echo "📝 Removing nginx config..."
sudo rm -f /etc/nginx/conf.d/hermes-dashboard.conf
sudo systemctl restart nginx || true

# 2. Remove iptables rules
echo "📡 Removing iptables DNAT rules..."
sudo iptables -t nat -D PREROUTING -p tcp --dport "$LAN_PORT" -j DNAT --to-destination 127.0.0.1:"$INTERNAL_PORT" 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -p tcp --dport "$LAN_PORT" ! -d 127.0.0.0/8 -j DNAT --to-destination 127.0.0.1:"$INTERNAL_PORT" 2>/dev/null || true

# 3. Remove systemd proxy service
echo "⚙️  Removing systemd proxy service..."
sudo systemctl stop hermes-dashboard-proxy.service 2>/dev/null || true
sudo systemctl disable hermes-dashboard-proxy.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/hermes-dashboard-proxy.service
sudo systemctl daemon-reload

# 4. Remove sysctl config
echo "⚙️  Removing sysctl config..."
sudo rm -f /etc/sysctl.d/99-hermes-route-localnet.conf

# 5. Close firewall port
echo "🔥 Closing firewall port $LAN_PORT/tcp..."
sudo firewall-cmd --remove-port="$LAN_PORT/tcp" --permanent 2>/dev/null || true
sudo firewall-cmd --reload 2>/dev/null || true

echo ""
echo "✅ Rollback complete!"
echo ""
echo "   To revert the Hermes web_server.py patches:"
echo "     cd ~/.hermes/hermes-agent"
echo "     git checkout -- hermes_cli/web_server.py"
echo "     systemctl --user restart hermes-dashboard.service"
echo ""
echo "   To remove the dashboard auto-start:"
echo "     systemctl --user stop hermes-dashboard.service"
echo "     systemctl --user disable hermes-dashboard.service"
echo "     rm -f ~/.config/systemd/user/hermes-dashboard.service"
echo "     systemctl --user daemon-reload"
