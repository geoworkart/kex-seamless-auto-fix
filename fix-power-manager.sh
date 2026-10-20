#!/usr/bin/env bash
# Silence the xfce4-power-manager D-Bus/systemd error flood in KeX sessions.
#
# In a chroot/WSL there is no systemd and usually no system D-Bus, so
# xfce4-power-manager spams the VNC log with:
#   GLib-GIO-CRITICAL: g_dbus_proxy_call_sync_internal: assertion 'G_IS_DBUS_PROXY (proxy)' failed
#   Failed to get a systemd proxy: Could not connect: No such file or directory
#   Unable to connect to the system bus
# Power management is meaningless there, so stop it from autostarting.
#
# Usage: ./fix-power-manager.sh [--system-dbus]
#   --system-dbus  also start a system D-Bus daemon (needs sudo), which
#                  silences "system bus" errors from other apps too.

set -euo pipefail

AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
OVERRIDE="$AUTOSTART_DIR/xfce4-power-manager.desktop"

mkdir -p "$AUTOSTART_DIR"
cat > "$OVERRIDE" <<'EOF'
[Desktop Entry]
Type=Application
Name=Power Manager
Exec=xfce4-power-manager
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
echo "[+] Disabled xfce4-power-manager autostart ($OVERRIDE)"

# Remove it from a saved XFCE session so it isn't restored on next login.
SESSION_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sessions"
if compgen -G "$SESSION_DIR/xfce4-session-*" > /dev/null; then
    sed -i '/xfce4-power-manager/d' "$SESSION_DIR"/xfce4-session-* || true
    echo "[+] Removed xfce4-power-manager from saved XFCE sessions"
fi

if pkill -x xfce4-power-manager 2>/dev/null; then
    echo "[+] Stopped running xfce4-power-manager"
fi

if [[ "${1:-}" == "--system-dbus" ]]; then
    if [[ -S /run/dbus/system_bus_socket ]] && pgrep -x dbus-daemon > /dev/null; then
        echo "[=] System D-Bus already running"
    else
        SUDO=""
        [[ $EUID -ne 0 ]] && SUDO="sudo"
        $SUDO mkdir -p /run/dbus
        $SUDO rm -f /run/dbus/pid
        $SUDO dbus-daemon --system --fork
        echo "[+] Started system D-Bus"
    fi
fi

echo "[✓] Done. Restart KeX (kex stop && kex) to get a clean log."
