// Xcode 27's libswiftCompatibility56.a references swift::_swift_tsan_acquire, which is
// missing from the iOS Swift runtime, so the app dies in dyld at launch. That shim only
// matters below iOS 15.4, so this plugin's linker flag skips it, and this symbol satisfies
// libgodot.a's force-load reference to it.
extern "C" __attribute__((used, visibility("hidden")))
char swift_compat56_force_load_stub __asm__("__swift_FORCE_LOAD_$_swiftCompatibility56") = 0;

void swift_compat_fix_init() {}
void swift_compat_fix_deinit() {}
