#!/bin/zsh
set -euo pipefail
launchpad="${0:a:h:h}"
work="$(mktemp -d)"
trap '/bin/rm -rf "$work"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
    "$launchpad/VPhoneLaunchpadShared/VPhoneLaunchpadMacCameraSupport.swift" \
    "$launchpad/Tests/MacCameraSupportTests.swift" -o "$work/mac-camera-tests"
"$work/mac-camera-tests"
