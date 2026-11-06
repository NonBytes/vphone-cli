# Export Installed IPA

Launchpad-owned Pentest Tools → App Inspector / App Browser → select one app →
Export Installed IPA. The action is available in the app's context menu and
its inspector. It opens a dedicated window; Choose Destination & Export IPA
starts collection only after a local destination is selected.

## Scope and output

The export contains `Payload/<installed-name>.app` in a ZIP-format `.ipa`.
It copies the installed bundle's regular files and supported symlinks only.
Sandbox data, App Groups, Keychain, external on-demand assets and original
App Store packaging outside the installed bundle are excluded. No application
is launched, terminated, re-signed or decrypted. App binaries and embedded
signatures remain as installed; encrypted executable bytes remain encrypted.
The UI reports the main executable's encryption flag when the guest can read
it and otherwise reports unknown. That flag is not an audit of every nested
framework or extension. Export does not prove reinstallability or physical
device compatibility and does not reconstruct the original submitted IPA.

Executable permission bits are retained using normalized 0644/0755 file modes;
directories use 0755. Guest ownership, set-ID bits, ACLs, xattrs and original
file timestamps are not copied. Payload bytes are not rewritten to normalize
these filesystem attributes. The completed IPA is mode 0600 and its SHA-256
is shown after saving. Nothing is uploaded automatically.

## Transport and consistency

The reader ships with Launchpad as `vphone-guest-export`, built natively for
iOS 17+ without private entitlements. It uses the existing guest files and
script RPCs, so no Core API, firmware patch or daemon update is introduced.
The content-hash helper path is deployed once per export. File reads are
batched, bounded pread ranges (up to 64 ranges / 256 KiB per batch) rather than
whole-file downloads. Argument JSON is limited to 64 KiB. This avoids the old
Core socket's push/pull dependency and the whole-file files.read size limit.

The guest walks a no-follow directory descriptor chain to the selected .app
and uses openat/fstatat without following symlinks for every directory and
regular file. It checks device/inode, size, mode and mtime before and after a
file range. Directory enumeration errors, unsupported special files and
unreadable files fail the export rather than silently omitting content.

The host validates relative paths, uniqueness, canonical case collisions,
parent directory kinds and symlink targets before creating files. Host files
and directories are created exclusively in a private mode-0700 workspace;
symlinks are created only after all regular files have been written. Absolute
and parent-relative symlink targets are refused, not rewritten. This can reject
unusual installed bundles whose links cannot be preserved safely. Additional
host filesystem name collisions also fail instead of merging directories.

Before packing, the host compares a second complete manifest with the first,
refreshes the registered app path/version/build, and validates the downloaded
Info.plist's identity and root executable. This is a live read, not an atomic
snapshot; checks cannot establish that a malicious writer did not alter bytes
while preserving all checked metadata. Normal detected app updates or file
changes fail the job and leave the destination unchanged.

macOS's system ditto packs only the private Payload directory; no shell or
runtime package manager is used. A completed archive is streamed through SHA-256
to a mode-0600 temporary file beside the selected destination, then renamed
atomically. Existing destination files are preserved on failure/cancellation.
Temporary workspaces and partial destination files are removed. Cancel/close
requests cancellation and terminates the packer if active; an in-flight guest
RPC may finish before cancellation is observed. A late save-panel callback
cannot start an export after its window has closed.

Limits: 20,000 entries, 4 MiB manifest JSON, 2 GiB total regular-file contents,
2 GiB + 64 MiB finished archive, depth 64, and a 15-minute operation budget.
No partial-success IPA is offered when these limits or checks fail.

## Validation

`zsh VPhoneLaunchpad/Tests/IPAExportTests.sh` exercises the production reader,
export model and packer against a synthetic installed app. It unpacks the IPA
to verify Payload layout, exact executable bytes, executable bits, empty files
and safe symlinks. It covers multiple read batches, case/path collisions,
escaping symlinks, unsafe read ranges, a file swapped to a symlink, cancellation,
app mutation, preservation of an existing destination, private output mode and
cleanup. The synthetic encrypted flag remains reported while file bytes remain
unchanged. CI runs this fixture along with the other Launchpad tool tests.

The full Launchpad build passed. Live UI smoke on frida-jb-test exported
Calculator (`com.apple.calculator`) without launching it. The output was
2,297,775 bytes, mode 0600, SHA-256
`644e73f17bf6c7571792cc895d854cc59d0b98eb6f2d62bdf7a874d205560017`.
An independent verifier unpacked the IPA, checked its identity/layout and hash,
and compared its executable byte-for-byte with the installed guest file read
through files.read rather than the new reader helper. No customer app or app
data was read for this smoke. Local UI ran from the separately built Pentest
app; replacing installed Launchpad remains subject to its original signing key.
