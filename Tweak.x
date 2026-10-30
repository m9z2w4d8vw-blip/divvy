
#import <Foundation/Foundation.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <stdlib.h>
#include <string.h>

static BOOL DivvyInterfaceIsActive(const char *name) {
    struct ifaddrs *interfaces = NULL;

    if (getifaddrs(&interfaces) != 0) {
        return NO;
    }

    BOOL active = NO;

    for (struct ifaddrs *item = interfaces;
         item != NULL;
         item = item->ifa_next) {

        if (item->ifa_name == NULL) {
            continue;
        }

        if (strcmp(item->ifa_name, name) != 0) {
            continue;
        }

        unsigned int required = IFF_UP | IFF_RUNNING;

        if ((item->ifa_flags & required) == required) {
            active = YES;
            break;
        }
    }

    freeifaddrs(interfaces);
    return active;
}

%ctor {
    @autoreleasepool {
        const char *process = getprogname();

        if (process == NULL ||
            strcmp(process, "misd") != 0) {
            return;
        }

        BOOL wifiActive = DivvyInterfaceIsActive("en0");
        BOOL hotspotActive = DivvyInterfaceIsActive("ap1");

        NSLog(@"[divvy] Loaded into misd");
        NSLog(@"[divvy] en0 active: %@", wifiActive ? @"YES" : @"NO");
        NSLog(@"[divvy] ap1 active: %@", hotspotActive ? @"YES" : @"NO");

        // No routing or upstream changes are performed.
        //
        // A future MSHookFunction hook must use an independently
        // verified misd function address and calling convention.
        //
        // If en0 is unavailable, that hook must invoke the
        // original implementation without modification.

        NSLog(@"[divvy] Upstream hook not installed: "
              @"target function not yet verified.");
    }
}
