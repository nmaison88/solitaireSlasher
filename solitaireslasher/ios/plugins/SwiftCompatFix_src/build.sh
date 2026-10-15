#!/bin/sh
# Rebuilds ../SwiftCompatFix.xcframework from swift_compat_fix.cpp
set -e
cd "$(dirname "$0")"
T=$(mktemp -d)
xcrun -sdk iphoneos clang -c -arch arm64 -miphoneos-version-min=15.0 swift_compat_fix.cpp -o "$T/dev.o"
xcrun -sdk iphonesimulator clang -c -arch arm64 -arch x86_64 -mios-simulator-version-min=15.0 swift_compat_fix.cpp -o "$T/sim.o"
mkdir -p "$T/dev" "$T/sim"
libtool -static -o "$T/dev/SwiftCompatFix.a" "$T/dev.o"
libtool -static -o "$T/sim/SwiftCompatFix.a" "$T/sim.o"
rm -rf ../SwiftCompatFix.xcframework
xcodebuild -create-xcframework -library "$T/dev/SwiftCompatFix.a" -library "$T/sim/SwiftCompatFix.a" -output ../SwiftCompatFix.xcframework
rm -rf "$T"
