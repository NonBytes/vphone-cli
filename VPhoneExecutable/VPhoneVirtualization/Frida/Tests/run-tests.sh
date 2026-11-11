#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="${0:a:h:h:h}"
kit="${root:h:h}/VPhoneKit/VPhonePentestKit"
work="$(mktemp -d "${TMPDIR:-/tmp}/vphone-frida-tests.XXXXXX")"
trap '/bin/rm -rf "$work"' EXIT
xcrun --sdk macosx swiftc -module-cache-path "$work/modules" -swift-version 6 -parse-as-library \
    "$kit/VPhoneProxyConfiguration.swift" \
    "$kit/VPhoneFridaRelease.swift" \
    "$kit/VPhoneFridaCustom.swift" \
    "${0:a:h}/FridaReleaseTests.swift" -o "$work/tests" -framework CryptoKit
"$work/tests" "$@"
