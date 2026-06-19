#!/usr/bin/env bash
# =============================================================================
# Hermes Dashboard LAN Expose — automated deploy script
# =============================================================================
# Usage: ./deploy.sh [--port LAN_PORT] [--internal-port INTERNAL_PORT]
#
# Defaults:
#   LAN_PORT        = 9119  (what LAN clients connect to)
#   INTERNAL_PORT   = 9191  (what nginx listens on internally)
#   DASHBOARD_PORT  = 9119  (what Hermes dashboard binds to on 127.0.0.1)
#   INTERNAL_IP     = 127.0.0.1
#
# Run with defaults:
#   sudo ./deploy.sh
#
# Custom ports (if Hermes dashboard is on 9090):
#   sudo ./deploy.sh --port 9090 --internal-port 9191
#
# Requires root for system-wide changes (nginx, iptables, SELinux, firewall).
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

# --- Parse options ---
LAN_PORT="${1:-9119}"
INTERNAL_PORT="${2:-9191}"
DASHBOARD_PORT="${LAN_PORT}"   # Hermes dashboard bound to 127.0.0.1
INTERNAL_IP="127.0.0.1"

if [ "$1" = "--port" ] && [ -n "$2" ]; then
    LAN_PORT="$2"
    DASHBOARD_PORT="$LAN_PORT"
    shift 2
fi
if [ "${1:-}" = "--internal-port" ] && [ -n "${2:-}" ]; then
    INTERNAL_PORT="$2"
    shift 2
fi

echo "🔧 Hermes Dashboard LAN Expose"
echo "   LAN access port : $LAN_PORT"
echo "   nginx proxy port: $INTERNAL_PORT"
echo "   Dashboard       : 127.0.0.1:$DASHBOARD_PORT"
echo ""

# --- 1. Install nginx ---
if ! command -v nginx &>/dev/null; then
    echo "📦 Installing nginx..."
    sudo dnf install -y nginx
else
    echo "✅ nginx already installed"
fi

# --- 2. Deploy nginx config ---
echo "📝 Deploying nginx config..."
sed -e "s/INTERNAL_PORT/$INTERNAL_PORT/g" \
    -e "s/DASHBOARD_PORT/$DASHBOARD_PORT/g" \
    "$CONFIG_DIR/nginx-hermes-dashboard.conf" \
    | sudo tee /etc/nginx/conf.d/hermes-dashboard.conf >/dev/null

# --- 3. SELinux ---
echo "🔒 Configuring SELinux..."
sudo semanage port -a -t http_port_t -p tcp "$INTERNAL_PORT" 2>/dev/null || \
    sudo semanage port -m -t http_port_t -p tcp "$INTERNAL_PORT"
sudo setsebool -P httpd_can_network_connect 1

# --- 4. Enable & start nginx ---
echo "🚀 Starting nginx..."
sudo systemctl enable --now nginx

# --- 5. Firewall ---
echo "🔥 Opening firewall port $LAN_PORT/tcp..."
sudo firewall-cmd --add-port="$LAN_PORT/tcp" --permanent
sudo firewall-cmd --reload

# --- 6. Sysctl route_localnet ---
echo "⚙️  Enabling route_localnet..."
sudo cp "$CONFIG_DIR/sysctl-hermes-route-localnet.conf" /etc/sysctl.d/99-hermes-route-localnet.conf
sudo sysctl -w net.ipv4.conf.all.route_localnet=1

# --- 7. iptables DNAT ---
echo "📡 Adding iptables DNAT rules ($LAN_PORT → $INTERNAL_IP:$INTERNAL_PORT)..."
sudo iptables -t nat -C PREROUTING -p tcp --dport "$LAN_PORT" -j DNAT --to-destination "$INTERNAL_IP:$INTERNAL_PORT" 2>/dev/null || \
    sudo iptables -t nat -A PREROUTING -p tcp --dport "$LAN_PORT" -j DNAT --to-destination "$INTERNAL_IP:$INTERNAL_PORT"
sudo iptables -t nat -C OUTPUT -p tcp --dport "$LAN_PORT" ! -d 127.0.0.0/8 -j DNAT --to-destination "$INTERNAL_IP:$INTERNAL_PORT" 2>/dev/null || \
    sudo iptables -t nat -A OUTPUT -p tcp --dport "$LAN_PORT" ! -d 127.0.0.0/8 -j DNAT --to-destination "$INTERNAL_IP:$INTERNAL_PORT"

# --- 8. systemd proxy service (persist DNAT across reboots) ---
echo "⚙️  Installing systemd proxy service..."
sed -e "s/LAN_PORT/$LAN_PORT/g" \
    -e "s/INTERNAL_IP/$INTERNAL_IP/g" \
    -e "s/INTERNAL_PORT/$INTERNAL_PORT/g" \
    "$CONFIG_DIR/hermes-dashboard-proxy.service" \
    | sudo tee /etc/systemd/system/hermes-dashboard-proxy.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-dashboard-proxy.service

# --- 9. Patch Hermes web_server.py ---
read -r -p "❓ Patch Hermes web_server.py for LAN origin support? [Y/n] " PATCH_WEB
PATCH_WEB="${PATCH_WEB:-Y}"
if [[ "$PATCH_WEB" =~ ^[Yy] ]]; then
    WEB_SERVER_PATH=$(find ~/.hermes/hermes-agent -name web_server.py -type f -not -path "*/venv/*" 2>/dev/null | head -1)
    if [ -z "$WEB_SERVER_PATH" ]; then
        echo "⚠️  Could not find web_server.py. Apply patch manually:"
        echo "   git apply $SCRIPT_DIR/patches/allow-lan-origins.patch"
        echo "   inside your hermes-agent directory"
    else
        cd "$(dirname "$WEB_SERVER_PATH")/.."
        if git diff --quiet -- hermes_cli/web_server.py 2>/dev/null; then
            git apply "$SCRIPT_DIR/patches/allow-lan-origins.patch" 2>/dev/null || {
                echo "⚠️  Patch failed (may already be applied). Checking..."
                grep -q "192\.168" hermes_cli/web_server.py && echo "✅ Patch already applied" || echo "❌ Manual review needed"
            }
        else
            echo "⚠️  web_server.py has uncommitted changes — skipping auto-patch."
            echo "   Apply $SCRIPT_DIR/patches/allow-lan-origins.patch manually."
        fi
    fi
fi

echo ""
echo "✅ Deploy complete!"
echo ""
echo "   Next steps:"
echo "     1. Restart Hermes dashboard to pick up the web_server.py patch:"
echo "        systemctl --user restart hermes-dashboard.service"
echo "     2. Verify from a LAN device:"
echo "        curl -s http://YOUR_LAN_IP:$LAN_PORT/api/status"
echo "     3. Optionally install the dashboard auto-start service:"
echo "        ./deploy-dashboard-user-service.sh"
