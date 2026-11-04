# Guest Frida server manager

Open **Features > Frida Server…** in an iOS/iPadOS VM. Choose a release from the
dropdown or use Other version, then Download & Install. Installation does not start
the server. Start creates a new random token and listens on the guest's port
27042. Copy command includes the token for a Mac Frida client. Use matching
client/server versions when possible. Stop terminates only the managed PID
whose executable path matches this installation. Closing the window keeps it
running; reboot does not start it automatically.

## Distribution and transport

GitHub REST GET `/repos/frida/frida/releases/latest` or `/releases/tags/<version>`
provides the release metadata. The selected asset is
`frida_<version>_iphoneos-arm.deb`, the upstream rootful iOS package with arm64
and arm64e slices. The similarly named iphoneos-arm64 package uses a rootless
layout and is not selected. The latest release observed during implementation
was 17.25.2, which does not publish a standalone ios-arm64 server XZ asset.

The public API needs no token. Non-200 responses, unavailable assets, invalid
version strings, missing SHA-256 metadata, unexpected download paths, wrong
size/digest, extraction errors and invalid binary signatures abort installation.
GitHub rate limits still apply. Only fixed archive members are streamed into a
unique temporary directory using macOS tar; package scripts and LaunchDaemons
are never installed or run. Temporary download/extraction files are removed.
There is no Homebrew runtime dependency and no Python added to the project.

The host uploads the server and agent into `/private/var/vphone-frida/usr/`.
The guest-only `vphone-guest-frida` helper uses the existing `script.eval` /
`proc.run` transport. It accepts only preparation commands, status, start and stop and has no new
private entitlements. It checks directory ownership and rejects live upgrades.
A version marker is written after uploads complete; a partial installation is
not ready to start. Server and agent retain upstream code signatures.

The helper starts one detached server with stdout/stderr redirected to a
private log and records its PID. Every operation checks PID ownership by
executable path to avoid signalling an unrelated process after PID reuse.
Status returns the last 8 KB of output. The token and state files are mode 0600,
inside a mode 0700 directory. The listener binds guest interfaces and requires
a fresh token on each start; the UI states this before starting. NAT/bridged
reachability depends on the VM network. Tokens are runtime state, never source
or committed configuration. Frida itself is downloaded at runtime, not vendored
in the Core Bundle; upstream's licenses remain applicable.

## Verification

```sh
zsh VPhoneExecutable/VPhoneVirtualization/Frida/Tests/run-tests.sh
# Optional official GitHub/download integration test:
zsh VPhoneExecutable/VPhoneVirtualization/Frida/Tests/run-tests.sh --live
```

Local tests cover exact version validation, supported asset selection and
rejection of a nonofficial download URL. The live Swift path fetched 17.25.2,
verified the SHA-256, extracted server/agent, and checked both binary signatures.
On test-vm (iPadOS 27.0.1), server 17.25.2 returned its version, served process
enumeration, and spawned/injected a disposable arm64 probe that printed
`FRIDA_PROBE_OK`. The existing Mac client used for that smoke test was 17.23.3;
that specific result does not establish compatibility for every mixed version.
No customer application was instrumented by this test.

Lifecycle checks also passed: a partial install has no ready marker, repeated
Start keeps the same PID/token, installing while running is rejected, and
repeated Stop is safe. The server ignored SIGTERM on this VM; Stop now waits
briefly, rechecks executable ownership, then uses SIGKILL on that managed PID
if necessary. The live test confirmed that the server was gone afterward.

The full VPhone scheme and bundle admission passed. Installed Core
2.15.0-local.074adbb6 exposed Features > Frida Server in test-vm. The panel
showed installed version 17.25.2, Running/PID, endpoint, a masked token, and Copy
command. A final client check enumerated processes through the installed Core's
server and rejected an intentionally invalid token. The server was left running
in the state observed in the UI. The UI download button itself was not confirmed
end to end because the user changed the UI during that action; the identical
Swift download/install preparation path was verified by the live test above.

## USB / usbmux transport

The VM also appears as a USB device in `frida-ls-devices`. The tested Mac client
(17.23.3) forwards `--token` only to remote (`-H`) connections; plain `frida-ps -U`
therefore reports authentication required with this token-protected server.
Keep authentication and forward the guest port through usbmux instead:

```sh
iproxy -u <vm-udid> 27043:27042
# In another terminal, use the token from the panel's Copy command:
frida-ps -ai -H 127.0.0.1:27043 --token '<token>'
```

`iproxy` is an optional external Mac tool, not a dependency of the shipped
bundle. This route was tested against test-vm and enumerated processes;
it carries traffic through usbmux rather than the guest's LAN address.

## Release picker and custom binaries

The Release dropdown offers Latest release, recent supported releases from
`GET /repos/frida/frida/releases?per_page=20`, Other version, and Custom.
Refresh reloads the list. A list-fetch error leaves Latest, Other version and
Custom usable. Other version retains access to older numeric release tags.

Custom accepts an uncompressed signed iOS arm64 Mach-O executable and an
optional matching iOS arm64 agent dylib. Files are inspected as data on the Mac;
only codesign verification is run there. The validator checks arm64 slices,
executable/dylib file type, iOS platform load commands, sizes and bounds before
upload. macOS, simulator, Android and malformed files are rejected. Local files
are never uploaded to GitHub and their signatures/entitlements are preserved.

When no external agent is selected, the server must embed its own agent.
Preparing that mode removes the previously managed external agent so it cannot
silently reuse a different version. With an agent selected, both files must
finish uploading before the installation becomes ready. The managed runtime
cache is cleared on preparation. Custom servers must support standard Frida
listen/token/directory command-line options; arbitrary custom builds are not
guaranteed compatible. The installed version label identifies the custom file.

Custom verification: selected signed server/agent files passed inspection; unit
fixtures rejected wrong platform, wrong file type and malformed load commands.
In test-vm the custom upload path started the server and served `frida-ps -ai`.
Embedded/external agent readiness was checked without reusing the old agent,
then the original 17.25.2 files and stopped state were restored. The full build
and bundle admission passed. Installed Core 2.15.0-local.3d9d5bb2 displayed the
20-version dropdown and Custom's Choose Server / Choose Agent controls. The
existing live server session observed afterward was preserved.

## Native session manager

Features > Frida Session is separate from server installation/lifecycle.
Start the managed server first, select a registered app, then Spawn or Attach
to running PID. Refresh Apps reads the existing `apps.list` contract. Attach
rechecks the selected app's current PID with `apps.list` before connecting. The
default transport is VSOCK: a private, ephemeral 127.0.0.1 listener forwards
only Frida TCP bytes through the existing guest `/v1/ports/27042` WebSocket
over VSOCK. Each Frida connection gets a guest stream of its own. The listener
exists only for the session, permits at most eight concurrent connections,
and applies bounded write backpressure. It exposes neither vphoned nor other
guest ports. The guest's Frida token is still required end to end. This route
does not depend on the guest LAN IP, NAT reachability or an external iproxy.
Clear Use guest transport (VSOCK) to enter a TCP endpoint, including a
user-managed loopback usbmux forward. Authentication uses the managed
server's current token, obtained through the existing signed guest helper.
The token is sent over the client's stdin pipe, never argv, console or reports.
No new RPC, guest environment update, host entitlement or kernel patch is added.

`vphone-frida-client` is a native C host child statically linked with the official
Frida Core 17.25.2 macOS arm64 devkit. BuildFridaClient.sh downloads that pinned
archive on the build machine and checks its fixed SHA-256 before extraction.
Only the header and static library are extracted; no upstream program runs.
At runtime only system libraries and the bundle are needed. Sources, notices,
the devkit header and a relinkable helper object (compressed) ship in
Contents/Resources/FridaClient. Bundle admission verifies the signed helper,
version, runtime dependencies and source/notice resources. Prefer server 17.25.2;
other/custom versions are subject to Frida protocol compatibility.

Choose Script reads a local nonempty UTF-8 JavaScript file of at most 512 KiB;
no remote script download or automatic bypass is provided. A chosen file is
held as a snapshot; choose it again after editing it on disk. Spawn attaches
and loads that snapshot before resuming the app. Attach uses the PID in the
refreshed app list, revalidated at start. Load / Replace Script compiles a candidate before unloading
the previous script. Syntax errors therefore keep the previous script;
runtime load failures are reported but cannot restore its prior runtime state.
This is raw Frida Core/QuickJS: scripts needing Frida 17 ObjC/Swift bridges must
bundle them, rather than relying on the Python CLI's bridge environment.

Console output includes raw script JSON and base64 for optional binary messages.
It retains bounded output (up to 1 MiB; oldest output is trimmed), and the pipe
queue is also bounded; a flooding client is stopped rather than growing host
memory indefinitely. Save Log exports the currently retained console locally.
Script output can contain sensitive data; no external service receives it.

Detach, closing the window, loss of guest connectivity, or stdin EOF unloads
and detaches. Successfully started/attached apps and the Frida server remain
running. A spawn that failed before resume is terminated to avoid a suspended
orphan. Remote operations have a 15-second cancellation deadline, cleanup has
its own deadlines, and the host has a final child-process watchdog. A transport
loss can prevent remote cleanup; such failures appear in the console and must
be checked on the guest. Closing during token/status lookup invalidates that
request, so it cannot create a hidden session after the window closes.

### Session verification

`zsh VPhoneExecutable/VPhoneVirtualization/Tests/run-pentest-tools-tests.sh`
checks frame splitting (including UTF-8 and newlines), malformed/oversized
output, a real refused loopback connection, and a test-only native Frida
boundary fixture. The fixture exercises actual client stdin/stdout and cleanup
for spawn, attach, script messages/replacement, EOF detach and injected failures
at attach/compile/load/resume. It verifies that only unresumed spawns are killed
and that tokens never appear in emitted events. It also checks a stalled
operation's cancellation, a syntax error during script replacement, and the
Swift client's streaming/EOF handling and early-child-exit path. These are local/fixture tests,
not evidence of live guest injection.

The relay regression uses real ephemeral loopback sockets with an injected
guest byte channel. It verifies byte transparency across receive boundaries,
multiple connections and guest-open failure. The production port stream reuses
the shell client's WebSocket handshake/framing with a fixed port route; shell
query behavior is preserved. Port close shuts down both directions to wake its
reader even when the guest is silent. The complete VPhone build checks this
integration; live VSOCK/Frida operation still needs the updated host process.

This transport change follows a live report where the Session child returned
No route to host for 192.168.64.4:27042 while the guest reported that same IP
and a host TCP probe succeeded. That establishes a difference between process
contexts, not a broken guest route or a confirmed specific privacy-policy cause.

The transport fix passed the relay/lifecycle regression suite, full Debug
build, bundle admission and Launchpad preflight. It was installed as
2.15.0-local.a8648fd3 and test-vm was bound to it for its next start.
The existing VM was left running, so its current process still uses the
previous build; live VSOCK verification remains pending that restart.

### Subsequent live failure: system apps

After restarting into the VSOCK build, the user reached the Frida server but
reported Files and Safari Spawn failures: EXC_CRASH codes 0x6000000, 0x0
while initializing a suspended process. This is Frida's Darwin target
preparation path, before script creation; it does not establish the underlying
abort cause. No matching crash-report metadata was returned by the guest.

With explicit user approval, a console-only Attach probe targeted Settings
only. Normal apps.launch first verified Settings as frontmost (PID 340).
The bundled native client then hit its 15-second cancellation deadline.
A throwaway diagnostic client with a 45-second deadline reached attach_sync
but received "Timeout was reached" before that call returned a session.
Repeating outside the stdin/event-loop callback, using the documented direct
synchronous calling pattern, produced the same timeout. No script was created
or console marker received. Settings still appeared in processes.list afterward;
that alone does not establish responsive UI. Customer apps were not targeted.
The token was read only into probe memory and sent over stdin; it was neither
printed nor persisted. The Frida agent file was present (61,890,896 bytes).
No server reinstall, guest update, kernel change, or VM restart was performed
for these probes. Attach is therefore not yet a validated workaround for the
Spawn failure. Server/agent and guest injection compatibility remain unresolved.

On 2026-11-04 the local suite, existing release/custom validation, full Debug
VPhone build and bundle admission passed. This build was not installed or
selected for an existing machine.

During this implementation's status check test-vm was stopped and bound
to Core 2.14.0-local.db9353c9. It was not started, rebound or updated. Live UI
and guest session checks remain: use a disposable test app, verify a script
message on both Spawn and Attach, replace the script, close the Session window,
and confirm the app and server remain running. Also exercise an invalid script,
target exit, server stop and closing during connection. Do not use a customer
app for these smoke tests.
