# Keychain Inspector

Open **Data → Keychain Inspector…**, or its button in **App Inspector**.
The inspector is read-only and has no add, edit, delete or entitlement-change
operation. It uses the existing vphoned Keychain APIs; no new guest helper,
wildcard entitlement, guest environment update or firmware patch is installed.
The existing Keychain Browser remains available separately.

## Workflow and scope

1. Choose App declared groups and select an app, or enter one Exact access
   group. App scope uses only explicit, exact `keychain-access-groups` returned
   by `apps.info`. Wildcards and unresolved build variables are excluded; an
   application identifier is not silently assumed to be a Keychain group.
2. Scan Metadata lists scoped rows without requesting values. The existing
   `keychain.list` API returns a guest-wide metadata listing, which the host
   filters by exact group. Its Security/framework and protected-database
   sources are kept distinct. The all-groups mode must be selected explicitly.
3. Dump Readable Values performs the metadata scan, then calls `keychain.get`
   for individually addressable generic/internet-password rows backed by
   Security.framework. Before each query, the complete metadata scan is checked
   for ambiguity, including matches caused by omitted empty attributes and
   entries beyond the display cap. Ambiguous queries are skipped. Certificate
   and cryptographic-key rows stay metadata-only.
4. Values are hidden initially. Reveal values enables display and searching
   through returned values. Clear, changing scope or closing the window clears
   the inspector's retained values. Cancel/Clear stops issuing further queries
   after the in-flight request finishes; late responses are ignored.
5. Export JSON saves the currently filtered rows with capture time, captured
   scope/groups, app version/build when available, source, query diagnostics
   and partial-result state. Include values in export is off by default.
   Exports use private temporary files and atomic replacement (0600).

The selected group's rows are not proof that the selected app owns those
items. Shared groups can contain data used by multiple apps. Likewise, guest
agent access does not establish access from the selected application's
process. Queries and the preceding metadata scan are not an atomic snapshot;
items may change between them.

## Comparison with objection

Objection's [iOS Keychain implementation](https://github.com/sensepost/objection/blob/master/agent/src/ios/keychain.ts)
queries Security.framework inside the process being instrumented. This UI
provides a similar tabular metadata/value view and JSON export, but reads
through vphoned's existing access rather than attaching to that app. It is not
an implementation of objection's app-process access context or smart decoder.

The older guest API does not distinguish UTF-8 text from data it encoded as
base64. The inspector preserves the returned string and labels that ambiguity;
it never guesses that a token is base64 and decodes it automatically. An empty
returned string is also not proof of a readable zero-length item: the legacy
API may return it when data was absent. Accessibility and dates are shown when
provided, otherwise explicitly unavailable. Protected database metadata is
never represented as decrypted values. Authentication/access refusals remain
failed/protected reads; there is no passcode or biometric bypass.

Limits are 500 displayed rows, 64 KiB per returned value string and 512 KiB of
retained value text. Reaching a value limit stops further reads. The value loop
checks a 30-second budget between requests; an in-flight RPC may finish later.
Metadata transport remains subject to the existing guest HTTP/RPC limits.
Default export redacts the value field only: account, service, group and other
metadata can themselves contain sensitive data and should be reviewed before
sharing. Nothing is uploaded automatically.

## Validation

Run `zsh VPhoneExecutable/VPhoneVirtualization/Tests/run-keychain-inspector-tests.sh`.
The real inspector model is exercised with synthetic transport responses for
exact-group filtering, metadata-only scans, ambiguous/partially specified
queries, redacted export, frozen export provenance, row/value caps, empty
legacy responses, access refusal and late-result cancellation. CI runs these
fixtures. The full VPhone build validates the finished UI bundle.

On 2026-11-05 the running pentest-test-vm VM's existing `keychain.list` reported
0 Security-accessible rows and 58 protected database metadata rows. An attempt
to add a uniquely named synthetic canary through the existing API failed with
`keychain add did not persist`; a follow-up metadata check found no matching
fixture to clean up. No other item's value was requested. Therefore this live
check establishes the current guest-access limitation, not successful secret
retrieval. No additional privileges or keychain database decryption were used.

The final `2.15.2-local.58ca5c71` bundle was installed and started on test-vm
for GUI validation. Its older guest agent reported 0 Security-accessible items
and 71 protected metadata rows. An exact nonexistent test group returned zero
rows; all-groups metadata scanning displayed the 71 rows as encrypted metadata.
No existing item's value was requested. Scope transitions clear results
synchronously, and a regression test checks that scans wait for new app groups
to resolve. Export from the UI retained the exact test group, omitted values
by default, and created a 0600 local JSON file. The viewer was closed afterward;
test-vm remains running on that bundle. The other running VM and both
guest environments were left unchanged. Host build, bundle admission and
model fixtures passed; live secret retrieval remains unverified/unavailable
on these tested guest agents.

### Source-level root cause of `keychain add did not persist` (2026-11-15, iOS 27.2.1)

Reproduced again on iOS 27.2.1 through `keychain.add`, including with an
explicit `group` (the updated, not-yet-committed `GuestKeychain.add` passes
`group` through to `addKeychain`; see `VPhoneDaemon/Daemon/GuestKeychain.swift`).
Creating and deleting the same item via the in-app Frida script synthesizer
(`VPhoneKeychainInspectorModel.swift`, `BuiltInScript.add`/`.delete`) inside
the *target app's own process* still succeeds.

The error string is emitted by vendored `IcliKit` (`owngoal-dev/icli`, pinned
in `VPhone.xcworkspace/.../Package.resolved`), not by anything in this repo:
`addKeychain` in `Host/Host.swift` calls `SecItemAdd` with
`kSecReturnAttributes`/`kSecReturnPersistentRef` and throws
`"keychain add did not persist"` only when `SecItemAdd` returns `errSecSuccess`
(so `throwIfKeychain` does not throw) yet hands back a `nil` result — and the
guest's own `keychain.list` independently reports 0 Security-accessible rows
for `vphoned`, so this is not a read-back-only glitch: the item is never
written.

`vphoned`'s entitlements (`VPhoneDaemon/VPhoneDaemon.entitlements`) already
carry `keychain-access-groups: ["*", "apple", "com.82flex.TrollVNCApp",
"GXZ23M5TP2.com.82flex.TrollVNCApp"]` plus
`com.apple.private.system-keychain` and
`com.apple.private.security.storage.Keychains`. On earlier iOS this
unentitled-daemon-plus-wildcard-group combination was enough for `securityd`
to accept an unentitled process's `SecItemAdd`/`SecItemCopyMatching`. The
2026-11-05 and 2026-11-15 runs together indicate `securityd` on 27.2.1 no
longer honors it for `vphoned`'s own process identity, for both read
(`keychain.list` sees only encrypted metadata rows, never Security-accessible
ones) and write (`keychain.add` reports success but never persists) — while
the same `SecItemAdd`/`SecItemDelete` calls succeed when executed by Frida
inside the target app's process, which carries that app's own real
entitlements/code identity rather than vphoned's ad hoc one. This reads as a
securityd-side entitlement/identity check that hardened between the guest
builds this project has tested against and 27.2.1, not a bug in
`GuestKeychain.swift`, `GuestAPI.swift`, or the `IcliKit` call parameters.

Not yet tried: whether any `kSecAttrAccessGroup` value lets vphoned's own
process write at all on 27.2.1 (e.g. an empty/omitted group so the item lands
in vphoned's own default group, rather than one from the wildcard list), and
whether `security_cf`/`securityd` logs on the guest (via `log stream` or a
sysdiagnose) name the specific entitlement or identity check that is
rejecting the write. Until one of those is run, keep `keychain.add`/`.update`
documented as unreliable on 27.2.1 and point users needing a guaranteed write
at the in-app Frida script path, which does not depend on vphoned's own
keychain identity.

### Live confirmation (2026-11-15, fresh `codex-pentest-smoke-1115`, iOS 27.2.1 24B156)

Booted a brand-new, never-before-tested VM (`vphone-cli vm launch
codex-pentest-smoke-1115`) specifically to rule out VM-specific corruption,
then drove the Keychain Inspector's "Add / Inject Item…" dialog (Data menu)
by hand against the running guest:

| Attempt | Account | Access Group | Result |
| --- | --- | --- | --- |
| 1 | `canary-nogroup-1115` | *(none)* | `keychain add did not persist` |
| 2 | `canary-applegroup-1115b` | `apple` (one of vphoned's own `keychain-access-groups` entries) | `keychain add did not persist` |

Both failures were fresh (the account name was changed between attempts and
the dialog still re-showed the error), ruling out a missing or wrong `group`
parameter as the cause — passing a group vphoned is actually entitled to
makes no difference.

Checked whether either attempt silently wrote anything vphoned itself cannot
read back: "Scan Metadata" with Scope = "All guest-visible groups" (the
widest the inspector offers) found **58/58 rows**, searching for "canary"
matched **0 rows**, and expanding "Diagnostics / query coverage" read
`Security: 0 accessible items` / `Database: 58 protected metadata rows` —
both counts unchanged from before the add attempts and identical in shape to
the `58 protected database metadata rows` / `0 Security-accessible rows`
recorded on 2026-11-05 against a different guest. All 58 rows are
pre-existing system items (`com.apple.bluetooth`, `com.apple.cloudd`,
`com.apple.continuity`, `com.apple.cfnetwork`, `com.apple.security.*`,
`ichat`, `lockdown-identities`); nothing from either add attempt appears
among them. So neither attempt persisted anywhere vphoned can see, on a
guest with no other activity on it — this is not a race with some other
process and not scope/filter noise.

This also lets one part of the above analysis be corrected rather than left
as a hypothesis: the guest's serial console log was captured across both add
attempts (`vphone-cli vm launch` output), and line counts were diffed
immediately before/after each click of "Commit to Guest" — **zero new kernel
lines appeared at the moment of either attempt**. In particular, the
`"AppleSEPKeyStore":pid:63,:13253: operation failed (sel: 57 ret: e00002c2)`
/ `pid:36,:13253: operation failed (sel: 135 ret: e00002e6)` lines seen
earlier in this same boot are boot-time noise (they recur every ~20s during
normal boot, unrelated to any keychain RPC) and are **not** the mechanism
behind `keychain add did not persist` — do not cite them as the cause in any
follow-up; whatever rejects the write happens inside securityd and leaves no
trace on the kernel serial console, so finding it needs `log stream`/syslog
access inside the guest (not yet available on an un-bootstrapped VM — see
`Documents/en/machines/package-environment.md` for installing `openssh-server`
first) or a sysdiagnose.

### Root cause found: `securityd` rejects vphoned as "not eligible" (2026-11-15)

No guest shell or bootstrap needed in the end — `vphoned`'s own `logs.syslog`
RPC (`VPhoneDaemon/Daemon/GuestAPILogMethods.swift`) reads the unified log
directly, and the automation API exposes it over plain HTTP with no
websocket client required:

```sh
vphone-cli vm launch codex-pentest-smoke-1115 --api-listen 127.0.0.1:8765
# VPHONE_API_TOKEN set before launch, or read the printed "[api] token:" line
curl -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"method":"logs.syslog","params":{"process":"securityd","seconds":10}}' \
  http://127.0.0.1:8765/v1/rpc &
sleep 2
curl -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"method":"keychain.add","params":{"account":"canary","service":"com.vphone.research","password":"x"}}' \
  http://127.0.0.1:8765/v1/rpc
```

Run twice against a freshly booted `codex-pentest-smoke-1115` (iOS 27.2.1),
both times capturing exactly these two lines at the moment of the failed
`keychain.add`:

```
com.apple.securityd/thread-local-client-debug  vphoned  notice  SecSecurityClientGet new thread!
com.apple.securityd/SecError  securityd  notice  serverxpc: client vphoned-555549448c19fbdc96533b0da89428957827ba60 is not eligible
```

That `"<name>-<hex>" is not eligible` message is logged by
`SecTaskIsEligiblePlatformBinary` in Apple's `Security` project
(`OSX/sec/ipc/server_security_helpers.m` —
[source mirror](https://git.saurik.com/apple/security.git/blob/HEAD:/OSX/sec/ipc/server_security_helpers.m)),
the gate `securityd`'s serverxpc layer runs before honoring a client's
keychain request. It checks the calling process's signing identifier against
an allow-list and, separately, whether its code signature carries the
platform-binary flag; debug/RC builds of securityd skip the check, release
builds do not. `vphoned` is ad hoc signed (per `AGENTS.md`, "the bundle and
CLI have no private entitlements" beyond what's in
`VPhoneDaemon.entitlements`) and is therefore not a platform binary in the
code-signature sense, regardless of which entitlements its plist claims
(`platform-application`, `keychain-access-groups: ["*", ...]`,
`com.apple.private.system-keychain` are all present and all irrelevant to
this specific check). This is why an explicit, genuinely-entitled access
group (`apple`, tested above) makes no difference, and why `keychain.list`
sees 0 Security-accessible items too: every `vphoned`-initiated keychain
operation hits this same gate before reaching `SecItemAdd`/
`SecItemCopyMatching`'s own logic, independent of the parameters passed in.

This reframes the limitation: it is not a parameter problem, not a missing
access group, not an OpenSEP/AppleSEPKeyStore issue (ruled out above), and
not something `GuestKeychain.swift`/`IcliKit` can route around with a
different query. It is `securityd` refusing `vphoned`'s code identity itself.
A real fix would need `vphoned` to carry the platform-binary code-signature
flag (not just an entitlement claiming to be one) — likely an AMFI-level
allowlist addition akin to the existing `vphone-escalator` cdhash allowlist
for `vphone-vm`, but for `vphoned`'s own cdhash, or building/signing
`vphoned` so it legitimately carries `CS_PLATFORM_BINARY`. Neither is
attempted here; this section only establishes the mechanism. Frida's
`SecItemAdd`/`SecItemDelete` calls succeed because they run inside the
*target app's* process, whose own code identity is whatever securityd
already trusts for that app, not vphoned's.
