#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
out="$root/.build/network-diagnostics-tests"
shared="$root/VPhoneExecutable/VPhoneVirtualization/UI/GuestCommunication"
network="$root/VPhoneExecutable/VPhoneVirtualization/Network"
/bin/mkdir -p "$out"
/usr/bin/xcrun --sdk macosx clang -target arm64-apple-macos15.0 -O2 -c "$network/VPhoneCaptureNative.c" -o "$out/native.o"
/usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
    -module-cache-path "$out/modules" -import-objc-header "$network/VPhoneCaptureNative.h" \
    "$shared/VPhoneNetworkCapture.swift" "$shared/VPhoneNetworkProbe.swift" \
    "$shared/VPhoneProxyConfiguration.swift" "${0:a:h}/NetworkDiagnosticsTests.swift" "$out/native.o" -o "$out/tests"
"$out/tests"
if [[ "${1:-}" == --live ]]; then
    machine="${2:?Pass the test VM name}"
    /usr/bin/xcrun --sdk iphoneos swiftc -swift-version 6 -target arm64-apple-ios17.0 \
        -sdk "$(/usr/bin/xcrun --sdk iphoneos --show-sdk-path)" "${0:a:h}/NetworkGuestTraffic.swift" -o "$out/traffic"
    /usr/bin/codesign --force --sign - "$out/traffic"
    /usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
        -module-cache-path "$out/modules" "$shared/VPhoneNetworkCapture.swift" "$shared/VPhoneNetworkProbe.swift" \
        "$shared/VPhoneProxyConfiguration.swift" "$shared/VPhoneProxyScriptResult.swift" \
        "${0:a:h}/NetworkGuestSmoke.swift" -o "$out/guest-smoke"
    "$out/guest-smoke" "$machine" "$root/.build/XcodeBundle/Build/Products/Debug/VPhone.bundle/Contents/Resources/guest-resources/vphone-guest-network" "$out/traffic"
fi
