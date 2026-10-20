# kex-seamless-auto-fix
Fix broken KeX Seamless Mode in Kali Linux WSL2 with one click. Automatically resolves missing visuals, 0 client errors, and slow file manager launch. Includes VcXsrv fixes, .Xauthority config, XFCE session startup, and Windows firewall rules.

## xfce4-power-manager error spam in the KeX log

If `~/.vnc/*.log` fills up with `GLib-GIO-CRITICAL ... G_IS_DBUS_PROXY (proxy)` and
`Failed to get a systemd proxy` / `Unable to connect to the system bus` from
`xfce4-power-manager`, the session itself is fine. Power management just can't work
without systemd. Run:

```bash
./fix-power-manager.sh              # disable xfce4-power-manager autostart
./fix-power-manager.sh --system-dbus  # also start a system D-Bus (uses sudo)
```

Then restart KeX: `kex stop && kex`.
