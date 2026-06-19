#!/usr/bin/env bash
# =============================================================================
# Hermes Dashboard LAN Expose — verification script
# =============================================================================
# Checks every component is in place and working.
# Usage: ./verify.sh [--port LAN_PORT]
# =============================================================================

set -euo pipefail
LAN_PORT="${1:-9119}"
INTERNAL_PORT="${2:-9191}"

PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo "  ✅ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ❌ $desc"
        FAIL=$((FAIL + 1))
    fi
}

warn() {
    local desc="$1"
    local msg="$2"
    WARN=$((WARN + 1))
    echo "  ⚠️  $desc"
    echo "     $msg"
}

echo "=========================================="
echo " Hermes Dashboard LAN — Verification"
echo "=========================================="
echo ""

# --- System services ---
echo "📡 Services:"
check "nginx running"         "systemctl is-active --quiet nginx"
check "nginx enabled"         "systemctl is-enabled --quiet nginx"
check "proxy service running" "systemctl is-active --quiet hermes-dashboard-proxy.service"
check "proxy service enabled" "systemctl is-enabled --quiet hermes-dashboard-proxy.service"
check "dashboard running"     "systemctl --user is-active --quiet hermes-dashboard.service 2>/dev/null || pgrep -f 'hermes dashboard' >/dev/null"

# --- Network ---
echo ""
echo "🌐 Network:"
check "nginx listening on 0.0.0.0:$INTERNAL_PORT"  "ss -tlnp 'sport = :$INTERNAL_PORT' | grep -q nginx"
check "dashboard on 127.0.0.1:${LAN_PORT:-9119}"     "ss -tlnp 'sport = :${LAN_PORT:-9119}' | grep -q python"

# --- iptables ---
echo ""
echo "📦 iptables DNAT:"
check "DNAT PREROUTING $LAN_PORT → $INTERNAL_PORT" \
    "sudo iptables -t nat -C PREROUTING -p tcp --dport $LAN_PORT -j DNAT --to-destination 127.0.0.1:$INTERNAL_PORT 2>/dev/null"
check "DNAT OUTPUT $LAN_PORT (non-loopback)" \
    "sudo iptables -t nat -C OUTPUT -p tcp --dport $LAN_PORT ! -d 127.0.0.0/8 -j DNAT --to-destination 127.0.0.1:$INTERNAL_PORT 2>/dev/null"

# --- Sysctl ---
echo ""
echo "⚙️  Sysctl:"
check "route_localnet=1" "sysctl net.ipv4.conf.all.route_localnet | grep -q '= 1$'"
check "sysctl config file" "test -f /etc/sysctl.d/99-hermes-route-localnet.conf"

# --- Firewall ---
echo ""
echo "🔥 Firewall:"
check "port $LAN_PORT/tcp open" "sudo firewall-cmd --list-ports --permanent | grep -q '$LAN_PORT/tcp'"

# --- SELinux ---
echo ""
echo "🔒 SELinux:"
if command -v semanage &>/dev/null; then
    check "port $INTERNAL_PORT in http_port_t" "sudo semanage port -l | grep -q 'http_port_t.*$INTERNAL_PORT'"
else
    warn "semanage not found" "SELinux port check skipped (install policycoreutils-python-utils)"
fi
check "httpd_can_network_connect=1" "getsebool httpd_can_network_connect | grep -q ' on$'"

# --- Hermes patches ---
echo ""
echo "🔧 Hermes web_server.py patches:"
WEB_SERVER=$(find ~/.hermes/hermes-agent -name web_server.py -type f -not -path "*/venv/*" 2>/dev/null | head -1)
if [ -n "$WEB_SERVER" ]; then
    check "CORS regex includes RFC1918"  "grep -q '192\\.168' '$WEB_SERVER'"
    check "_is_accepted_host patched"     "grep -q 'RFC1918\|private LAN\|172\\.(1[6-9]' '$WEB_SERVER'"
else
    warn "web_server.py not found" "Skipping patch checks — set HERMES_HOME or check path"
fi

# --- End-to-end ---
echo ""
echo "📡 End-to-end test:"
LOCAL_IP=$(ip -4 addr show | grep -oP 'inet \K192\.168\.\d+\.\d+' | head -1 || echo "127.0.0.1")
if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${LAN_PORT:-9119}/" 2>/dev/null | grep -q '20[0-9]\|30[0-9]'; then
    echo "  ✅ Dashboard accessible locally via 127.0.0.1:${LAN_PORT:-9119}"
    PASS=$((PASS + 1))
else
    echo "  ❌ Dashboard NOT accessible locally via 127.0.0.1:${LAN_PORT:-9119}"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=========================================="
echo " Results:  $PASS passed, $FAIL failed, $WARN warnings"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
