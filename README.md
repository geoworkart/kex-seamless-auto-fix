# kex-seamless-auto-fix
Fixes for Kali NetHunter (rootless, via Termux) KeX on Android phones such as the Samsung Galaxy S25.

## xfce4-power-manager error spam in the KeX log

If `~/.vnc/*.log` fills up with `GLib-GIO-CRITICAL ... G_IS_DBUS_PROXY (proxy)` and
`Failed to get a systemd proxy` / `Unable to connect to the system bus` from
`xfce4-power-manager`, the session itself is fine. The Kali on the phone runs inside
Termux (proot) with no systemd and no system D-Bus, so the power manager can't work.
Android already handles power anyway. Inside Kali (`nethunter`), run:

```bash
./fix-power-manager.sh                # disable xfce4-power-manager autostart
./fix-power-manager.sh --system-dbus  # also start a system D-Bus
```

Then restart KeX: `kex stop && kex`.

## KeX dies with `[Process completed (signal 9)]` (Android 12+ / One UI)

Android kills Termux's background processes ("phantom process killer"). On the S25:

1. Settings → About phone → Software information → tap **Build number** 7 times.
2. Settings → Developer options → turn on **Disable child process restrictions**.

If that option is missing, run this from a computer with `adb`:

```bash
adb shell "settings put global settings_enable_monitor_phantom_procs false"
```

Also set Termux's battery usage to **Unrestricted** (Settings → Apps → Termux → Battery).
