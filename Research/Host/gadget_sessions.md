# Gadget sessions in Launchpad Pentest Tools

Pentest Tools → Local IPA Tools → Frida Session → **Gadget**. The entry remains
available when guest RPC or Apps API is unavailable; Gadget speaks its own TCP
protocol. The Frida Server mode retains the managed server's token lookup and
app Spawn/Attach behavior. This change does not start a server, boot a VM,
install/launch an app, configure a forward or update the guest environment.

1. Patch an unencrypted IPA with Gadget, install it in the test VM, and launch
   it separately. Use a matching client/Gadget version; the client is 17.25.2.
2. Enter its reachable host:port (or [IPv6]:port) and authentication token.
   Guest loopback requires a tunnel that reaches loopback. Ordinary VM network
   forwards connect to the guest network address and require explicit
   guest-network listening in the IPA config. No network setting changes here.
3. Test Connection authenticates and enumerates processes only. It requires
   exactly one process named Gadget, reports its PID, and disconnects without
   attaching, loading a script, resuming or killing any process.
4. Attach Gadget repeats that check and attaches only to its returned PID.
   Gadget mode offers no Spawn or arbitrary app/PID selection. A wrong server,
   empty/multiple process list, auth error, unreachable endpoint or timeout
   fails explicitly. A process name is a protocol shape check, not a trusted
   identity proof for an untrusted remote endpoint.
5. Choose a local UTF-8 JS file (maximum 512 KiB), load/replace it, review console
   output, save the log, and Detach. A selected script may also be loaded on
   Attach. Frida 17 ObjC/Swift bridges must be bundled in the script. Closing
   detaches and clears the token field; the target remains running.

## Credentials and persistence

Save Connection explicitly stores a generic-password item in macOS Keychain,
scoped by SHA-256 of the canonical VM directory and endpoint. It is device-only,
available when unlocked, with no synchronizable attribute. The remembered
endpoint and selected mode are nonsecret UserDefaults entries scoped to the
same VM. Load Saved Token is explicit, never done merely by opening the panel.
Editing the endpoint clears the in-memory token; the old saved item is retained.
Forget Saved Token deletes only this VM/endpoint's item. No automatic connect,
script replay or migration between machines, renamed paths or endpoints.

Token and script travel over the native client's socket stdin, never command
arguments. Helper output messages are scrubbed for the current token (including
its JSON-escaped spelling) before console/error display. Saved logs use the
existing atomic private report writer, mode 0600. Console data remains bounded
to 1 MiB. Script output can contain other sensitive data; this scrubber does not
claim general secret detection.

The app's Keychain access remains governed by macOS code identity. A local ad
hoc test build and a signed distribution can be treated differently by macOS;
no access control or signature check is bypassed. The installed signed
Launchpad is unchanged because its original signing key is unavailable here.

## Ownership and verification

The UI/model and credential store are Launchpad-owned. The shared native Frida
client adds backward-compatible `gadget` and `probe` start modes; existing
spawn/attach commands are unchanged. Core public CLI/API/layout are unchanged.

On 2026-11-08 (Asia/Bangkok):

- Launchpad and full VPhone builds passed, including bundle admission. The license staging phase now handles a repeated build
  after SwiftPM's read-only license was copied into the output.
- Native lifecycle fixtures verified probe performs no attach/compile/load/
  resume/kill; Gadget attach, script replacement and detach work; enumeration
  errors, multiple processes and a wrong name are refused before attach. All
  existing server spawn/attach/error/EOF cleanup checks passed.
- `zsh VPhoneLaunchpad/Tests/GadgetConnectionTests.sh` checks endpoint validation,
  scope separation and token scrubbing. `--keychain` additionally tested a
  uniquely scoped disposable save/read/delete round trip on this Mac. CI skips
  real Keychain writes.
- Real UI smoke used the official macOS Gadget 17.25.2, downloaded with release
  size/SHA-256 verification, inside a self-authored disposable host process on
  127.0.0.1:27044. With frida-jb-test stopped/RPC disconnected, Test Connection
  authenticated without attach, Save/Load Token worked, Attach reported the
  fixture PID, a local console.log script emitted VPHONE_GADGET_SESSION_UI_OK,
  Save Log produced mode 0600 with no fixture token, and Detach succeeded.
  This validates real Gadget protocol/script handling; it does not claim a new
  VM network-route test or instrumentation of a customer's app. The separate
  iOS IPA/Gadget load smoke is in Research/Guest/gadget_patchipa.md.

Reference: [Frida Listen Gadget](https://frida.re/docs/gadget/#listen).

After the smoke, the loopback fixture process was stopped and its exact saved
Keychain item and two test preferences removed using supported macOS tools.
VM bindings/environments and installed bundles were unchanged.
