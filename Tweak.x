// divvy — rootless iOS 17.0 / arm64e placeholder.
//
// No network settings, routing tables, daemons, or Wi-Fi firmware are
// modified here. Add actual ElleKit-compatible hooks ONLY after comparing
// wifi_before.txt / wifi_after.txt captured by scripts/capture-wifi-state.ps1.
//
// Candidate components to research: wifid, misd, hostapd, and configd.
// Do not guess class names, symbols, or hook targets without verification.

#import <Foundation/Foundation.h>

%ctor {
    // Intentionally empty: no hooks or side effects.
}
