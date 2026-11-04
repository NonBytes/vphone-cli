# Guest Frida server manager

Open **Features > Frida Server…** in an iOS/iPadOS VM. Enter `latest` or an exact
numeric release version, then Download & Install. Installation does not start
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
`proc.run` transport. It accepts only prepare/status/start/stop and has no new
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
On doctor-ipad (iPadOS 27.0.1), server 17.25.2 returned its version, served process
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
2.15.0-local.074adbb6 exposed Features > Frida Server in doctor-ipad. The panel
showed installed version 17.25.2, Running/PID, endpoint, a masked token, and Copy
command. A final client check enumerated processes through the installed Core's
server and rejected an intentionally invalid token. The server was left running
in the state observed in the UI. The UI download button itself was not confirmed
end to end because the user changed the UI during that action; the identical
Swift download/install preparation path was verified by the live test above.
