#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
out="$root/.build/sandbox-diff-tests"
/bin/mkdir -p "$out"
/usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library \
    -target arm64-apple-macos15.0 -module-cache-path "$out/modules" \
    "$root/VPhoneKit/VPhonePentestKit/VPhoneSandboxSnapshot.swift" \
    "$root/VPhoneExecutable/VPhoneVirtualization/Sandbox/VPhoneSandboxScanner.swift" \
    "${0:a:h}/SandboxDiffTests.swift" -o "$out/tests"
"$out/tests"
if [[ "${1:-}" == --live ]]; then
    machine="${2:?Pass the existing test VM name}"
    /usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library \
        -target arm64-apple-macos15.0 -module-cache-path "$out/modules" \
        "$root/VPhoneKit/VPhonePentestKit/VPhoneSandboxSnapshot.swift" \
        "$root/VPhoneKit/VPhonePentestKit/VPhoneProxyConfiguration.swift" \
        "$root/VPhoneKit/VPhonePentestKit/VPhoneProxyScriptResult.swift" \
        "${0:a:h}/SandboxGuestSmoke.swift" -o "$out/guest-smoke"
    "$out/guest-smoke" "$machine" "$root/.build/XcodeBundle/Build/Products/Debug/VPhone.bundle/Contents/Resources/guest-resources/vphone-guest-sandbox"
fi
