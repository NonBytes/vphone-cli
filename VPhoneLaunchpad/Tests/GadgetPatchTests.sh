#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../.." && pwd)"
ui="$root/VPhoneLaunchpad/VPhonePentest"
kit="$root/VPhoneKit/VPhonePentestKit"
out="$root/.build/gadget-patch-tests"
products="$root/.build/XcodeLaunchpad/Build/Products/Debug"
framework="$root/.build/XcodeLaunchpad/SourcePackages/artifacts/libarchive.xcframework/libarchive/libarchive.xcframework/macos-arm64_x86_64"
mkdir -p "$out"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -isysroot "$sdk" -fobjc-arc \
 -Wl,-headerpad,0x4000 "${0:a:h}/GadgetFixtures/app.m" -framework UIKit -framework Foundation -o "$out/Fixture"
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -isysroot "$sdk" -dynamiclib \
 -Wl,-headerpad,0x4000 "${0:a:h}/GadgetFixtures/gadget.c" -o "$out/FixtureGadget.dylib"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 -module-cache-path "$out/modules" \
 -I "$products" -F "$framework" -framework libarchive -lz -lbz2 -liconv -lxml2 \
 "$ui/Models/"{VPhoneGadgetMachO,VPhoneGadgetArchive,VPhoneGadgetPatcher,VPhoneIPAExport,VPhoneIPAArchive}.swift \
 "$kit/"{VPhoneEvidencePackage,VPhoneSandboxSnapshot}.swift \
 "$ui/Panels/VPhonePanelShared.swift" "$ui/Support/"{VPhoneLocalization,VPhoneGuestFileName}.swift \
 "${0:a:h}/GadgetPatchTests.swift" -o "$out/tests"
"$out/tests" "$out"
