#!/bin/zsh
set -euo pipefail

daemon="${0:a:h:h}"
temporary="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/vphone-syslog-tests.XXXXXX")"
trap '/bin/rm -rf "$temporary"' EXIT

/usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -warnings-as-errors -parse-as-library \
    -module-cache-path "$temporary/module-cache" \
    "$daemon/Daemon/GuestMethodSpec.swift" \
    "$daemon/Daemon/GuestSyslog.swift" \
    "$daemon/Tests/SyslogTests.swift" \
    -o "$temporary/syslog-tests"
"$temporary/syslog-tests"
