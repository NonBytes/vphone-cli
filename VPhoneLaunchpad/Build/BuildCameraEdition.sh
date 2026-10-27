#!/bin/zsh
# Build a self-contained camera edition without changing the installed app.
# --development produces an ad hoc signed, separately identified trial app.
# Distribution needs the original SignLaunchpad.sh Developer ID workflow.
set -euo pipefail
root="${0:a:h}/../.."
root="${root:A}"
configuration=Release
development=false
if [[ ${1:-} == --development ]]; then
    configuration=Debug
    development=true
elif [[ -n ${1:-} ]]; then
    print -u2 'usage: BuildCameraEdition.sh [--development]'
    exit 2
fi
cd "$root"
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/XcodeBundle build
xcodebuild -project VPhoneLaunchpad/VPhoneLaunchpad.xcodeproj -scheme VPhoneLaunchpad \
    -configuration "$configuration" -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .build/CameraLaunchpad build
app="$root/.build/CameraEdition/vphone-launchpad-camera.app"
source="$root/.build/CameraLaunchpad/Build/Products/$configuration/vphone-launchpad.app"
# ditto into a fresh staging directory so old resources never survive an update.
stage="$(mktemp -d "$root/.build/camera-edition.XXXXXX")"
trap '/bin/rm -rf "$stage"' EXIT
ditto "$source" "$stage/vphone-launchpad-camera.app"
prepared="$stage/vphone-launchpad-camera.app"
mkdir -p "$prepared/Contents/Resources/EmbeddedCore"
ditto "$root/.build/XcodeBundle/Build/Products/Debug/VPhone.bundle" \
    "$prepared/Contents/Resources/EmbeddedCore/VPhone.bundle"
if $development; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.nonbytes.vphone.launchpad.camera-development' "$prepared/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :VPhoneCameraDevelopmentCompanion bool true' "$prepared/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName VPhone Camera Development' "$prepared/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName VPhone Camera Development' "$prepared/Contents/Info.plist"
    for strings in "$prepared/Contents/Resources/"*.lproj/InfoPlist.strings(N); do
        for key in CFBundleName CFBundleDisplayName; do
            /usr/libexec/PlistBuddy -c "Set :$key VPhone Camera Development" "$strings" 2>/dev/null || \
                /usr/libexec/PlistBuddy -c "Add :$key string VPhone Camera Development" "$strings"
        done
    done

    for binary in "$prepared/Contents/MacOS/vphone-launchpad-cli" \
        "$prepared/Contents/MacOS/vphone-launchpad-launcher" \
        "$prepared/Contents/Library/LaunchServices/com.vphone.launchpad.helper"; do
        codesign --force --sign - "$binary"
    done
    codesign --force --sign - "$prepared"
    codesign --verify --strict --deep "$prepared"
fi
mkdir -p "${app:h}"
# Replacing only this build output, never /Applications or installed VMs.
if [[ -e "$app" ]]; then
    backup="${app:h}/vphone-launchpad-camera-previous-$(date +%Y%m%d%H%M%S).app"
    mv "$app" "$backup"
fi
mv "$prepared" "$app"
print "Camera edition: $app"
if $development; then
    print 'Trial launch: VPHONE_LAUNCHPAD_CAMERA_COMPANION=1 <app>/Contents/MacOS/vphone-launchpad'
else
    print 'Sign with SignLaunchpad.sh and your configured Developer ID before distributing.'
fi
