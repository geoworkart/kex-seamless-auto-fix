#!/usr/bin/env bash
# One-shot fix for NetHunter rootless KeX (Termux) on Android, e.g. Samsung S25.
#
# Fixes:
#   - KeX app "Connection refused" on localhost:5901 because the VNC server
#     quits a few seconds after starting (no usable xstartup for newer
#     TigerVNC, which reads ~/.config/tigervnc instead of ~/.vnc)
#   - the desktop loading and then the whole server dying (Android's limit of
#     32 child processes, plus autostart apps that can't work on Android)
#   - no wallpaper/icon images and xfce4-panel crashing, because GTK's glycin
#     image loader sandboxes itself with bwrap, which can't run on Android
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

echo "fix-kex.sh v4"
echo "[1/6] Checking dbus-launch"
if ! command -v dbus-launch >/dev/null; then
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq dbus-x11
fi

echo "[2/6] Writing VNC desktop startup script"
XSTARTUP_BODY='#!/bin/sh
# KeX desktop session (written by fix-kex.sh).
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR=/tmp/runtime-$(id -u)
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
# Picks up the bwrap stand-in for GTK image loading (see fix-kex.sh).
export PATH="$HOME/.local/bin:$PATH"
# Newer TigerVNC shuts the server down as soon as this script exits, so stay
# in the foreground and restart XFCE (with a fresh session bus) if it quits.
while pgrep -x "Xtigervnc|Xvnc" >/dev/null; do
    echo "fix-kex: starting XFCE $(date +%T)"
    if command -v dbus-run-session >/dev/null; then
        dbus-run-session -- startxfce4
    else
        eval "$(dbus-launch --sh-syntax)"
        startxfce4
        kill "$DBUS_SESSION_BUS_PID" 2>/dev/null
        unset DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
    fi
    echo "fix-kex: XFCE exited with code $? $(date +%T)"
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

echo "[3/6] Fixing GTK image loading (wallpaper, icons, panel)"
# Newer GTK loads images through glycin, which sandboxes each loader with
# bubblewrap. bwrap needs user namespaces, which Android apps don't get, so
# every image fails to load and xfce4-panel aborts. Install a stand-in bwrap
# in ~/.local/bin that skips the sandbox options and runs the loader directly.
if [[ -d /usr/libexec/glycin-loaders ]] && ! /usr/bin/bwrap --ro-bind / / true 2>/dev/null; then
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/bwrap" <<'SHIM'
#!/bin/bash
# bwrap stand-in for NetHunter rootless / proot (written by fix-kex.sh).
# Real bubblewrap can't run without user namespaces, so drop the sandbox
# options and run the command directly.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --) shift; break ;;
        --version) echo "bubblewrap 0.11.0 (fix-kex stand-in)"; exit 0 ;;
        --overlay)
            shift 4 2>/dev/null || exit 1 ;;
        --setenv|--bind|--bind-try|--dev-bind|--dev-bind-try|--ro-bind|--ro-bind-try|\
        --bind-fd|--ro-bind-fd|--file|--bind-data|--ro-bind-data|--symlink|--chmod)
            shift 3 2>/dev/null || exit 1 ;;
        --args|--argv0|--userns|--userns2|--pidns|--uid|--gid|--hostname|--chdir|--unsetenv|\
        --lock-file|--sync-fd|--remount-ro|--exec-label|--file-label|--proc|--dev|--tmpfs|\
        --mqueue|--dir|--seccomp|--add-seccomp-fd|--block-fd|--userns-block-fd|--info-fd|\
        --json-status-fd|--cap-add|--cap-drop|--perms|--size|--overlay-src|--tmp-overlay|--ro-overlay)
            shift 2 2>/dev/null || exit 1 ;;
        --*) shift ;;
        *) break ;;
    esac
done
[[ $# -gt 0 ]] || exit 0
exec "$@"
SHIM
    chmod +x "$HOME/.local/bin/bwrap"
    rm -rf "$HOME/.cache/glycin"
    echo "      Installed ~/.local/bin/bwrap stand-in"
fi

echo "[4/6] Disabling autostart apps that can't work on Android"
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

echo "[5/6] Stopping old server and clearing stale locks"
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

echo "[6/6] Starting KeX"
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
    echo "[FAIL] KeX did not stay running. Screenshot everything below and send it."
    LOG=$(ls -t "$HOME"/.local/state/tigervnc/*.log "$HOME"/.config/tigervnc/*.log "$HOME"/.vnc/*.log 2>/dev/null | head -1)
    echo "--- log: ${LOG:-none found} (known harmless noise hidden)"
    if [[ -n "$LOG" ]]; then
        cp "$LOG" "$HOME/kex-debug.log"
        grep -v -E 'GLib-GIO-CRITICAL|GLib-CRITICAL|Error creating proxy|GVFS-WARNING|connection is closed|g-io-error-quark|lost on the message dbus|power-manager|blueman|Traceback|^ +File "|^ +[~^]+$|setup_icon_path|prepend_search_path|app = |GDK_IS_SCREEN|^ *$' \
            "$LOG" | tail -30
    fi
    echo "--- processes:"
    ps -eo pid,args 2>/dev/null | grep -E 'Xtigervnc|Xvnc|xstartup|xfce4-session|dbus-daemon' | grep -v grep
    echo "--- xstartup in use:"
    head -3 "$HOME/.config/tigervnc/xstartup"
    echo
    echo "Most likely Android killed it. On the phone:"
    echo "  Settings > Developer options > turn ON 'Disable child process restrictions'"
    echo "  Settings > Apps > Termux > Battery > Unrestricted"
    echo "Then run this script again."
fi
