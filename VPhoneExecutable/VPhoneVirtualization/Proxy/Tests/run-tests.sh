#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="${0:a:h:h:h}"
kit="${root:h:h}/VPhoneKit/VPhonePentestKit"
work="$(mktemp -d "${TMPDIR:-/tmp}/vphone-proxy-tests.XXXXXX")"
trap '/bin/rm -rf "$work"' EXIT
xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library \
    "$kit/VPhoneProxyConfiguration.swift" \
    "$kit/VPhoneProxyScriptResult.swift" \
    "${0:a:h}/ProxyTests.swift" -o "$work/proxy-tests"
"$work/proxy-tests"
