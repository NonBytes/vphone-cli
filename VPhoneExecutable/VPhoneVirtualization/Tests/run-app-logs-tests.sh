#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
out="$root/.build/app-logs-tests"
ui="$root/VPhoneExecutable/VPhoneVirtualization/UI"
kit="$root/VPhoneKit/VPhonePentestKit"
/bin/mkdir -p "$out"
/usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
    -module-cache-path "$out/modules" "$kit/VPhoneAppLogScope.swift" \
    "$kit/VPhoneLocalization.swift" \
    "$kit/VPhoneGuestControlError.swift" \
    "$kit/VPhoneGuestControlling.swift" \
    "$kit/VPhoneGuestToolsShared.swift" \
    "$kit/VPhoneAlert.swift" \
    "$kit/VPhoneFridaPortRelay.swift" \
    "$kit/VPhoneProxyConfiguration.swift" "$kit/VPhoneProxyScriptResult.swift" \
    "$kit/VPhoneSandboxSnapshot.swift" "$kit/VPhoneEvidencePackage.swift" \
    "$kit/VPhonePanelShared.swift" "$kit/VPhoneConsoleEntry.swift" \
    "$kit/VPhoneConsoleModel.swift" \
    "$kit/VPhoneAppRecord.swift" "$kit/VPhoneAppLogsModel.swift" \
    "$kit/VPhoneCrashReportContent.swift" \
    "${0:a:h}/AppLogsTests.swift" -o "$out/tests"
"$out/tests"
if [[ "${1:-}" == --live ]]; then
    machine="${2:?Pass the test VM name}"
    /usr/bin/xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
        -module-cache-path "$out/modules" "$kit/VPhoneAppLogScope.swift" \
        "$kit/VPhoneProxyConfiguration.swift" "${0:a:h}/AppLogsGuestSmoke.swift" -o "$out/guest-smoke"
    "$out/guest-smoke" "$machine"
fi
