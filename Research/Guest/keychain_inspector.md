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

### Checked whether an existing "debug/RC build" bypass applies (2026-11-15) — inconclusive, blocked by read-only rootfs

Public mirrors of Apple's `Security` project note that `securityd`'s
eligibility check is skipped on debug/RC builds. Pulled the guest's real
`/usr/libexec/securityd` (4,217,344 bytes, arm64e) over the automation API —
no guest shell needed:

```sh
vphone-cli vm launch codex-pentest-smoke-1115 --api-listen 127.0.0.1:8765
curl -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"method":"files.find","params":{"root":"/usr/libexec","pattern":"securityd"}}' \
  http://127.0.0.1:8765/v1/rpc
curl -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"method":"files.read","params":{"path":"/usr/libexec/securityd","binary":true,"limit":4300000}}' \
  http://127.0.0.1:8765/v1/rpc   # base64 content, decode locally
```

`strings` on the pulled binary turned up, alongside the "is not eligible" /
"is eligible platform binary" os_log strings themselves: `_isAppleInternal`,
`hasIsAppleInternal`, `setIsAppleInternal:`, the ObjC type encoding
`{?="isAppleInternal"b1}`, and imports of `_os_variant_has_internal_content`
/ `_os_variant_has_internal_ui`. This is consistent with (not proven to be)
the debug/RC bypass: a client that reads as "AppleInternal" may skip the
eligibility gate entirely.

The cheapest test of that — `files.mkdir` for `/AppleInternal` at the guest
root, the conventional on-disk marker `os_variant_has_internal_content`-style
checks look for — was refused: **`/` is the sealed, read-only APFS system
volume** (`NSCocoaErrorDomain Code=642` / `EROFS`) on this un-bootstrapped
VM, so nothing can be written there without first remounting it, which on
this project's tooling means installing the roothide bootstrap (`Apps >
Install Bootstrap…`, see `Documents/en/machines/package-environment.md`) —
untested here. `r2 aaa` on the pulled arm64e binary found the
`os_variant_has_internal_content` import stub but could not resolve its
callers (PAC-wrapped arm64e stubs commonly defeat naive xref analysis in
radare2; no arm64e-aware disassembler was tried), so it is not yet confirmed
that this function is what the eligibility check actually reads, only that
it is imported and thematically adjacent to the log strings found.

Next steps if this is picked back up: (1) install the roothide bootstrap on
a throwaway VM to get a writable `/`, create `/AppleInternal`, `services.kickstart`
(`force: true`) `com.apple.securityd`, and retest `keychain.add` — cheap and
conclusive either way; (2) if that doesn't change the result, disassemble the
actual call site with the project's own `ARM64Disassembler`
(`libcapstone-spm`, already arm64-aware and used throughout `FirmwarePatcher`)
instead of bare r2, since Capstone handles the PAC instruction forms this
binary uses where r2's default analysis did not.

### Option A is a dead end: the system volume stays sealed even with roothide (2026-11-15)

Ran step (1) above. `bootstrap.install {"layout":"roothide"}` over the
automation API installs Irisin fully scripted (no GUI needed — this is the
same call `Apps > Install Bootstrap…` makes):

```sh
curl -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"method":"bootstrap.install","params":{"layout":"roothide"}}' \
  http://127.0.0.1:8765/v1/rpc
```

It created a `jbroot` at
`/private/var/containers/Bundle/Application/.jbroot-<id>` and registered
Irisin — but retrying `files.mkdir` for `/AppleInternal` afterward failed
with the identical `EROFS` as before. This is expected once you know how
roothide works: it is a **per-process root redirection** (a kernel hook that
makes jailbroken processes see a translated jbroot tree), not a remount of
the real `/`. The actual iOS system volume stays the sealed, read-only APFS
volume it always is — roothide's entire design point is to jailbreak
*without* unsealing it, unlike old-style "rootful" jailbreaks. `vphoned`
talks to the real, unredirected `/`, so nothing changes for it.

So "just write a marker file and kickstart the daemon" (Option A as scoped)
cannot work on this project's jailbreak, with or without bootstrap — not
because of a missing step, but because the system volume is cryptographically
sealed and no in-guest write ever reaches it. The only place this project
modifies sealed system content at all is the **CFW pipeline**
(`vphone-cli cfw install`, host-mount, VM must be off — see `AGENTS.md`'s
"Firmware Mode" and `VPhoneExecutable/VPhoneCommand/FirmwarePatcher`), which
patches the restore image before the seal is computed. If `/AppleInternal`
or an `os_variant_has_internal_content` override is ever worth pursuing, it
has to go through that pipeline (a new `cfw` patch target), not through a
live `files.mkdir`+`services.kickstart` call — which folds this into Option B
(binary-patch securityd) rather than being a separate, lighter option.

### Option B: the exact patch site, found and verified (2026-11-15)

Pulled `/usr/libexec/securityd` again the same way (`files.find` + `files.read`
over the automation API) and disassembled it with Capstone in a throwaway
venv (`python3 -m venv`, `pip install capstone`, outside this repo, per the
same "stand a tool up in a throwaway environment" rule `AGENTS.md` gives for
keystone — nothing added to the repo or to system Python). String-anchored on
the two os_log format strings from the live log capture above
(`"serverxpc: client %@ is not eligible"` at VA `0x100308d4f`, `"client %@ is
eligible platform binary"` at VA `0x100308d29`, both in `__TEXT,__oslogstring`)
and found their `adrp`/`add` cross-references — both inside the same function
at `0x10008928c`, 0x492 bytes apart:

```
0x1000893c4: adrp x3, #0x100308000 ; add x3, x3, #0xd29   ; "...eligible platform binary"
0x1000895b0: adrp x3, #0x100308000 ; add x3, x3, #0xd4f   ; "...is not eligible"
```

This function (unnamed in the symbol table — release `securityd` strips it,
so it was never resolved by name, only by this xref, matching the "string
anchors, ADRP+ADD xrefs" rule in `AGENTS.md`'s kernel guardrails applied to a
userspace binary) takes `(task, identifierList)`. Tracing it end to end:

1. It masks the task's codesign flags (`csops`-style) and compares against
   `CS_VALID | CS_PLATFORM_BINARY` (`0x4000001`). If that matches — which it
   does for `vphoned`, whose jailbroken AMFI evidently grants
   `CS_PLATFORM_BINARY` for its `platform-application` entitlement even
   though it's ad hoc signed — it fetches the task's computed signing
   identifier (this is where `"vphoned-555549448c19fbdc96533b0da89428957827ba60"`
   comes from: `<process name>-<hash>`, the fallback identity for a process
   with no proper Team-ID.BundleID). **So the earlier theory in this file —
   that `vphoned` fails the platform-binary check itself — was wrong**; it
   passes that part.
2. If `identifierList` (the second argument, the serverxpc caller's allowed
   identifiers for this particular keychain operation) is `NULL`, the
   function returns eligible unconditionally.
3. If it's non-`NULL` (our case), it calls into a membership-search function
   at `0x100279c9c`, which writes a one-byte result into a stack-passed
   result struct at offset `+0x18`. That byte is what decides which of the
   two log strings to print — and, critically, it is read a **second time**
   after the log call to produce the actual return value:
   ```
   0x1000895cc: bl #0x100279a6c        ; release
   0x1000895d0: mov x0, x19
   0x1000895d4: bl #0x10027708c        ; release (the signing identifier)
   0x1000895d8: ldr x8, [sp, #0x48]    ; reload the result struct pointer
   0x1000895dc: ldrb w19, [x8, #0x18]  ; <-- the real eligibility byte
   0x1000895e0: add x0, sp, #0x40
   0x1000895e4: mov w1, #8
   0x1000895e8: bl #0x100278bac
   0x1000895ec: b #0x1000894f0         ; -> `and w0, w19, #1` ; … ; `retab`
   ```
   `vphoned`'s computed identifier (`vphoned-<hash>`) is never a member of
   whatever list `0x100279c9c` searches, so this byte comes back `0`, and the
   function returns `false` — for every keychain RPC `vphoned` makes,
   regardless of access group, matching everything observed.

**The patch:** replace `ldrb w19, [x8, #0x18]` at VA `0x1000895dc` (file
offset `0x895dc` in the pulled 4,217,344-byte binary) with `mov w19, #1`
(`MOVZ W19, #1`, hand-encoded `0x52800033` / little-endian `33 00 80 52`,
same four bytes, no length change, no cave). Verified in the throwaway venv:
Capstone round-trips the patched bytes back to `mov w19, #1`; the register
it writes is the same one the unconditional branch at `0x1000895ec` carries
into `and w0, w19, #1`, the function's actual return-value computation
(confirmed by resolving that branch's target, not by assuming straight-line
flow — the `and` is physically earlier in the binary than the `ldrb`). This
only affects the branch reached when the caller passed a non-`NULL`
identifier list (step 2 above is untouched, and already returns eligible).

### Shipped as `system-securityd-exp-keychain_eligibility` (2026-11-15)

The patch above is now a real CFW patch, following `Skills/authoring-patch-sets/SKILL.md`:

- `VPhoneExecutable/VPhoneCommand/FirmwarePatcher/CustomFirmware/ExecutablePatches/Securityd/CustomFirmwareSecurityd.swift`
  (`CustomFirmwareSecuritydPatcher`) — written against `ARM64Disassembler`/
  `ARM64Encoder`/`MachOParser`, not the hand-encoded word above (that was this
  file's own throwaway verification only): it string-anchors on both os_log
  literals in `__TEXT,__cstring`/`__TEXT,__oslogstring`, resolves each one's
  ADRP+ADD xref, scans forward from the "not eligible" xref for `ldrb w?,
  [x?, #0x18]`, resolves the following unconditional branch's target, and
  requires that target reach `and w0, <the ldrb's register>, #1` before
  writing `mov w?, #1` (`ARM64Encoder.encodeMovzW`) over the `ldrb`. A second
  run recognizes `mov w?, #1` already in place as its own output, same as the
  other `ExecutablePatches`.
- `vphone-cli cfw patch-securityd <binary>` (`VPhoneCustomFirmwareMachOVerbsCommand.swift`),
  wired into `cfw install`/`cfw update-environment` via
  `machO(FirmwareGuestSystemPatchSet.securitydKeychainEligibility, path:
  "usr/libexec/securityd", verbs: ["patch-securityd"], codeIdentifier:
  "com.apple.securityd", preserveEntitlements: true)` in
  `VPhoneCustomFirmwareInstaller.swift` — the installer's own `patchMachO`
  re-signs the whole binary afterward, so this verb's own
  `reattestsCodeSignature` stays `false` by default, same as every other verb
  there.
- Declared in `FirmwareGuestSystemPatchSet.manifest` with
  `target: .guestExecutable(path: "/usr/libexec/securityd")`, and left off by
  default everywhere (added to `FirmwarePatchSetCatalog.manualOnlyPatches`,
  which every shipped preset but `experimental` blocks with) because it
  disables the identifier-allowlist half of this eligibility check
  *system-wide*, for every client and identifier list securityd checks this
  way, not only vphoned's keychain calls. `vphone-cli fw set-patches <vm>
  --allow system-securityd-exp-keychain_eligibility` turns it on for one VM.
- Tested against a synthetic Mach-O fixture (no `ipsws/ref_extract` binary
  for securityd), in `CustomFirmwareSecuritydTests.swift`: site discovery,
  the four refusal shapes (string missing either way, branch not reaching
  `and w0`, branch target out of bounds), patching, idempotence, dry run, and
  that re-attestation without a code signature correctly refuses rather than
  silently no-op'ing. `FirmwarePatchSetCatalogTests` passes with the new
  declaration in place (naming, uniqueness, preset-plist/Swift-copy parity).

### Verified live against the real guest (2026-11-15)

`sudo cfw update-environment codex-pentest-smoke-1115` (the privileged
host-mount step this session cannot run non-interactively; the user ran it)
applied the patch to the real binary, and its own log lines match the
hand-found addresses exactly:

```
Found "serverxpc: client %@ is not eligible" at va:0x100308D4F
Found string ref at 0x895B0
Found eligibility byte read at 0x1000895DC: ldrb w19, [x8, #0x18]
[+] Patched at 0x895DC: mov w19, #1
```

Rebuilding `vphone-vm` changed its own cdhash, so it needed a fresh AMFI
allow (`vphone-escalator allow <path-to-vphone-vm>`) before it would launch —
unrelated to this patch, just the usual consequence of a local rebuild.

With the patch live, over the automation API against the booted guest:

```json
// keychain.add {"account":"canary-postpatch-1","service":"com.vphone.research.postpatch","password":"canary-secret"}
{"result":{"group":"*","ok":true,"status":0}}

// keychain.list {"class":"genp"} — diag
"Security: 54 accessible items", "Database: 55 protected metadata rows"
// (was "Security: 0 accessible items" / 58 protected rows before this patch)

// keychain.get for the same item
{"result":{"ok":true,"value":"canary-secret"}}
```

Add, list (shown with `"source": "security"`, not just protected metadata)
and get all round-trip correctly. The canary item was then deleted via
`keychain.delete` to leave the guest clean. This closes the investigation:
`keychain.add`/`.update`/`.list` work on iOS 27.2+ once
`system-securityd-exp-keychain_eligibility` is turned on for a VM.

## Automated Security Risk Assessment & Issue Summary (OWASP MASVS)

To streamline pentesting and security audits, Keychain Inspector includes an automated
security heuristic analyzer evaluating items against OWASP MASVS (MASVS-STORAGE-1 and
MASVS-STORAGE-2):

1. **Security Audit Summary Bar**:
   - Displays real-time risk breakdown: `[X High Risk]`, `[Y Medium Risk]`, `[Z Best Practice]`.
   - **Issues Only Toggle**: Filters the table instantly to show only insecure or non-compliant rows.
   - **Add All Issues to MASVS Findings**: Dispatches all identified High and Medium risk items into `VPhoneMASVSFindingStore` in a single click, ready for executive compliance reporting.

2. **Risk Classification Heuristics**:
   - **High Risk**:
     - `AccessibleAlways` or `AccessibleAlwaysThisDeviceOnly`: Deprecated since iOS 12. Keys remain accessible even when the device is locked, allowing unauthorized extraction if filesystem access or physical dump occurs.
   - **Medium Risk**:
     - Missing `ThisDeviceOnly` protection on sensitive items (e.g. `AccessibleAfterFirstUnlock`, `AccessibleWhenUnlocked`): Items may sync across iCloud Keychain or be restored from unencrypted iTunes/Finder backups.
     - Sensitive token detection (account or service matching `token`, `jwt`, `secret`, `bearer`, `auth`, `refresh`, `password`, `key`) stored without hardware biometric access control (`kSecAccessControlBiometryAny` / Secure Enclave).
   - **Best Practice (Low/Secure)**:
     - Items configured with `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` or bound to user presence/biometrics with Secure Enclave.

