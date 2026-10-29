#!/bin/zsh
# vphone-tier: build
set -euo pipefail
camera="${0:a:h:h}"
work="$(mktemp -d "${TMPDIR:-/tmp}/vphone-camera-tests.XXXXXX")"
trap '/bin/rm -rf "$work"' EXIT
/usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library \
    -target arm64-apple-macosx15.0 \
    "$camera/../UI/HostDevices/VPhoneMacCameraChannel.swift" \
    "$camera/VPhoneMacCameraState.swift" \
    "$camera/Tests/VPhoneMacCameraTests.swift" \
    -framework Foundation -framework CoreImage \
    -o "$work/vphone-camera-tests"
"$work/vphone-camera-tests"
