# Deep Link Tester

Open **Diagnostics → Deep Link Tester…**, or its button in App Inspector.
Select an installed app and refresh the declared schemes if needed. The panel
uses existing `apps.list`, `apps.url_schemes` and targeted `apps.open_url`
operations. No guest helper, daemon method, entitlement or firmware change is
added. The original App Browser Open URL sheet remains available.

## Editor and execution

Choose a declared scheme or enter a complete raw URL. Raw input is sent to the
guest without rebuilding or trimming it. Validation limits it to 8 KiB, requires
an ASCII URI scheme, and rejects literal control characters. Deliberately
malformed percent sequences and percent-encoded payloads remain possible in
raw mode. The guest/OS URL parser may still normalize or reject that input.
Manual URLs are permitted even when the scheme was not declared by the app.

The optional builder appends up to 32 query parameters to a parseable base URL.
Names and values use strict UTF-8 percent encoding, including `+`, spaces,
`&`, `=` and Unicode. Duplicate names, empty names and empty values are
preserved. Existing query text and fragments are retained by URLComponents;
this explicit builder operation can normalize the base URL, unlike raw mode.
Applying parameters updates the editor and clears the builder rows, preventing
an accidental second append. The builder does not support bare flag parameters
without `=`; those can be written directly in the raw URL.

Open URL in Selected App submits exactly one request. It may launch the app
and trigger whatever action or network traffic the app associates with that
URL. An accepted request is not verification of the destination route,
frontmost application, authentication state or Universal Link association.
HTTP(S) testing through a forced app target does not establish the behavior of
an ordinary Universal Link tap. Observe the app to assess the result.

## Cases and history

Save Case captures a name, URL, notes, bundle identifier and the app name,
version/build from the last refreshed app list. Up to 100 cases are retained.
Each executed request records a timestamp, elapsed time, original target/URL,
accepted/failed outcome and response summary. History retains the most recent
100 runs. A response arriving after window close still records the request
that was actually sent, using its original target. Changing apps does not
relabel an in-flight request.

Load Selected Case and Load Selected Run into Editor never execute a URL.
A missing target app is reported without silently substituting another app.
To repeat a case, load it and explicitly choose Open URL. The selected app's
current list metadata is captured for the new run. No case or history entry
executes automatically on import, refresh, selection or window open.

## Local persistence

Cases/history stay in memory until Save Workspace is chosen. Saving writes a
private (0600), atomically replaced JSON file for reuse across sessions.
URLs, notes and error summaries can contain tokens or sensitive payloads;
the archive preserves them for reproducibility and does not redact them.
Review before sharing. Nothing is uploaded automatically.

Open Workspace replaces the in-memory archive after explicit file selection;
the UI asks for confirmation first if it already contains cases/history.
Cancelling the file panel keeps the current archive. Schema version, UUIDs,
entry counts, field lengths and URLs are validated. Files are limited to
4 MiB and must be regular non-symlink files. Loading never opens links or
modifies existing workspace files. Save first to retain unsaved data.

## Validation

`zsh VPhoneExecutable/VPhoneVirtualization/Tests/run-deep-link-tester-tests.sh`
exercises the real model with synthetic guest responses: raw payload
preservation, encoding/duplicate/empty parameters, invalid inputs, case save
and load without execution, accepted/refused request history, original-target
provenance, bounded archive validation, symlink rejection and private export.
CI runs these fixtures. The full VPhone build validates the finished bundle.
GUI and live dispatch checks are recorded separately from synthetic results.

The initial GUI smoke test on test-vm opened only `prefs:` in Settings.
The guest accepted the request and history recorded its target, installed
version/build and elapsed time. Loading that run into the editor left the
history at one request. A synthetic builder parameter containing `+`, `&`,
spaces and Thai text produced the expected percent-encoded preview without
executing it. Save Workspace produced a 0600 JSON file with exactly one case
and one accepted run, preserving the original `prefs:` URL. The archive was
validated again from disk. This is dispatch evidence, not route verification.

On macOS 27.2 the automatic TabView navigation was placed in toolbar overflow.
Cases/History navigation now uses a segmented picker directly in the content
so both views remain discoverable. The navigation update passed the full
VPhone build and was installed as `2.15.2-local.95e4e930` on test-vm.
The final GUI check confirmed both segments are visible, imported the saved
workspace with one case and one run, and loaded the Settings case into the
editor without adding a run. Switching to Run History still showed exactly
the original accepted request. The VM remains running on this build; its
boot chain and guest environment were not updated.
