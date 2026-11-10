# Patch IPA → Install → Launch → Gadget Session

Launchpad → a machine → Actions → Pentest Tools → Local IPA Tools → Patch IPA
with Frida Gadget. After creating a new patched IPA, the same window offers:

1. Select a VM from **Refresh VMs**. The list comes from the running Launchpad's
   same-user control socket across all its configured libraries. A stopped VM
   must be started in Launchpad and the list refreshed; this flow never boots,
   rebinds or updates a machine automatically.
2. **Install Patched IPA** copies the exact artifact into a private workspace,
   computes SHA-256 and compares it with the patch result before any guest
   installation. It checks for an existing Bundle ID; installing over it requires
   explicit Replace existing installation opt-in, reset when the VM/artifact
   changes. Installation uses the existing push and apps.install APIs and
   requires the returned Bundle ID to match. The guest may re-sign the app;
   this is not an installd install-gate test.
3. **Launch App** becomes available only for that installed artifact/VM pair.
   It launches the frozen Bundle ID and requires a positive PID. Locked/screen-
   off guests report their existing API error; unlock/wake separately and retry.
   No app is automatically launched following installation.
4. **Open Gadget Session** transfers endpoint/token in memory to a Session
   window scoped to the selected VM. It refuses to replace an active/busy
   session. Test Connection and Attach remain explicit user actions, as does
   choosing a script. Nothing is attached or replayed automatically.

Changing VM, a VM's reported UDID, or the patched artifact invalidates prior
install/launch state. Generation checks discard late UI results after a reset
or close. A guest installation already requested may finish after the patch
window is closed; closing cannot roll back the guest's install operation and
never causes a later launch. Temporary uploaded IPA paths are cleaned up on
success and failure. Host artifact/config tokens are never included in logs or
patch reports; IPA and log artifacts are private (0600).

## USB transport to guest loopback

The default route uses the macOS system usbmuxd socket and an independently
implemented, bounded plist protocol. It reads no pairing record or private key,
requests no trust/pairing change, and invokes no Homebrew/iproxy process.
ListDevices must return exactly one **USB** device whose serial equals the
selected VM's UDID (case/hyphen normalization only). It never chooses the first
attached device and refuses absent, duplicate or network-only matches. The
production socket peer must be root. Replies validate framing/version/type/tag
and are bounded to 1 MiB with five-second handshake timeouts.

Connect addresses only that device and the Gadget port frozen into the IPA.
A temporary host TCP listener binds 127.0.0.1 on an ephemeral port, relaying
bounded chunks over USB with a maximum of eight connections and backpressure.
Frida still authenticates end-to-end with the IPA's token. No guest network
listener, VM network setting, Core install or guest helper is added. The selected
Core needs only the existing guest app/file APIs for installation/launch; USB
streaming does not pass through Core or rely on a new vphone.sock verb.

The Session window owns the relay after handoff. Closing it, switching to Server
or editing the endpoint closes the relay. Detach retains it for a deliberate
reattach while the window stays open. Keychain Save/Load/Forget is disabled for
this temporary port; it is not persisted as a stable profile. A custom reachable
endpoint can be selected instead if USB is unavailable. Guest-network access
requires the IPA's explicit network-listening option or a separately configured
working forward. No fallback changes network exposure automatically.

Keep the target app running and the guest ready during testing. In the live
smoke, the guest locked/screen turned off and the Gadget session disconnected
while the app still had a PID. A fresh foreground launch restored attachment;
this flow does not override Auto-Lock or app suspension. A PID confirms launch,
not sustained Gadget reachability; Test Connection remains the protocol check.

## Validation (2026-11-08)

- `GadgetDeploymentTests.sh`: two isolated fake VM sockets exercise frozen
  artifact/hash checks, explicit install/update/launch, scope reset, wrong
  returned Bundle ID refusal and in-memory custom-endpoint/token handoff.
  A mock usbmuxd fragments its plist replies, places an unrelated device first,
  checks the exact selected device and network-byte-order port, and exercises
  both direct USB bytes and the real loopback relay. Empty, duplicate and
  network-only matches are refused. All fixture UDIDs are synthetic.
- IPA patch, credential, VM transport and existing pentest-feature regressions
  run alongside the Launchpad product build. CI adds the deployment suite after
  the Launchpad build resolves the pinned archive dependency.
- UI smoke used the self-authored com.vphone.fixture.gadget IPA, official iOS
  Gadget 17.25.2 (release size/SHA-256 verified), pentest-test-vm, Core
  2.15.2-local.8062000e and its existing guest environment. Patch saved a
  24,436,298-byte IPA, SHA-256
  `aca2725b4d712acb91fc97ce8ac391dedc4f596571799bf5ec8fdbe4cf24618f`.
  Install and Launch succeeded; Open Gadget Session created a host loopback
  tunnel to guest port 27043. Test Connection authenticated without attaching,
  and explicit Attach loaded a local console-only script that emitted
  VPHONE_GADGET_SESSION_UI_OK in the VM process (PID 303; PID 382 after restarting
  the fixture for the foreground/detach check). Explicit Detach succeeded.
  The exported log was 0600 and a check against the actual config token found
  no token in it. No customer app was installed, launched or inspected. The
  synthetic app was removed and pentest-test-vm returned to Stopped. During final
  menu verification test-vm was inadvertently started, then stopped again;
  its bindings and guest environment were unchanged.

The signed-app build script also signs Debug's loadable debug dylibs with the
same identity before sealing their containing apps, so hardened-runtime library
validation accepts the actual Debug outputs. The private signing key remains in
macOS Keychain; no P12/private key material is read, exported or tracked.

Protocol references (wire-format research only; no vendored implementation):
[libusbmuxd Connect/ListDevices](https://github.com/libimobiledevice/libusbmuxd/blob/master/src/libusbmuxd.c),
[usbmuxd protocol framing](https://github.com/libimobiledevice/usbmuxd/blob/master/src/usbmuxd-proto.h).

The final build was signed with the original Apple Development identity and
installed over Launchpad with a rollback copy preserved. The app and bundled
Pentest Tools launched from /Applications; deep/strict code verification,
Developer Tools, helper 21 and host readiness passed. The temporary USB listener
was closed and both VMs verified Stopped after testing.

Signing also reuses an already installed helper only after strict validation
against the app's requirement and an exact CodeDirectory hash match. This
preserves its existing timestamped signature when the executable code is
unchanged, avoiding a false helper-update requirement caused only by a new CMS
timestamp. Changed helper code is never reused and still requires the normal
SMJobBless update. The live staged/installed helper bytes were confirmed equal
and helper readiness passed without changing the privileged installation.
