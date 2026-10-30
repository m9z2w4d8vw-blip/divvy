# divvy

Rootless Theos tweak scaffold targeting an iPhone 13 on iOS 17.0 with Dopamine / ElleKit.

**This is a hook-free placeholder, not a functioning Wi-Fi repeater.** Do not
assume simultaneous station + AP support until the diagnostic results confirm it.

## Network state capture (Windows PowerShell 5.1+)

From the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\capture-wifi-state.ps1
```

The script uses Windows' built-in `ssh.exe`, first with Personal Hotspot off,
then after you enable it. If SSH momentarily disconnects, the second snapshot
retries up to 10 times, sleeping 3 seconds between attempts. It saves only on
the Windows PC, to `%USERPROFILE%\Desktop`:

- `wifi_before.txt`
- `wifi_after.txt`
- `wifi_diff.txt`

No files are written to the iPhone. With password authentication, you may have
to enter your password again after a disconnect; key-based SSH is recommended.
If hotspot changes your iPhone's IP address or makes SSH entirely unreachable,
retrying this same address cannot solve that. Reconnect to your iPhone and rerun
when both snapshots can be obtained.

The summaries inspect `en0`, `ap1`, `bridge100`, the default IPv4 route, and
`net.inet.ip.forwarding`. A reported `UP` flag alone does not guarantee a usable
Wi-Fi link; check the interface's `status:` and test actual connectivity.

**Privacy:** these reports may contain MAC addresses, IP addresses and router
information. Review before publishing or committing them.

## Tweak / GitHub Actions

- `THEOS_PACKAGE_SCHEME = rootless`
- `ARCHS = arm64e`
- `TARGET = iphone:clang:16.5:15.0`
- Explicit link-time dependency on `@rpath/libellekit.dylib`. The local
  `vendor/ellekit/libellekit.tbd` is a small link-time stub, *not* ElleKit itself.
  ElleKit must be installed on the device.
- `entitlements.plist` is empty, intentionally.
- `divvy.plist` filters the placeholder to SpringBoard.

Push commits to trigger `.github/workflows/build.yml`. Download the resulting
`.deb` from the workflow's **Artifacts**; it is not auto-installed on the phone.

The package identifier is `com.parv.divvy`, version 0.0.1.

## Caution

Do not deploy network policy hooks, packet-forwarding changes, or daemon tweaks
until you have inspected the before/after capture and tested safe rollback.
