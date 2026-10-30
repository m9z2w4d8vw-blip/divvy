# divvy — experimental iOS 17 Wi-Fi hotspot NAT hook

A rootless Theos / ElleKit tweak for the **iPhone 13, iOS 17.0, Dopamine 3**.
This repository contains an **active experimental** `MSHookFunction` interception
of a specific `misd` NAT configuration function. **Wi-Fi-to-Wi-Fi internet sharing
has NOT yet been verified end to end.** Do not install expecting a finished repeater.

## What the code does

- Injects only into the `misd` executable (`divvy.plist`, not SpringBoard).
- Checks the main executable's Mach-O UUID before hooking; if different, **does not hook**.
- Hooks the function at image-relative offset `0x1A7AC` on the tested binary.
- When its NAT outbound interface-name argument is `pdp_ip0` **and** `en0`
  has an active IPv4 address, passes `en0` to the original function.
- Otherwise calls the original function without changing arguments.
- Does **not** change the kernel default route, guarantee hotspot-client internet,
  manage the DHCP server, or patch other NAT rules.

### Binary provenance and limitations

The original 258,624-byte arm64e `misd` from the test device has Mach-O UUID
`C3DD0E90-C963-38EA-9A55-33B8B6D2ED5D`. An ARM64 disassembly identified
`mis_pf_configure_nat_outbound` (name found in error strings, **not an exported symbol**)
at `0x10001A7AC`, relative to image base by `0x1A7AC`. Four direct call sites
were observed. A full production ABI/function-semantics review is still advisable.
The Apple executable is **not** included in this repo.

### Confirmed network behavior on the test device

With Personal Hotspot enabled, `en0` and `ap1` remain active simultaneously,
`bridge100` is created for `ap1`, and `net.inet.ip.forwarding` is set to `1`.
The selected default IPv4 route changes from `en0` to `pdp_ip0`. A manual
route swap has selected `en0` successfully, and phone-side curl succeeds via
`--interface en0`. **None of those tests proves hotspot-client NAT uses en0.**

## Build / GitHub Desktop

1. Clone `https://github.com/m9z2w4d8vw-blip/divvy` in GitHub Desktop.
2. Copy **all contents** of this ZIP's `divvy/` folder into that clone, replacing
   the existing files, while preserving the clone's `.git` directory.
3. In GitHub Desktop, review the changed files, **Commit to main**, then
   **Push origin**.
4. `.github/workflows/build.yml` builds the arm64e rootless `.deb`, uploads the
   Actions artifact, and publishes a GitHub Release tagged `v-<shortSHA>`.
5. Obtain the `.deb` from **Releases**. Building does not install it automatically.

The workflow is based on the repository version that had previously published
`com.parv.divvy_0.0.1_iphoneos-arm64.deb`. This modified hook has **not been
compiled or tested on a live iPhone in this session**.

## Important installation and rollback precautions

- The hook targets a system daemon. A bad hook may cause `misd` crashes,
  broken hotspot service, or unexpected network behavior.
- Back up the working jailbreak state and retain an SSH/local recovery method.
- If it disrupts service, disable/remove `com.parv.divvy` using your package
  manager or recover in an unjailbroken state before attempting another version.
- A matching UUID only guards binary version. It is **not** proof of runtime safety.
- The current control package version is `0.1.0` (experimental).

## Windows diagnostic scripts

- `scripts/capture-wifi-state.ps1`: read-only before/after capture (rootless paths).
- `scripts/route-swap-ip-compare.ps1`: **changes the live route** through `sudo`,
  then compares the phone's `en0` and default public IPv4 addresses.
- `scripts/hotspot-connectivity-test.ps1`: read-only curl testing; does not
  modify the route.

Run with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\<name>.ps1`.
The scripts are not executed during GitHub Actions builds or on install.
Do not publish saved captures without checking for IP and MAC addresses.
