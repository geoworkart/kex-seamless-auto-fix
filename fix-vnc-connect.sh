#!/usr/bin/env bash
# Fix "Connection refused (port 5901)" in the NetHunter KeX app.
#
# ECONNREFUSED means no VNC server is listening on display :1. Usually KeX
# crashed or was killed by Android and left stale lock files behind, so it
# won't start again. This clears them and restarts KeX.
#
# Run inside Kali (`nethunter` from Termux): ./fix-vnc-connect.sh

set -uo pipefail

DISPLAY_NUM=1

echo "[*] Stopping any existing KeX/VNC server"
kex stop >/dev/null 2>&1
vncserver -kill ":$DISPLAY_NUM" >/dev/null 2>&1
pkill -f "Xtigervnc :$DISPLAY_NUM" 2>/dev/null
pkill -f "Xvnc :$DISPLAY_NUM" 2>/dev/null

echo "[*] Removing stale lock files"
rm -f "/tmp/.X$DISPLAY_NUM-lock" "/tmp/.X11-unix/X$DISPLAY_NUM"
rm -f "$HOME"/.vnc/*":$DISPLAY_NUM.pid"
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

if [[ ! -s "$HOME/.vnc/passwd" ]]; then
    echo "[!] No KeX password set yet, set one now:"
    kex passwd
fi

echo "[*] Starting KeX"
kex &
sleep 5

if vncserver -list 2>/dev/null | grep -q ":$DISPLAY_NUM"; then
    echo "[✓] VNC server is running on :$DISPLAY_NUM (port 590$DISPLAY_NUM)."
    echo "    In the KeX app connect to localhost:590$DISPLAY_NUM with your KeX password."
else
    echo "[✗] KeX did not start. Last log lines:"
    tail -20 "$(ls -t "$HOME"/.vnc/*.log 2>/dev/null | head -1)" 2>/dev/null
fi
