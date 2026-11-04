# App Logs and Crash Viewer

Open **Diagnostics → App Logs & Crash Viewer…** in the VM window or use the
button near the top of **App Inspector**. Select an app, then use the App Logs
and Crash Reports tabs. Refresh Apps updates registrations; Reload App Scope
re-reads executable metadata and resets the scoped panels. Logs start paused.
Choose Start, Pause, Refresh (one batch while paused), Clear, level/search
filters, row details and Save. Crash Reports provides its existing search,
text viewer, Copy, wrap control, Refresh and single/multiple report export.

## Existing contracts

No new daemon operation or guest helper is added. The viewer composes the
existing Console and Crash Logs panels using `apps.list`, `apps.info`,
`logs.syslog`, `logs.crashes` and `logs.crash`. General Console and Crash Logs
remain available and retain their unscoped behavior. No firmware, guest
environment, proxy, certificate or app state change is required.

The executable basename from fresh `apps.info` supplies the server's process
substring filter. The host then retains only rows with that exact process
name, before applying the in-memory row cap. PIDs are not fixed so an app
relaunch can appear. Executable names are not bundle identities: another app
with the same executable may match. Extensions, system-service events and
stdout/stderr that are not in unified logging are outside this scope. The
viewer does not inject, launch or terminate apps or reveal redacted values.

Log batches last two seconds, with a maximum of 2,000 returned events per
batch and 10,000 retained rows. Gaps between RPC captures can lose events;
this is not a continuous lossless stream or historical log-store query. The
backend's substring match can consume the batch cap with similarly named
processes, even though the host discards those rows. The existing truncated
indicator remains visible. Cancelled capture responses are discarded.
Switching apps pauses the previous model, clears scoped panels and uses a
generation check to ignore stale executable responses. Closing pauses logs.

## Crash identity

`logs.crashes {bundle_id}` filters filename candidates by bundle ID or app
executable name. This is a heuristic; system-wide Jetsam reports and reports
with unrelated filenames may be absent. Selection fetches report text on
demand through `logs.crash`. The viewer displays a reported bundle ID from
an IPS JSON header/body (`bundleID`, `bundleInfo.CFBundleIdentifier`) or the
legacy Identifier field. It highlights mismatches and labels missing identity
as a filename candidate. Report metadata is evidence supplied by that report,
not an authentication check. No symbolication or causal diagnosis is implied.

Identity parsing is bounded to a 65,536-character prefix for headers/legacy
fields and 4 MiB for full JSON bodies. Existing text-size, truncation and JSON
layout handling remain in place. Copy and Export preserve the raw returned
report, not the formatted display. No guest report is deleted by this UI.

## Exports and verification

Log and single-report exports write private temporary files and rename them
atomically over the chosen destination. Multiple-report export uses the
existing descriptor-relative unique-file writer. Exports stay local and may
contain sensitive application data; no automatic cloud upload is performed.

Run `zsh VPhoneExecutable/VPhoneVirtualization/Tests/run-app-logs-tests.sh` for
real ConsoleModel fixtures covering exact scope, PID relaunch, explicit Start,
search, row limits, cancelled responses, general Console compatibility, and
crash identity/raw text handling. CI runs these checks. The full VPhone scheme
validates the finished host bundle.

The opt-in `--live doctor-ipad` contract check reads Settings executable
metadata, uses a unique empty log process filter, creates one uniquely named
synthetic IPS fixture, verifies scoped list/read/identity, then removes only
that fixture. It does not launch or crash an installed app, read customer log
events, or inspect existing crash contents. This is API-contract evidence;
it does not prove live event generation or GUI interaction.
