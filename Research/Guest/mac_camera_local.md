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

The companion's camera picker discovers built-in, external USB and Continuity
Camera devices. The helper opts into `NSCameraUseContinuityCameraDeviceType`.
It initially prefers the built-in camera, then keeps the selected device ID
while refreshing the list once a second. Changing devices stops the session,
clears the previous frame, replaces its input and restarts on the capture
queue; output remains 1280x720 BGRA even when the device needs another preset.
Disconnecting a selected camera keeps that selection and clears the frame,
rather than silently capturing another device. Reconnecting it resumes capture.

To use an iPhone, enable Settings > General > AirPlay & Continuity > Continuity
Camera, sign into the same Apple Account with two-factor authentication on both
devices, and connect by USB (trust the Mac) or use wireless Continuity Camera.
Select the iPhone by name in the companion. A USB cable alone does not expose
arbitrary iPhone camera access. See [Apple's setup requirements](https://support.apple.com/en-us/102546)
and [AVFoundation Continuity Camera support](https://developer.apple.com/documentation/avfoundation/supporting-continuity-camera-in-your-macos-app).
Continuity Camera exposes the iPhone's rear camera system; this source does not
provide front-camera switching on the physical iPhone.

Validation: build the VPhone bundle, verify signatures, bind a test VM
to the local bundle, open Mac Camera and grant consent, verify advancing frames
and upright capture in the guest, then Stop Streaming and confirm camera stops.
Transport success does not validate face verification, hardware camera parity,
or the app's original signing/provisioning behavior.

Earlier development-build validation: a 12-second built-in-camera smoke test
delivered 357 frames (29.75 FPS) into an iPad guest. Another measurement had a
7-second gap, so this does not establish uninterrupted or end-to-end latency.
The picker enumerated the built-in camera and OBS Virtual Camera. Physical
Continuity capture, device switching and unplug/reconnect still need hardware
validation; automated tests do not exercise physical capture devices.

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
The build workflow runs this script after bundle validation.
The tests cover pending/denied permission, stop/start policy, owner exit and
late permission after shutdown; private-buffer validation; pause/termination;
fresh-buffer isolation on restart; malformed files and symlinks; concurrent
publication from a separate process with torn-frame checks; and all four
rotations with colored markers and letterbox borders.

The companion UI, permission prompt and menu label are localized in English,
Japanese, Korean, Vietnamese and Simplified Chinese. Bundle validation checks
that each language's permission prompt and companion strings were staged.

## Manual verification

Use a disposable test guest to check each source that is physically available:

1. Select the built-in camera and confirm advancing frames in a guest app.
2. Switch to an external or iPhone camera; confirm the image changes and
   rotation still works without restarting the VM.
3. Unplug the selected camera; confirm a disconnected status and cleared image,
   with no automatic switch to another camera. Reconnect it and confirm capture
   resumes, or explicitly choose another source.
4. Stop streaming, close the companion, then close the VM; confirm each action
   releases the camera and an old companion cannot publish into a new session.

End-to-end behavior depends on each guest app's capture SDK. These checks do
not establish hardware camera parity, face verification, or signing behavior.

To roll back, stop the test VM, bind it to its previously installed release
using `vm set-bundle <vm-name> <previous-version>`, then start it again.
The original release remains installed when using `--keep-default`.
