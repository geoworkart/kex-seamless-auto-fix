#!/usr/bin/env bash
# One-shot fix for NetHunter rootless KeX (Termux) on Android, e.g. Samsung S25.
#
# Fixes:
#   - KeX app "Connection refused" on localhost:5901 because the VNC server
#     quits a few seconds after starting (no usable xstartup for newer
#     TigerVNC, which reads ~/.config/tigervnc instead of ~/.vnc)
#   - the desktop loading and then the whole server dying (Android's limit of
#     32 child processes, plus autostart apps that can't work on Android)
#   - stale X lock files left behind by a crashed/killed server
#   - xfce4-power-manager D-Bus/systemd error spam in the log
#
# Run inside Kali (the kali@localhost prompt):
#   curl -fsSL https://raw.githubusercontent.com/geoworkart/kex-seamless-auto-fix/claude/fix-jo0bfs/fix-kex.sh | bash

set -uo pipefail

DISPLAY_NUM=1
PORT=$((5900 + DISPLAY_NUM))

SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

echo "[1/5] Checking dbus-launch"
if ! command -v dbus-launch >/dev/null; then
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq dbus-x11
fi

echo "[2/5] Writing VNC desktop startup script"
XSTARTUP_BODY='#!/bin/sh
# KeX desktop session (written by fix-kex.sh).
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR=/tmp/runtime-$(id -u)
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
eval "$(dbus-launch --sh-syntax)"
trap '"'"'kill "$DBUS_SESSION_BUS_PID" 2>/dev/null'"'"' EXIT
# Newer TigerVNC shuts the server down as soon as this script exits, so stay
# in the foreground and restart XFCE if it quits, until the server is gone.
while pgrep -x "Xtigervnc|Xvnc" >/dev/null; do
    startxfce4
    sleep 3
done'
for dir in "$HOME/.config/tigervnc" "$HOME/.vnc"; do
    mkdir -p "$dir"
    if [[ -f "$dir/xstartup" && ! -f "$dir/xstartup.bak" ]]; then
        cp "$dir/xstartup" "$dir/xstartup.bak"
    fi
    printf '%s\n' "$XSTARTUP_BODY" > "$dir/xstartup"
    chmod +x "$dir/xstartup"
done
# Older KeX looks for the password in ~/.vnc, newer TigerVNC in ~/.config/tigervnc.
if [[ -s "$HOME/.config/tigervnc/passwd" && ! -s "$HOME/.vnc/passwd" ]]; then
    cp "$HOME/.config/tigervnc/passwd" "$HOME/.vnc/passwd"
elif [[ -s "$HOME/.vnc/passwd" && ! -s "$HOME/.config/tigervnc/passwd" ]]; then
    cp "$HOME/.vnc/passwd" "$HOME/.config/tigervnc/passwd"
fi

echo "[3/5] Disabling autostart apps that can't work on Android"
# Each one needs hardware or a system bus Termux doesn't have, and every extra
# process brings the session closer to Android's 32 child-process limit.
mkdir -p "$HOME/.config/autostart"
for name in xfce4-power-manager blueman nm-applet light-locker xscreensaver \
    polkit-gnome-authentication-agent-1 polkit-mate-authentication-agent-1 xfce-polkit \
    print-applet system-config-printer-applet xiccd geoclue-demo-agent; do
    if [[ $name == xfce4-power-manager || -f /etc/xdg/autostart/$name.desktop ]]; then
        printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$name" \
            > "$HOME/.config/autostart/$name.desktop"
    fi
done
rm -rf "$HOME/.cache/sessions"

echo "[4/5] Stopping old server and clearing stale locks"
kex stop >/dev/null 2>&1
vncserver -kill ":$DISPLAY_NUM" >/dev/null 2>&1
pkill -f "Xtigervnc :$DISPLAY_NUM" 2>/dev/null
# Leftovers from earlier crashed sessions also count toward Android's limit.
pkill -f 'xfce4|xfwm4|xfdesktop|xfsettingsd|xfconfd|Thunar|blueman|nm-applet|polkit|xiccd|light-locker|xscreensaver|at-spi|gvfs|dbus-launch|dbus-daemon.*--session' 2>/dev/null
sleep 1
rm -f "/tmp/.X$DISPLAY_NUM-lock" "/tmp/.X11-unix/X$DISPLAY_NUM"
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix 2>/dev/null

if [[ ! -s "$HOME/.vnc/passwd" && ! -s "$HOME/.config/tigervnc/passwd" ]]; then
    echo "      No KeX password yet, set one now:"
    kex passwd </dev/tty
fi

echo "[5/5] Starting KeX"
kex >/dev/null 2>&1 </dev/null &

port_open() { timeout 2 bash -c "</dev/tcp/127.0.0.1/$PORT" 2>/dev/null; }

for _ in $(seq 1 20); do
    port_open && break
    sleep 1
done
# The server used to start and then die once the desktop loaded, so check it stays up.
sleep 15

if port_open; then
    echo
    echo "[OK] KeX is running on localhost:$PORT."
    echo "     Open the NetHunter KeX app and tap Connect."
    echo "     Keep Termux open in the background (pull down its notification -> Acquire wakelock)."
else
    echo
    echo "[FAIL] KeX did not stay running. Screenshot this log and send it:"
    LOG=$(ls -t "$HOME"/.local/state/tigervnc/*.log "$HOME"/.config/tigervnc/*.log "$HOME"/.vnc/*.log 2>/dev/null | head -1)
    [[ -n "$LOG" ]] && tail -40 "$LOG" | grep -v -e xfce4-power-manager -e '^$'
    echo
    echo "Most likely Android killed it. On the phone:"
    echo "  Settings > Developer options > turn ON 'Disable child process restrictions'"
    echo "  Settings > Apps > Termux > Battery > Unrestricted"
    echo "Then run this script again."
fi
