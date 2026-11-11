# Patch IPA with Frida Gadget (VM)

Launchpad → a machine's Pentest Tools → Local IPA Tools → Patch IPA with
Frida Gadget. This host-only action remains available while the VM is stopped
and does not depend on its selected Core Bundle.

Choose an already unencrypted IPA and an iOS Frida Gadget dylib, or explicitly
download an official Gadget release. The download verifies the exact GitHub
release asset's size and SHA-256 digest before bounded native XZ decompression.
The initial suggested version is 17.25.2; use a matching external Frida client.
No Gadget is downloaded merely by opening the window.

Choose a new output path. The tool validates and privately copies both inputs,
extracts one Payload/*.app, adds a strong LC_LOAD_DYLIB referencing
`@executable_path/Frameworks/FridaGadget.dylib`, embeds that dylib and
`FridaGadget.config`, signs code inside-out with Apple's ad hoc signer, verifies
the signatures, and packages a new IPA. Original files remain unchanged.
Existing signed code retains identifier/entitlements when re-signed. No
entitlement, provisioning profile or signing identity is created for a physical
device. Guest installation may re-sign the bundle again.

The patch changes load-command metadata in existing zero header padding only;
there is no instruction patching, code relocation, decryption or automatic
install/launch. ARM64/ARM64e executable slices must each match a Gadget subtype.
Encrypted code, unsupported platforms/architectures, insufficient padding and
an existing Gadget link/file are refused. Rebuild an app you own with header
padding if necessary. Runtime compatibility is separate from successful packing:
guest/kernel restrictions and anti-tamper can still prevent instrumentation.

## Connection and secrets

The default config listens on **guest loopback 127.0.0.1:27043**, requires a
random token, and resumes app startup. Waiting for a client is an explicit
option. Copy the token before closing the window; closing clears it from the
model. It is embedded in the IPA's config, so keep that artifact private.
The optional JSON patch report includes input/output hashes, identity, load
command offsets and nonsecret settings, and omits the token.

Loopback requires a transport that actually reaches guest loopback. An ordinary
VM NAT/tunnel network port forward connects to the guest network address and
therefore requires the explicit guest-network listening option (0.0.0.0).
That option makes the authenticated Gadget endpoint reachable from networks
that can reach the VM. Configure any forward separately; patching never changes
VM network settings. Connect an external matching Frida client to that endpoint
and attach to the Gadget process, for example:

```sh
frida -H 127.0.0.1:27043 --token '<copied-token>' -n Gadget
```

Here the host endpoint presumes a separately configured working transport;
it is not created by the patcher. Frida Tools' Session tab now also offers a
Gadget mode with connection testing, Attach, scripts, console and Keychain
profiles; see Research/Host/gadget_sessions.md. Its Server tab retains
the managed server workflow.

## Implementation and bounds

Production code is owned by `VPhoneLaunchpad/VPhonePentest`: VPhoneGadgetMachO,
VPhoneGadgetArchive, VPhoneGadgetPatcher and VPhoneGadgetPatchWindowController.
The handwritten Xcode target statically links the pinned ArchiveKit/libarchive
package already used elsewhere in the repository. All archive/decompression
code ships in the app; runtime tools are system codesign and ditto. No Python,
Homebrew runtime package, shell interpolation or external patching utility.

ZIP paths and types are inspected before extraction. Absolute/traversal paths,
case/Unicode collisions, duplicate names, hardlinks, special files, encrypted
entries and absolute/parent-relative symlinks are refused. Files are created
exclusively inside a private workspace; symlinks are created last. Bounds:
20,000 paths, depth 64, 2 GiB input/expanded files, 512 MiB executable, 256 MiB
Gadget, 4 MiB plist, and a 15-minute patch deadline. Cancellation takes effect
between signing steps; archive packing can be terminated. Temporary files are
cleaned up; final IPA/report permissions are 0600.

## Validation

Build Launchpad, then run `zsh VPhoneLaunchpad/Tests/GadgetPatchTests.sh`.
Self-authored ARM64 iOS fixtures exercise the full patch/sign/pack/extract path,
unchanged bytes outside load-command changes, encrypted/duplicate/padding
refusal, malformed input, unsafe ZIP paths/symlinks, cancellation, original input
preservation, signature verification and a token-free report. CI runs this
after the Launchpad build, which resolves its pinned static archive dependency.

UI smoke on 2026-11-06: Local IPA Tools was available with pentest-test-vm stopped;
official 17.25.2 Gadget download passed SHA-256 verification and the UI saved a
24,435,127-byte patched fixture with verified ad hoc signatures. No customer app
was patched, launched or inspected for this test. Live results are recorded
below after installing the self-authored fixture through apps.install; that
API re-signs/copies bundles and is not a test of the installd gate.

References: [Frida Gadget configuration](https://frida.re/docs/gadget/),
[Objection iOS patching](https://github.com/sensepost/objection/wiki/Patching-iOS-Applications).
This implements the VM patching workflow natively rather than invoking Objection.

Live smoke: the corrected scene-lifecycle fixture opened frontmost (PID 380)
on pentest-test-vm, iOS 27.0.1 (24A446), and wrote its own result
`{"fixture":"com.vphone.fixture.gadget","gadgetLoaded":true}`. Its patched IPA
SHA-256 was `e94cd0777fb75370ecdbbc1131fd39409c38cfa3ad96e19b3f0d0bbf61782030`.
The first fixture lacked the scene lifecycle required by this SDK/OS and
crashed in UIApplication's scene-adoption check; correcting the test app
resolved that failure. No Frida attach/script execution was claimed by this
smoke. The disposable app/uploaded IPAs were removed and the VM stopped again.
Initial UI verification used the separately built tool app. On 2026-11-08 the
original Apple Development signing identity was confirmed present and usable;
the latest Launchpad was subsequently signed and installed with it.

After a successful patch, Install & Launch now selects a VM, checks the exact
IPA hash, installs/launches explicitly and hands off to Gadget Session. Its
default USB transport reaches guest loopback without a guest network listener;
see Research/Host/gadget_deployment.md.
