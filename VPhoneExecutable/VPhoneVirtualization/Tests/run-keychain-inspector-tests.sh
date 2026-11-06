#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
out="$root/.build/keychain-inspector-tests"
ui="$root/VPhoneExecutable/VPhoneVirtualization/UI"
/bin/mkdir -p "$out"
/usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
    -module-cache-path "$out/modules" "$ui/GuestCommunication/VPhoneProxyConfiguration.swift" \
    "$ui/GuestCommunication/VPhoneSandboxSnapshot.swift" "$ui/GuestCommunication/VPhoneKeychainInspection.swift" \
    "$ui/UserInterface/Panels/VPhonePanelShared.swift" "$ui/UserInterface/Browsers/Apps/VPhoneAppRecord.swift" \
    "$ui/UserInterface/Browsers/Keychain/VPhoneKeychainItem.swift" "$ui/UserInterface/Panels/VPhoneKeychainInspectorModel.swift" \
    "${0:a:h}/KeychainInspectorTests.swift" -o "$out/tests"
"$out/tests"
