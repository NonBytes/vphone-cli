#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
out="$root/.build/evidence-export-tests"
ui="$root/VPhoneExecutable/VPhoneVirtualization/UI"
kit="$root/VPhoneKit/VPhonePentestKit"
/bin/mkdir -p "$out"
/usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
    -module-cache-path "$out/modules" \
    "$kit/VPhoneLocalization.swift" \
    "$kit/VPhoneGuestControlError.swift" \
    "$kit/VPhoneGuestControlling.swift" \
    "$kit/VPhoneFridaPortRelay.swift" \
    "$kit/VPhoneProxyConfiguration.swift" \
    "$kit/VPhoneProxyScriptResult.swift" \
    "$kit/VPhoneSandboxSnapshot.swift" \
    "$kit/VPhoneEvidencePackage.swift" \
    "$kit/VPhonePanelShared.swift" "$kit/VPhoneAppRecord.swift" \
    "$kit/VPhoneEvidenceExportWindowController.swift" "${0:a:h}/EvidenceExportTests.swift" -o "$out/tests"
"$out/tests"
