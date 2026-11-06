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
was not installed or bound to test-vm; that guest remained stopped.

Manual guest checks: select an app in the browser, open the inspector, reload,
verify its running PID against the refreshed app list, inspect ATS exceptions,
open bundle/data containers, save a report and compare its fields with the UI.
Switch selections during loading and confirm old responses do not populate
the new selection. Guest/UI checks remain separate from fixture verification.

## App Browser icons

App Browser shows a 24-point icon beside each app name. Visible rows request
icons in batches of at most 12 through the existing guest-tool transport.
The signed `vphone-guest-icons` helper asks UIKit's installed-icon service for
the bundle identifier, then renders a 64×64 PNG. This includes icons stored
in asset catalogs; it does not need to launch the app or scan its data.
The UIKit selector is private and best-effort, so unavailable icons use the
standard app symbol and do not block browsing or app actions.

The window-local cache retains up to 128 images. Keys include bundle ID,
version, build and bundle path; Refresh invalidates cached results, and closing
the browser cancels pending work. Host decoding validates PNG magic, byte
size, frame count and dimensions before creating an image. Guest thumbnails
are capped at 256 KiB each. No new daemon API or guest environment update is
required; the helper is part of the Core Bundle.

On 2026-11-05 the renderer returned actual Settings and Calculator icons on
test-vm. A host check decoded both and rejected malformed, oversized
payloads and out-of-range dimensions, and verified changed app builds use a
different cache key. This checks rendering/decoding independently of UI
validation after loading the new Core Bundle.
