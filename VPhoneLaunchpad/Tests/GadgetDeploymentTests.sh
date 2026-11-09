#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../.." && pwd)"
ui="$root/VPhoneLaunchpad/VPhonePentest"
out="$root/.build/gadget-deployment-tests"
mkdir -p "$out"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 -module-cache-path "$out/modules" \
 -I "$root/.build/XcodeLaunchpad/Build/Products/Debug" \
 -F "$root/.build/XcodeLaunchpad/SourcePackages/artifacts/libarchive.xcframework/libarchive/libarchive.xcframework/macos-arm64_x86_64" -framework libarchive -lz -lbz2 -liconv -lxml2 \
 "$ui/Transport/"*.swift \
 "$ui/Models/"{VPhoneGadgetDeployment,VPhoneGadgetUSB,VPhoneFridaPortRelay,VPhoneGadgetConnection,VPhoneGadgetPatcher,VPhoneGadgetMachO,VPhoneGadgetArchive,VPhoneIPAExport,VPhoneIPAArchive,VPhoneSandboxSnapshot,VPhoneEvidencePackage,VPhoneProxyConfiguration,VPhoneProxyScriptResult}.swift \
 "$ui/Panels/VPhonePanelShared.swift" "$ui/Support/"{VPhoneLocalization,VPhoneGuestFileName}.swift \
 "${0:a:h}/GadgetDeploymentTests.swift" -o "$out/tests"
"$out/tests"
