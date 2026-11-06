#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
out="$root/.build/deep-link-tester-tests"
ui="$root/VPhoneExecutable/VPhoneVirtualization/UI"
/bin/mkdir -p "$out"
/usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
    -module-cache-path "$out/modules" "$ui/GuestCommunication/VPhoneProxyConfiguration.swift" \
    "$ui/GuestCommunication/VPhoneSandboxSnapshot.swift" "$ui/GuestCommunication/VPhoneDeepLinkCase.swift" \
    "$ui/UserInterface/Panels/VPhonePanelShared.swift" "$ui/UserInterface/Browsers/Apps/VPhoneAppRecord.swift" \
    "$ui/UserInterface/Panels/VPhoneDeepLinkTesterModel.swift" "${0:a:h}/DeepLinkTesterTests.swift" -o "$out/tests"
"$out/tests"
