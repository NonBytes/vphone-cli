# Sandbox Diff

Apps > App Browser > select one app > App Inspector (Command-I) > Data
Container > Sandbox Diff. Capture Baseline, exercise the app, then Scan &
Compare. Replace Baseline clears the previous comparison only after the new
capture succeeds. A failed capture leaves the last successful evidence visible
with its date. Closing/cancelling invalidates pending host results; the bounded
guest scan may finish in the background. It does not stop or modify the app.

Scope is the selected app's UUID data container, resolved afresh from the
existing apps.info contract. App Groups, the app bundle, keychain inspection
and structured database/plist diffs are excluded. SQLite, WAL, SHM, plist and
other files are compared as bytes. A current app version/build and container
check after scanning rejects a reinstall/update that happened during capture.

## Capture and transport

The signed, unentitled iOS helper `vphone-guest-sandbox` is staged in the
Core Bundle's guest-resources. Each capture uses the existing guestTool upload
and script.eval/proc.run transport. No new RPC/HTTP route, listener, interpreter,
Homebrew dependency, guest-environment installation or firmware patch is added.
The public helper accepts one bounded JSON identity argument; it has no write
or arbitrary-execution operation.

Only `/private/var/mobile/Containers/Data/Application/<UUID>` roots are
admitted; `/var/...` is normalized to that spelling. The helper opens the
application-container parent and the UUID child with directory/no-follow flags,
checks F_GETPATH against the selected root, and checks the root's device/inode
again at completion. Traversal is descriptor-relative with fstatat/openat and
O_NOFOLLOW. Symbolic links record their target text but are never traversed.
Regular files are rechecked before/after hashing and against the directory
entry afterward; changed metadata discards the hash. Directory changes or
unreadable subtrees make enumeration incomplete. Special files (FIFO, socket,
device) are not read. Opens and reads are content-read-only; normal filesystem
access-time bookkeeping may still occur.

Capture defaults: 2,001 entries including root, depth 32, 32 MiB per file,
128 MiB total hashing and an eight-second scan budget. Hashing streams in
64 KiB chunks. A snapshot is capped at 2 MiB encoded. Time checks are monotonic
between filesystem operations; the existing 20-second guestTool timeout also
applies. Slow filesystem calls can still outlast an individual time check.

These are live, sequential observations, not APFS snapshots or a transactionally
consistent database backup. File changes while the scanner reads them are
reported when detected; no claim of an atomic tree or app quiescence is made.

## Evidence and comparisons

Snapshots contain formatVersion 1, capture start/end Dates (Foundation JSON
seconds since 2001-01-01 UTC), app identity/version/build, canonical root,
machine ID, enumeration status/notes and sorted entries. Entries contain
relative paths, type, regular-file size, nanosecond modification time (Unix
epoch), mode/ownership, SHA-256, symlink target and any per-path error. File
contents are never retained or exported. Root is represented by `.`.

The machine ID is SHA-256 of the host VM's ECID and canonical config location.
It keeps raw host paths/ECID out of reports while separating machines. Moving
the VM, changing its identity, or reinstalling the app into another container
requires a new baseline. App version/build changes between captures are allowed
and remain visible in each capture's metadata.

Only verified entries can be classified as unchanged. A missing path is added
only if baseline enumeration was complete, or removed only if current
enumeration was complete. Unverified content, incomplete coverage or read
errors yield Uncertain. Directory mtimes are excluded from metadata diffs
to avoid repeating child insert/delete events; directory mode/ownership changes
are included. Symlink target changes and file/directory replacements are content/
type changes. Directory/file hashes are not inferred from timestamps or size.

Baselines stay in memory until explicitly saved. Save Baseline writes a snapshot;
Save Diff writes both snapshots and their changes. Export is local, atomic and
mode 0600 from temporary-file creation. Imported JSON is not authenticated or
signed evidence. Import is bounded to 2 MiB, requires a regular non-symlink file,
and rejects malformed schemas, duplicate/escaping paths and a different machine,
app or data container. No baseline/report is committed or sent to an external
service. Show in Files is available for current regular files/directories.

## Verification

```sh
zsh VPhoneExecutable/VPhoneVirtualization/Tests/run-sandbox-diff-tests.sh
# Explicit existing running test VM; synthetic data only, removed afterward:
zsh VPhoneExecutable/VPhoneVirtualization/Tests/run-sandbox-diff-tests.sh --live doctor-ipad
```

Local tests exercise actual filesystem traversal and SHA-256, same-size content
edits with restored mtime, add/remove/type/permission changes, regular file
stability, symlink escape/broken links, FIFO skipping, entry/depth/hash limits,
uncertain missing paths, private atomic baseline export/import, JSON round trips,
duplicate/escaping paths and machine/root validation. CI runs the local suite.
Out-of-range file timestamps are handled as unverified metadata rather than
overflowing the nanosecond conversion; the local suite covers both integer
extremes and invalid fractions.

The signed scanner's live guest fixture passed in doctor-ipad:
capture, same-size edit, add/remove, symlink no-follow and comparison. A fresh
synthetic UUID directory and a uniquely named temporary helper were used and
removed; no registered app's existing data, Frida token, guest environment or
kernel was changed. UI checks on a real selected app remain separate from this
scanner/transport test.

The final local suite, synthetic guest smoke, full Debug VPhone build, bundle
admission, signatures and Launchpad preflight passed. Core
2.15.0-local.70fe2ccd is installed and doctor-ipad is bound to it for its next
start. The existing running VM and default Core (2.15.0-local.a8648fd3) were
left in place. The new UI requires Stop/Start to load; no live UI validation or
scan of a registered app's existing data was claimed by these fixture tests.
