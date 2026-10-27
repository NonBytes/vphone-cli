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

Install using Launchpad of the matching 2.13 series:

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
