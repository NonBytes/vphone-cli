#!/bin/zsh
set -euo pipefail
launchpad="${0:a:h:h}"
work="$(mktemp -d)"
trap '/bin/rm -rf "$work"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
    "$launchpad/VPhoneLaunchpadShared/VPhoneLaunchpadDelegatedCameraStatus.swift" \
    "$launchpad/Tests/DelegatedCameraStatusTests.swift" -o "$work/delegated-camera-tests"
"$work/delegated-camera-tests" "$@"
