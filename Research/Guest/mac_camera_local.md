# Local Mac camera source

Adds Camera > Source: Mac Camera and a separately launched VPhoneMacCamera.app.
The companion owns macOS Camera consent. Launchpad's Developer ID signature,
helper, VM guest environment and security settings stay as installed.

Each streaming session creates a fresh mkstemp file (0600), mapped into both
processes. Stopped helpers cannot write into a later session's buffer.
The fixed 64-byte header contains control (UInt32 at offset 0, 0 pause / 1
capture / 2 exit) and frame sequence (UInt64 at offset 8). Pixels are 1280x720
BGRA at offset 64, stride 5120. Both processes flock before access;
an NSLock also serializes threads sharing one descriptor. Frame reads and
publication drop a frame when the other process owns the mapping lock.
No socket listener, recording or external video service is involved.

Start Streaming opens the companion and asks Camera consent. Stop Streaming,
Source: Off, closing the camera window or closing the VM stops capture.
The companion also monitors the VM PID and exits when it disappears.
A rotation selector compensates for the guest application's camera orientation.

Validation: build the VPhone bundle, verify signatures, bind a test VM
to the local bundle, open Mac Camera and grant consent, verify advancing frames
and upright capture in the guest, then Stop Streaming and confirm camera stops.
Transport success does not validate face verification, hardware camera parity,
or the app's original signing/provisioning behavior.

## Build and install

Build with Xcode on an Apple Silicon Mac:

```sh
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeBundle build
```

Install using Launchpad of the matching 2.14 series:

```sh
vphone-launchpad-cli bundle install-local \
  .build/XcodeBundle/Build/Products/Debug/VPhone.bundle --keep-default
```

Use the local version returned by that command. Stop the test VM, bind it
with `vm set-bundle <vm-name> <local-version>`, then `vm start <vm-name> --wait`.
The change is host-only: do not update the guest environment or restore the VM.

In Features, choose Source: Mac Camera, then Start Streaming. Allow Camera
access to VPhone Mac Camera when macOS prompts. The companion's rotation
selector offers 0/90/180/270 degrees. Stop Camera or Stop Streaming ends capture.

## Automated regression tests

```sh
VPhoneExecutable/VPhoneVirtualization/Camera/Tests/run-tests.sh
```

This compiles the actual shared channel, capture policy and rotation code with
Swift 6 and system frameworks. No Camera permission or physical camera is used.
The tests cover pending/denied permission, stop/start policy, owner exit and
late permission after shutdown; private-buffer validation; pause/termination;
fresh-buffer isolation on restart; malformed files and symlinks; concurrent
publication from a separate process with torn-frame checks; and all four
rotations with colored markers and letterbox borders.

The companion UI, permission prompt and menu label are localized in English,
Japanese, Korean, Vietnamese and Simplified Chinese. Bundle validation checks
that each language's permission prompt and companion strings were staged.

## Verification


The full VPhone Xcode scheme, including ValidateBundle, passed on an Apple
Silicon Mac. Launchpad installed the local build with policy and preflight
passed. MacBook Pro Camera capture produced advancing shared-frame sequence
numbers while the guest camera transport was connected. End-to-end behavior
still depends on each guest app's capture SDK; hardware camera parity and
face verification are not established by this transport test.

To roll back, stop the test VM, bind it to its previously installed release
using `vm set-bundle <vm-name> <previous-version>`, then start it again.
The original release remains installed when using `--keep-default`.

## Launchpad camera edition (2.14)

The camera-edition app packages Core Bundle 2.14 in
`Contents/Resources/EmbeddedCore/VPhone.bundle`. In Core Bundle, select
Install Included Camera Bundle, then Use for New Machines. Installation uses
the normal signed privileged helper, archive/signature validation and host
preflight. Existing VMs opt in while stopped from their inspector's Mac Camera
section. This updates only the host bundle binding, not guest firmware/data.

For running VMs, Start Mac Camera and Stop Camera send local `camera` requests
through the VM's existing Unix socket. No new network listener is opened.
Capability is declared by `VPhoneMacCameraControlVersion=1` in Core Bundle's
Info.plist and requires the camera companion executable. An older local build
is not assumed to support control. Menu state follows socket-driven changes.

Build the trial app:

```sh
VPhoneLaunchpad/Build/BuildCameraEdition.sh --development
```

The result is `.build/CameraEdition/vphone-launchpad-camera.app`. The ad hoc
signed development app has a separate bundle identifier. Launch with
`VPHONE_LAUNCHPAD_CAMERA_COMPANION=1` to keep the official Launchpad's existing
control socket and helper untouched. In this explicit Debug-only mode, the
camera installer/default/binding buttons and host preflight delegate to the already installed
signed app's CLI. Running VM camera control still uses the VM's local socket.
The signed app must be installed at `/Applications/vphone-launchpad.app`.
Other privileged operations in the development app still require a configured
Developer ID; this mode is a camera integration trial, not a distributable
replacement for Host Setup or VM provisioning.

For distribution, build without `--development`, configure the fork's signing
team, sign via `VPhoneLaunchpad/Build/SignLaunchpad.sh`, and notarize normally.
No client requirement or signature verification is relaxed for development.

Capability/version checks:

```sh
VPhoneLaunchpad/Tests/MacCameraSupportTests.sh
VPhoneLaunchpad/Tests/BundleNamesTests.sh
```

The current camera socket command accepts only the VM owner's Unix peer UID,
even if the machine folder is shared with other local accounts. Start/stop
replies describe the transport request, not proof of granted camera consent.

### Host Setup in the development companion

The trial app's Host Setup presents the signed app's live status as
Privileged helper (delegated), explicitly limited to camera operations. It
checks helper readiness, host readiness, Developer Tools access and whether
an installation is in progress. Errors and missing status fields fail closed.
The trial's own requiredPassed remains unchanged, so presenting delegated
camera readiness does not unlock this app's unsupported root operations.
Use the official Launchpad for VM provisioning and firmware maintenance.

```sh
VPhoneLaunchpad/Tests/DelegatedCameraStatusTests.sh
```

Developer Tools is also labeled delegated in the camera trial: the displayed
value comes from the signed app that actually requests policy exceptions.
The trial app's own EPDeveloperTool value is preserved in its underlying
checks and still applies to its own privileged operations. A toggled-on trial
app permission therefore cannot hide a denied or unavailable signed-app grant,
and a stale trial-app authorization snapshot does not block camera delegation.
