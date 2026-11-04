#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
out="$root/.build/app-logs-tests"
ui="$root/VPhoneExecutable/VPhoneVirtualization/UI"
/bin/mkdir -p "$out"
/usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
    -module-cache-path "$out/modules" "$ui/GuestCommunication/VPhoneAppLogScope.swift" \
    "$ui/GuestCommunication/VPhoneProxyConfiguration.swift" "$ui/GuestCommunication/VPhoneSandboxSnapshot.swift" \
    "$ui/UserInterface/Panels/VPhonePanelShared.swift" "$ui/UserInterface/Panels/Console/VPhoneConsoleEntry.swift" \
    "$ui/UserInterface/Panels/Console/VPhoneConsoleModel.swift" \
    "$ui/UserInterface/Browsers/Apps/VPhoneAppRecord.swift" "$ui/UserInterface/Panels/VPhoneAppLogsModel.swift" \
    "$ui/UserInterface/Panels/CrashLogs/VPhoneCrashReportContent.swift" \
    "${0:a:h}/AppLogsTests.swift" -o "$out/tests"
"$out/tests"
if [[ "${1:-}" == --live ]]; then
    machine="${2:?Pass the test VM name}"
    /usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
        -module-cache-path "$out/modules" "$ui/GuestCommunication/VPhoneAppLogScope.swift" \
        "$ui/GuestCommunication/VPhoneProxyConfiguration.swift" "${0:a:h}/AppLogsGuestSmoke.swift" -o "$out/guest-smoke"
    "$out/guest-smoke" "$machine"
fi
