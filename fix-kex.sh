#!/usr/bin/env bash
# One-shot fix for NetHunter rootless KeX (Termux) on Android, e.g. Samsung S25.
#
# Fixes:
#   - KeX app "Connection refused" on localhost:5901 because the VNC server
#     quits a few seconds after starting (no usable xstartup for newer
#     TigerVNC, which reads ~/.config/tigervnc instead of ~/.vnc)
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
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR=/tmp/runtime-$(id -u)
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
exec dbus-launch --exit-with-session startxfce4'
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

echo "[3/5] Disabling xfce4-power-manager (no systemd on Android)"
mkdir -p "$HOME/.config/autostart"
printf '[Desktop Entry]\nType=Application\nName=Power Manager\nExec=xfce4-power-manager\nHidden=true\n' \
    > "$HOME/.config/autostart/xfce4-power-manager.desktop"

echo "[4/5] Stopping old server and clearing stale locks"
kex stop >/dev/null 2>&1
vncserver -kill ":$DISPLAY_NUM" >/dev/null 2>&1
pkill -f "Xtigervnc :$DISPLAY_NUM" 2>/dev/null
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
# The server used to start and then die a few seconds later, so check it stays up.
sleep 8

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
fi
