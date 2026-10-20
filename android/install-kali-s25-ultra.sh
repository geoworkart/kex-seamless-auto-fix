#!/data/data/com.termux/files/usr/bin/bash
#
# Installs Kali Linux on a Samsung Galaxy S25 Ultra without root: Kali NetHunter
# Rootless (full image) in Termux, updated, plus the default Kali tools.
#
# It runs Kali's official installer and adds what that installer doesn't do
# today: a free-space check, SHA256 verification of the download, detection of
# an interrupted unpack, DNS that doesn't depend on Kali's build server, and a
# KeX (VNC) server that only listens on the phone itself.
#
# Usage: bash install-kali-s25-ultra.sh [--large | --everything | --image-only] [--reinstall]

set -euo pipefail

ROOTFS_URL=https://kali.download/nethunter-images/current/rootfs
INSTALLER_URL=https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-rootless/raw/main/install-nethunter-termux
IMAGE=kali-nethunter-rootfs-full-arm64.tar.xz
CHROOT=$HOME/kali-arm64
UNPACKING=$CHROOT.incomplete
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

TOOLS=kali-linux-default
REINSTALL=

red='\033[1;31m'
green='\033[1;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
reset='\033[0m'

info() { printf '%b[*] %s%b\n' "$blue" "$*" "$reset"; }
warn() { printf '%b[!] %s%b\n' "$yellow" "$*" "$reset"; }
die() {
    printf '%b[x] %s%b\n' "$red" "$*" "$reset" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: bash install-kali-s25-ultra.sh [option]

Installs Kali NetHunter Rootless (full image) in Termux, updates it and adds
the default Kali tools (kali-linux-default). Run it again to update Kali.

  --large        install kali-linux-large instead of kali-linux-default
  --everything   install kali-linux-everything instead (can take hours)
  --image-only   only the full image: no update, no extra tools
  --reinstall    delete ~/kali-arm64 and everything in it, then install again
  -h, --help     show this help
EOF
}

check_phone() {
    [[ ${PREFIX:-} == */com.termux/files/usr ]] ||
        die "Run this in the Termux app (from the NetHunter Store or F-Droid, not Google Play)."
    local abi model
    abi=$(getprop ro.product.cpu.abi)
    [ "$abi" = arm64-v8a ] || die "This needs a 64-bit ARM phone; this one reports '$abi'."
    model=$(getprop ro.product.model)
    info "Phone: $model, Android $(getprop ro.build.version.release)"
    [[ $model == SM-S938* ]] ||
        warn "This is written for the Galaxy S25 Ultra (SM-S938x) but should work on any 64-bit ARM phone."
}

remove_rootfs() {
    if [ -d "$CHROOT" ]; then
        chmod -R u+rwX "$CHROOT"
        rm -rf "$CHROOT"
    fi
    rm -f "$UNPACKING"
}

check_space() {
    local need=0 free
    [ -d "$CHROOT" ] || need=11 # 1.8 GB download + ~8.3 GB unpacked
    # Rough download + installed size on top of the image, plus room for updates.
    case $TOOLS in
        kali-linux-default) need=$((need + 8)) ;;
        kali-linux-large) need=$((need + 17)) ;;
        kali-linux-everything) need=$((need + 43)) ;;
    esac
    free=$(df -Pk "$HOME" | awk 'NR == 2 {print int($4 / 1048576)}')
    [ "$free" -ge "$need" ] || die "This needs about $need GB of free space; the phone has $free GB."
}

setup_termux() {
    [ -d "$HOME/storage" ] || termux-setup-storage || true
    info "Updating Termux packages"
    export DEBIAN_FRONTEND=noninteractive
    pkg update
    apt-get "${APT_OPTS[@]}" full-upgrade
    apt-get "${APT_OPTS[@]}" install proot tar xz-utils axel curl coreutils
}

fetch_image() {
    local sums attempt
    sums=$(curl -fsSL "$ROOTFS_URL/SHA256SUMS") || die "Can't reach kali.download; check the internet connection."
    awk -v f="$IMAGE" '$2 == f' <<<"$sums" >"$IMAGE.sha256"
    [ -s "$IMAGE.sha256" ] || die "Kali's checksum list has no entry for $IMAGE."
    # A file from an earlier run is resumed. One left over from an older image
    # won't verify, so it gets one fresh download.
    for attempt in resume fresh; do
        [ "$attempt" = resume ] || rm -f "$IMAGE"
        info "Downloading the Kali NetHunter full image (1.8 GB)"
        curl -fL --retry 5 --retry-delay 5 -C - -o "$IMAGE" "$ROOTFS_URL/$IMAGE" ||
            die "The download stopped. Run the script again to resume it."
        info "Verifying the download"
        if sha256sum --status -c "$IMAGE.sha256"; then
            return
        fi
        warn "The download doesn't match Kali's checksum."
    done
    rm -f "$IMAGE"
    die "The download is still corrupt after a fresh try. Run the script again later."
}

unpack_image() {
    info "Unpacking Kali (~8.3 GB). This takes a while; keep Termux open in the foreground."
    touch "$UNPACKING"
    # Same tar command as Kali's installer, which ignores tar's complaints. xz
    # exits 0 only if tar read the whole image, so an unpack that Android killed
    # partway is caught here instead of leaving a half-installed Kali.
    local status
    set +e
    xz -dc "$IMAGE" | proot --link2symlink tar -xf - 2>/dev/null
    status=("${PIPESTATUS[@]}")
    set -e
    if [ "${status[0]}" != 0 ] || [ "${status[1]}" -ge 128 ]; then
        die "Unpacking was interrupted. Keep Termux in the foreground and run the script again."
    fi
    local f
    for f in bash apt-get dpkg sudo Xtigervnc xfce4-session; do
        [ -f "$CHROOT/usr/bin/$f" ] || die "Unpacking failed: /usr/bin/$f is missing. Run the script again."
    done
    rm -f "$UNPACKING"
}

run_kali_installer() {
    local installer=$PREFIX/tmp/install-nethunter-termux
    curl -fsSL -o "$installer" "$INSTALLER_URL" || die "Can't download Kali's installer from gitlab.com."
    # The answers below depend on these names; stop rather than guess if they change.
    # shellcheck disable=SC2016
    if ! grep -qF 'CHROOT=kali-${SYS_ARCH}' "$installer" ||
        ! grep -qF 'IMAGE_NAME=kali-nethunter-rootfs-${wimg}-${SYS_ARCH}.tar.xz' "$installer"; then
        die "Kali's installer has changed and this script needs an update."
    fi
    info "Running Kali's installer"
    # "1" picks the full image. Its other questions offer to delete the unpacked
    # Kali and the downloaded image; both get the default answer, no.
    printf '1\n' | bash -e "$installer" || die "Kali's installer failed (see above)."
    rm -f "$installer"
}

fix_dns() {
    local conf=$CHROOT/etc/resolv.conf
    # The image ships the resolv.conf of the machine it was built on.
    if [ ! -s "$conf" ] || grep -q systemd-resolved "$conf"; then
        rm -f "$conf"
        printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' >"$conf"
    fi
}

install_kex() {
    cat >"$CHROOT/usr/bin/kex" <<'EOF'
#!/bin/bash
# NetHunter KeX launcher, installed by install-kali-s25-ultra.sh. Same as Kali's,
# except that the VNC server only accepts connections from the phone itself
# unless started with --lan, and "kex kill" stops sessions.

function start-kex() {
    if [ ! -f ~/.vnc/passwd ]; then
        passwd-kex
    fi
    USR=$(whoami)
    SCREEN=":1"
    [ "$USR" = "root" ] && SCREEN=":2"
    export USER="$USR"
    LOCALHOST="yes"
    [ "$1" = "--lan" ] && LOCALHOST="no"
    vncserver "$SCREEN" -localhost "$LOCALHOST"
}

function stop-kex() {
    vncserver -kill :1 2>/dev/null
    vncserver -kill :2 2>/dev/null
}

function kill-kex() {
    pkill Xtigervnc
}

function passwd-kex() {
    vncpasswd
}

function status-kex() {
    vncserver -list
}

case "$1" in
    start) start-kex "$2" ;;
    stop) stop-kex ;;
    kill) kill-kex ;;
    status) status-kex ;;
    passwd) passwd-kex ;;
    *) start-kex "$1"; status-kex ;;
esac
EOF
    chmod 700 "$CHROOT/usr/bin/kex"
}

check_kali() {
    nethunter -r true || die "Kali is installed but won't start; run 'nethunter -r' to see the error."
    nethunter true || warn "Kali starts as root but not as user kali; use 'nethunter -r' for now."
}

update_kali() {
    [ -n "$TOOLS" ] || return 0
    info "Updating Kali and installing $TOOLS. This is the long part."
    # kali-desktop-xfce and tigervnc are already in the full image; they're
    # listed so that an existing minimal or nano install gets the desktop too.
    nethunter -r "export DEBIAN_FRONTEND=noninteractive; apt-get update &&
        apt-get ${APT_OPTS[*]} full-upgrade &&
        apt-get ${APT_OPTS[*]} install kali-desktop-xfce tigervnc-standalone-server $TOOLS &&
        apt-get clean" ||
        die "Updating Kali failed (see above). Kali itself works; run this script again to retry."
}

print_next_steps() {
    printf '%b' "$green"
    cat <<'EOF'

Kali Linux is installed. In Termux:

  nethunter                  Kali shell as user kali (short: nh)
  nethunter -r               Kali shell as root
  nethunter -r passwd kali   set the password sudo asks for
  nethunter kex passwd       set the desktop password (once)
  nethunter kex &            start the desktop, then connect the
                             NetHunter KeX app to 127.0.0.1:5901
  nethunter kex stop         stop the desktop

So Android doesn't kill the desktop ("signal 9"), turn on
Settings > Developer options > Disable child process restrictions
and set Settings > Apps > Termux > Battery to Unrestricted.
EOF
    printf '%b' "$reset"
}

main() {
    local arg answer
    for arg in "$@"; do
        case $arg in
            --large) TOOLS=kali-linux-large ;;
            --everything) TOOLS=kali-linux-everything ;;
            --image-only) TOOLS= ;;
            --reinstall) REINSTALL=1 ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                exit 2
                ;;
        esac
    done

    check_phone
    cd "$HOME"
    if [ -e "$UNPACKING" ]; then
        warn "The last run was interrupted while unpacking Kali; unpacking it again."
        remove_rootfs
    elif [ -n "$REINSTALL" ] && [ -d "$CHROOT" ]; then
        read -rp "Delete $CHROOT and everything in it? [y/N] " answer || true
        [[ $answer == [yY]* ]] || die "Cancelled."
        remove_rootfs
    fi
    check_space

    if command -v termux-wake-lock >/dev/null; then
        termux-wake-lock
        trap termux-wake-unlock EXIT
    fi
    setup_termux
    if [ ! -d "$CHROOT" ] || [ ! -x "$PREFIX/bin/nethunter" ]; then
        fetch_image
        [ -d "$CHROOT" ] || unpack_image
        run_kali_installer
        rm -f "$IMAGE" "$IMAGE.sha256"
    else
        info "Kali is already installed in $CHROOT; updating it and re-applying the fixes."
    fi
    fix_dns
    install_kex
    check_kali
    update_kali
    print_next_steps
}

main "$@"
