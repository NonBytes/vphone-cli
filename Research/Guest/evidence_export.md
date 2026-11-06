# Evidence Export

Diagnostics → Evidence Export opens a local case packaging window in the VM
process. It uses existing guest RPCs; no new daemon capability, entitlement,
firmware patch, external tool or network upload is introduced.

## Collection and provenance

Select an installed app (or guest only), add a title and test notes, and attach
files explicitly using the file picker. Logs, crash reports, sandbox reports,
deep-link workspaces and PCAP files are collected through their existing panels
and then imported here. This window does not start logging, traffic capture,
Frida or keychain reads, and does not silently collect other windows' state.

Capture Guest Screenshot requests one JPEG through `screen.screenshot`.
Choose Script for Hash records SHA-256 of the chosen local file, never its
contents or original filename/path. This identifies selected bytes, not proof
that Frida executed them. Imported attachments are not verified as belonging
to the selected app, guest or test interval.

Prepare Preview refreshes the app list to capture installed version/build,
reads the allowlisted guest version fields from `device.info`, and records the
running Core bundle version/build and review timestamp. Device identifiers,
host name, original local filenames and source paths are omitted. The context
is an annotated UTF-8 text representation, not a strict JSON contract after
redaction. A missing guest build field remains absent rather than inferred.

## Review and redaction

Text redaction defaults on. Known UTF-8 text extensions (txt, log, json, ips,
crash, csv, md, xml, plist) are treated as text only if decoding succeeds and
there are no NUL characters. Other files are binary originals. Common
credential fields, Authorization/Bearer lines, selected URL credential query
parameters and URL basic credentials are replaced on a best effort basis.
Additional exact secrets can be entered one per line. Replacement values are
never written into the package. Redacted JSON/XML need not remain parseable.

Binary originals default off, including screenshots and PCAP. They require
explicit inclusion because this window cannot redact images, packet payloads,
binary plists or other binary formats. Inspect those files separately before
sharing. The text preview shows the first 256 KiB and clearly labels larger
files; exported text is the complete transformed content. Binary preview shows
size and SHA-256. Redaction does not establish absence of sensitive data.

Changing title, app, notes, redaction settings, script or attachments invalidates
the prepared package. Export writes the immutable bytes shown by the current
review, not freshly reread source files. Closing clears attachments, prepared
bytes, notes, literal secrets and the script hash. No auto-export occurs.

## Files and limits

Export Reviewed Evidence asks for a parent folder and creates a unique
`vphone-evidence-<UUID>` directory, mode 0700. It never merges into an existing
case folder. Evidence and manifest files are created privately with mode 0600.
The manifest records export time and each exported file's name, byte count and
SHA-256 of the actual exported bytes, including redacted bytes. It is an
integrity inventory, not a cryptographic signature or authenticity guarantee.

Source files are opened without following symlinks and must be regular files,
no larger than 32 MiB. Up to 32 attachments / 96 MiB are held in memory; the
package writer caps output at 40 files / 128 MiB. Attachment names are generated
locally rather than copied from untrusted input. Original files remain unchanged.
There is no automatic workspace persistence or cloud destination.

## Validation

`zsh VPhoneExecutable/VPhoneVirtualization/Tests/run-evidence-export-tests.sh`
uses the production model/writer with synthetic guest responses. It verifies
common and literal redaction, restricted guest metadata, app version provenance,
binary exclusion and opt-in, immutable output, stale review rejection after
close, symlink/directory/traversal rejection, private modes and manifest hashes.
CI runs this test. Full bundle build and real UI smoke outcomes are recorded
separately below.

The full VPhone build and regression tests passed. Core
`2.15.2-local.8062000e` was installed and tested on `frida-jb-test` without
changing its boot chain or guest environment. The real UI imported a synthetic
log, captured one guest JPEG, showed the log's Authorization/token values as
`[REDACTED]`, and excluded the screenshot by default. Enabling binary originals
invalidated the prior preview and required Prepare Preview again. The resulting
local export contained context, redacted log, screenshot and manifest. An
independent Swift verifier confirmed all three artifact hashes/sizes, private
folder/file modes, a decodable JPEG, absence of the synthetic secrets in text,
and an unchanged source log. test-vm remains running its previous process;
its binding selects this build for its next start, with no forced restart.
