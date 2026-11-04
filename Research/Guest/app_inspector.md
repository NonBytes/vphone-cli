# App Inspector

Open Apps > App Browser, select one app and use App Inspector (Command-I).
This extends the existing App Info inspector rather than adding a second app
inventory. Bundle/version/build, PID, signer, executable, sandbox, app groups,
URL schemes, Mach-O encryption and entitlements come from the existing
`apps.info`, `apps.list`, `apps.binary`, `apps.url_schemes` and `apps.network_policy`
contracts. The inspector's Reload re-reads each section and discards results
from an obsolete selection/reload. PID is read from a fresh app list because
`apps.info` does not provide running-process state. Missing process state is
shown as unavailable, separately from an app that is not running. Bundle and
data-container buttons open the existing guest File Browser.

The App Transport Security section downloads the installed app's Info.plist
through the existing file transport, accepts XML or binary plists, and renders
the full NSAppTransportSecurity dictionary, including exception domains. A
missing key, an explicitly empty dictionary, a malformed value and a read
failure are distinct states. The parser rejects input above 4 MiB. The file
transport's own limits apply to download before parsing. ATS is configuration
evidence, not a claim that runtime TLS or certificate pinning passed testing.

Save Report captures a JSON snapshot locally: app identity, paths, PID,
entitlements and ATS plists, load-state flags, section errors, capture time
and VM/re-signing limitations. It does not upload a report, retrieve keychain
secrets or classify findings automatically. Details describe the installed
guest binary; signing/entitlements may differ from the original IPA.

## Verification

Run `zsh VPhoneExecutable/VPhoneVirtualization/Tests/run-pentest-tools-tests.sh`.
The fixtures check XML/binary ATS dictionaries and nested exceptions, missing
versus empty dictionaries, malformed/oversized input, PID decoding and JSON
export. The same suite checks fragmented Frida protocol frames and native
client lifecycle cleanup (documented in frida_server.md).

On 2026-11-04 these local tests, the existing Frida release/custom validation
suite, the full Debug VPhone build and bundle admission passed. The new bundle
was not installed or bound to doctor-ipad; that guest remained stopped.

Manual guest checks: select an app in the browser, open the inspector, reload,
verify its running PID against the refreshed app list, inspect ATS exceptions,
open bundle/data containers, save a report and compare its fields with the UI.
Switch selections during loading and confirm old responses do not populate
the new selection. Guest/UI checks remain separate from fixture verification.
