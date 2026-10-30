THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0

TWEAK_NAME = divvy

# A hook-free skeleton until live network snapshots identify safe hook targets.
divvy_FILES = Tweak.x
divvy_CFLAGS = -fobjc-arc
# The filter is restricted to SpringBoard while this is a scaffold.
# ElleKit supplies libellekit.dylib on the rootless Dopamine filesystem.
# The text stub under vendor/ellekit is for linking, not bundled in the .deb.
divvy_LIBRARIES = ellekit
divvy_LDFLAGS += -L$(CURDIR)/vendor/ellekit -Wl,-needed-lellekit
# Do not link CydiaSubstrate; ElleKit implements the hooking API at runtime.
# If adding Logos hooks later, they must use an ElleKit-compatible API.

TARGET_CODESIGN = ldid
TARGET_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
