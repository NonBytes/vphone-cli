# Build and install this fork

The fork's current pentest tools are owned by Launchpad, not by a selected Core
Bundle. Build/sign/install Launchpad to update those tools. Build Core separately
when you need this fork's VM-host or firmware changes. Building needs an Apple
Silicon Mac and Xcode with the iPhoneOS SDK; shipped runtime components use
system libraries and their own bundled resources, without Python or Homebrew.

## Launchpad and Pentest Tools

Clone https://github.com/NonBytes/vphone-cli and open its checkout. Configure
`VPhoneLaunchpad/Configuration/Developer.xcconfig` locally before building:

```xcconfig
VPHONE_LAUNCHPAD_TEAM = YOUR_TEAM_ID
```

This file is gitignored. Never commit a real team ID or signing credentials.
The team must match your signing identity, including its private key in macOS
Keychain. Apple Development works for local testing; use Developer ID Application
and the appropriate distribution/notarization process when distributing outside
the Mac App Store. A certificate alone does not provide its private key.

```sh
xcodebuild -project VPhoneLaunchpad/VPhoneLaunchpad.xcodeproj \
  -scheme VPhoneLaunchpad -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeLaunchpad build

security find-identity -v -p codesigning
zsh VPhoneLaunchpad/Build/SignLaunchpad.sh \
  .build/XcodeLaunchpad/Build/Products/Debug/vphone-launchpad.app \
  '<signing-identity-name-or-hash>'

codesign --verify --strict --deep \
  .build/XcodeLaunchpad/Build/Products/Debug/vphone-launchpad.app
```

Choose your identity from the public identity list; the placeholder above is
not a usable identity. Nothing is signed by the Xcode build itself. The signing
script signs Debug dylibs, bundled frameworks, native Frida client, helper,
launcher and CLI before sealing the apps, and checks helper requirements and
app entitlements. It can preserve an existing installed helper only when its
signature/requirement are valid and its CodeDirectory matches exactly; changed
helper code still requires the normal SMJobBless update.

Quit Launchpad and its Pentest Tools instances, preserve a rollback copy of the
installed app, and replace `/Applications/vphone-launchpad.app` with the signed
build. Reopen it and check Host Setup. Handle any macOS administrator or Keychain
prompt yourself; do not put passwords or P12/private keys in chat or the repo.
Keeping the same valid signing identity avoids an unnecessary identity change,
but verify actual grants/helper readiness after replacing the app:

```sh
/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli status
```

Select a machine → Actions → Pentest Tools. Offline IPA patching works without
a running guest; install/launch requires a running VM with the needed APIs.
See [tools ownership and compatibility](launchpad_pentest_tools.md),
[Gadget sessions](gadget_sessions.md), and
[Patch → Install → Launch → Session](gadget_deployment.md).

## Optional Core Bundle build

```sh
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeBundle build

/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli \
  bundle install-local .build/XcodeBundle/Build/Products/Debug/VPhone.bundle \
  --keep-default
```

This produces/validates the complete distributable bundle and installs a local
version without changing the default or any VM's binding. Launchpad/Core series
must be compatible; see [downloads/version rules](../../Documents/en/get-started/downloads.md).
To bind a stopped VM to the returned version, use Launchpad's Change Core Bundle
or the [local Core workflow](../../Documents/en/launchpad/core-bundles.md).
Updating a host Core does not automatically update the guest environment or
boot chain. Guest/API/kernel restrictions still apply to individual tools.

For Developer Tools grants after a rebuild, see
[grant troubleshooting](developer_tools_grant.md). For host security requirements,
use [Host Setup](../../Documents/en/get-started/host-setup.md); this build guide
does not change SIP, boot arguments or Research Guests settings.
