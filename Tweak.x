// divvy - experimental NAT egress-interface redirect for *one verified misd build*.
// iPhone 13 / iOS 17.0 / rootless / arm64e. Uses ElleKit's MSHookFunction.
// CAUTION: Correct hotspot-client routing is not yet established by device tests.
// This hook changes PF NAT rule construction only, not the default route,
// upstream selection, other PF rules, or DNS. It is not a proven repeater.

#import <Foundation/Foundation.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// ElleKit implements the Substrate-compatible API on Dopamine.
extern void MSHookFunction(void *symbol, void *replace, void **result);

// Observed in uploaded misd (MobileInternetSharing-289.0.3), at 0x10001a7ac.
// Callers pass six registers (x0..x5). Return is an int in w0.
// x0 = PF outbound interface name (stored under _kPFInterface).
// x1 = address family; x2 = textual address; x3 = prefix length;
// x4 and x5 = PF rule context values forwarded to the rule builder.
typedef int (*DivvyNatOutboundFn)(const char *interfaceName,
                                  int family,
                                  const char *address,
                                  uint32_t prefixLength,
                                  void *context,
                                  void *ruleSet);
static DivvyNatOutboundFn DivvyOriginalNatOutbound = NULL;

// Unslid function address minus Mach-O image base; NOT a file-offset
// string address (the function-name string itself lives at file 0x2944f).
static const uintptr_t kDivvyNatFunctionOffset = 0x1A7AC;

// LC_UUID from the exact 258,624-byte uploaded misd executable.
// A mismatch disables the hook rather than patching an unrelated function.
static const uint8_t kExpectedMisdUUID[16] = {
    0xC3, 0xDD, 0x0E, 0x90, 0xC9, 0x63, 0x38, 0xEA,
    0x9A, 0x55, 0x33, 0xB8, 0xB6, 0xD2, 0xED, 0x5D
};

static BOOL DivvyIsExactMisdImage(const struct mach_header_64 *header) {
    if (!header || header->magic != MH_MAGIC_64) return NO;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if (cursor + sizeof(struct load_command) > end) return NO;
        const struct load_command *cmd = (const struct load_command *)cursor;
        if (cmd->cmdsize < sizeof(struct load_command) ||
            cursor + cmd->cmdsize > end) return NO;
        if (cmd->cmd == LC_UUID && cmd->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uuid = (const struct uuid_command *)cursor;
            return memcmp(uuid->uuid, kExpectedMisdUUID, 16) == 0;
        }
        cursor += cmd->cmdsize;
    }
    return NO;
}

static BOOL DivvyEn0HasActiveIPv4(void) {
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return NO;
    BOOL active = NO;
    for (struct ifaddrs *cur = list; cur; cur = cur->ifa_next) {
        if (!cur->ifa_name || strcmp(cur->ifa_name, "en0") != 0 ||
            !cur->ifa_addr || cur->ifa_addr->sa_family != AF_INET) continue;
        unsigned int wanted = IFF_UP | IFF_RUNNING;
        if ((cur->ifa_flags & wanted) == wanted) {
            active = YES;
            break;
        }
    }
    freeifaddrs(list);
    return active;
}

static int DivvyNatOutboundReplacement(const char *interfaceName,
                                       int family,
                                       const char *address,
                                       uint32_t prefixLength,
                                       void *context,
                                       void *ruleSet) {
    DivvyNatOutboundFn original = DivvyOriginalNatOutbound;
    // MSHookFunction should have supplied the original trampoline.
    // If it didn't, do not dereference an invalid function pointer.
    if (!original) return 22; // EINVAL; installation should never reach here.

    // Only replace the cellular interface observed in this experiment.
    // Preserve every other call and fall back if Wi-Fi is down.
    if (interfaceName && strcmp(interfaceName, "pdp_ip0") == 0 &&
        DivvyEn0HasActiveIPv4()) {
        NSLog(@"[divvy] NAT outbound interface: pdp_ip0 -> en0");
        return original("en0", family, address, prefixLength, context, ruleSet);
    }
    return original(interfaceName, family, address, prefixLength, context, ruleSet);
}

%ctor {
    @autoreleasepool {
        const char *process = getprogname();
        if (!process || strcmp(process, "misd") != 0) return;

        const struct mach_header_64 *mainHeader =
            (const struct mach_header_64 *)_dyld_get_image_header(0);
        if (!DivvyIsExactMisdImage(mainHeader)) {
            NSLog(@"[divvy] misd build UUID mismatch; NAT hook DISABLED");
            return;
        }

        void *target = (void *)((uintptr_t)mainHeader + kDivvyNatFunctionOffset);
        MSHookFunction(target,
                       (void *)DivvyNatOutboundReplacement,
                       (void **)&DivvyOriginalNatOutbound);
        NSLog(@"[divvy] Installed experimental NAT outbound hook at %p", target);
    }
}
