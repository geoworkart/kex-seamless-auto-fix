# Kali Linux on the Galaxy S25 Ultra

[`install-kali-s25-ultra.sh`](install-kali-s25-ultra.sh) installs Kali Linux on a
Samsung Galaxy S25 Ultra without root: Kali NetHunter Rootless with the **full**
image, updated, plus the default Kali tool set (`kali-linux-default`, the tools a
normal Kali install comes with). You get a Kali shell in Termux and an Xfce
desktop through NetHunter KeX, which also works on a monitor with Samsung DeX.

## Why rootless

Full NetHunter needs root, which on Android means an unlocked bootloader and a
NetHunter kernel built for the phone. The S25 Ultra has neither: US models have
never allowed bootloader unlocking, One UI 8 removed the OEM unlocking option on
the others ([9to5Google](https://9to5google.com/2025/07/26/samsung-galaxy-one-ui-8-bootloader-unlock/)),
and unlocking would permanently trip Knox (Samsung Wallet, Secure Folder).
[NetHunter Rootless](https://www.kali.org/docs/nethunter/nethunter-rootless/)
runs Kali in Termux through proot instead, on the stock phone.

What that means in practice:

- The full image already has nmap, Metasploit, sqlmap, john, aircrack-ng and
  Wireshark; `kali-linux-default` adds hydra, hashcat, gobuster, ffuf, nikto,
  wpscan, impacket and the rest of the standard tools. Burp Suite isn't in the
  arm64 default set; add it with `nethunter -r apt install -y burpsuite`.
- Anything that needs the real kernel or real root doesn't work: no Wi-Fi
  monitor mode or packet injection, no USB Wi-Fi adapter drivers, no HID/BadUSB
  attacks, no raw-socket scans or live packet capture. Run nmap as
  `nmap --unprivileged -sT ...`; Metasploit runs without its database.

## 1. Prepare the phone

1. **Free space**: about 19 GB for the default install (see [Options](#options)).
2. **Turn off Auto Blocker**, which blocks installing apps from outside the
   Galaxy Store and Google Play: Settings > Security and privacy > Auto Blocker.
3. **Install the NetHunter Store** from <https://store.nethunter.com>, then
   from it install **Termux** and **NetHunter KeX** (Kali also suggests
   **Hacker's Keyboard**). Don't use Termux from Google Play: the Termux
   maintainers don't support that build, and Termux apps from different stores
   can't be mixed. You can turn Auto Blocker back on afterwards.
4. **Stop Android from killing Kali.** Android limits how many processes an app
   can start and kills the rest, which ends the desktop with
   `[Process completed (signal 9) - press Enter]`.
   - Enable Developer options: Settings > About phone > Software information >
     tap **Build number** 7 times.
   - Settings > Developer options > turn on **Disable child process
     restrictions**. If your One UI build doesn't have it, run this once from a
     computer with ADB and USB debugging on:
     `adb shell settings put global settings_enable_monitor_phantom_procs false`
   - Settings > Apps > Termux > Battery > **Unrestricted**.

## 2. Install

Open Termux and run:

```sh
pkg install -y curl
curl -fLo install-kali.sh https://raw.githubusercontent.com/geoworkart/kex-seamless-auto-fix/main/android/install-kali-s25-ultra.sh
bash install-kali.sh
```

Allow storage access if Android asks. The script downloads the 1.8 GB image,
unpacks it, then downloads about 1.2 GB of tools plus any Kali updates since the
image was built, so use Wi-Fi. Keep Termux open until it finishes. If it gets
interrupted, run `bash install-kali.sh` again: it resumes the download and
redoes an interrupted unpack. Running it again later also updates Kali.

### Options

| Command | Installs | Free space needed |
| --- | --- | --- |
| `bash install-kali.sh` | full image + `kali-linux-default` | 19 GB |
| `bash install-kali.sh --large` | full image + `kali-linux-large` | 28 GB |
| `bash install-kali.sh --everything` | full image + `kali-linux-everything` (can take hours) | 54 GB |
| `bash install-kali.sh --image-only` | full image only, not updated | 11 GB |

`--reinstall` deletes `~/kali-arm64`, including anything you saved inside
Kali, and installs from scratch. It asks first.

## 3. Use it

In Termux:

| Command | What it does |
| --- | --- |
| `nethunter` (or `nh`) | Kali shell as user `kali` |
| `nethunter -r` | Kali shell as root |
| `nethunter -r passwd kali` | set the password `sudo` asks for |
| `nethunter kex passwd` | set the desktop password, once (VNC uses at most 8 characters) |
| `nethunter kex &` | start the desktop |
| `nethunter kex stop` | stop it; `nethunter kex kill` if it's stuck |

Then open the **NetHunter KeX** app and connect to `127.0.0.1:5901` with the
desktop password. A root desktop (`nethunter -r kex &`) is on `127.0.0.1:5902`.
Your phone's storage is at `/sdcard` inside Kali.

**On a monitor with DeX**: connect the phone to a monitor (USB-C to HDMI, or
wireless DeX to a TV), start the desktop, open NetHunter KeX in DeX, set its
resolution to the monitor's (for example 1920x1080) under Advanced Settings,
and maximize the window. With a Bluetooth or USB keyboard and mouse, that's a
full Kali desktop.

**From another device**: the desktop only accepts connections from the phone
itself. To reach it from a laptop on the same network, start it with
`nethunter kex start --lan` and connect a VNC viewer to the phone's IP address
on port 5901. VNC passwords are weak, so do this only on networks you trust.

## What the script does

It runs [Kali's official installer](https://www.kali.org/docs/nethunter/nethunter-rootless/),
picks the full image, and adds what that installer doesn't do today:

- **Checks free space first.** The full image unpacks to about 8.3 GB, and
  Kali's installer hides unpacking errors, so running out of space would leave
  a broken install.
- **Verifies the download** against Kali's published `SHA256SUMS`. Kali's
  installer looks for a `.sha512sum` file that isn't published, so it skips
  the check.
- **Catches an interrupted unpack**, for example when Android kills Termux, and
  redoes it on the next run instead of leaving a half-installed Kali.
- **Fixes DNS inside Kali.** The image's `/etc/resolv.conf` points at the DNS
  server of the machine the image was built on. The script replaces it with
  Google (8.8.8.8) and Cloudflare (1.1.1.1), unless you've edited it.
- **Keeps the desktop private.** Kali's KeX launcher starts the VNC server with
  `-localhost no`, so anyone on the same Wi-Fi can reach the desktop's password
  prompt. This one listens on the phone only, unless you ask for `--lan`. Its
  `kex kill` also kills sessions, as Kali's docs describe, instead of starting
  a new one.
- Updates Termux and Kali, installs the tool set you chose, and holds a wake
  lock while it runs so the phone doesn't sleep partway.

## Troubleshooting

- **`[Process completed (signal 9) - press Enter]`**: Android killed Kali. Do
  step 4 of [Prepare the phone](#1-prepare-the-phone).
- **`sudo` doesn't work as user kali**: Kali's docs note some Galaxy phones
  block it in rootless Kali. Use `nethunter -r` for root instead.
- **NetHunter KeX can't connect**: run `nethunter kex status`. If no session is
  listed, run `nethunter kex kill`, then `nethunter kex &`. Connect to
  `127.0.0.1:5901`, not the phone's network address.
- **The install stopped partway**: run `bash install-kali.sh` again.
- **Uninstall**: in Termux, run
  `chmod -R u+rwX ~/kali-arm64 && rm -rf ~/kali-arm64 $PREFIX/bin/nethunter $PREFIX/bin/nh`.
