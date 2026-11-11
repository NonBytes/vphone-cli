#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../.." && pwd)"
ui="$root/VPhoneLaunchpad/VPhonePentest"
kit="$root/VPhoneKit/VPhonePentestKit"
out="$root/.build/ipa-export-tests"
mkdir -p "$out"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 -module-cache-path "$out/modules" \
 "$ui/Models/"{VPhoneIPAExport,VPhoneIPAArchive}.swift \
 "$root/VPhoneLaunchpad/VPhonePentestGuestExport/VPhoneIPAReader.swift" \
 "$ui/Panels/VPhoneIPAExportWindowController.swift" \
 "$kit/"{VPhonePanelShared,VPhoneAppRecord,VPhoneLocalization}.swift "$ui/Support/VPhoneGuestFileName.swift" \
 "${0:a:h}/IPAExportTests.swift" -o "$out/tests"
"$out/tests"
