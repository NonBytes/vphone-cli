#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../.." && pwd)"
out="$root/.build/gadget-connection-tests"
mkdir -p "$out"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 -module-cache-path "$out/modules" \
 "$root/VPhoneLaunchpad/VPhonePentest/Models/VPhoneGadgetConnection.swift" \
 "$root/VPhoneKit/VPhonePentestKit/"{VPhoneProxyConfiguration,VPhoneProxyScriptResult,VPhoneFridaPortRelay,VPhoneGuestControlError,VPhoneGuestControlling,VPhoneLocalization,VPhoneEvidencePackage,VPhoneSandboxSnapshot}.swift \
 "${0:a:h}/GadgetConnectionTests.swift" -o "$out/tests"
"$out/tests" "$@"
