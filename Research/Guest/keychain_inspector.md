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

On 2026-11-05 the running frida-jb-test VM's existing `keychain.list` reported
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
