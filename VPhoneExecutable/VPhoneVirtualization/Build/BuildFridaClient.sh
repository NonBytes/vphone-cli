#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
output="${1:?Pass the output directory}"
version=17.25.2
archive="$root/.build/frida-client/frida-core-devkit-$version-macos-arm64.tar.xz"
digest=b91a1dc1a59857d0d23cab91792455122187765bea0d0bd72f48355651666353
cache="$root/.build/frida-client/$version"
/bin/mkdir -p "${archive:h}" "$cache" "$output"
if [[ ! -f "$archive" ]]; then
    temporary="$(/usr/bin/mktemp "${archive}.XXXXXX")"
    trap '/bin/rm -f "$temporary"' EXIT
    /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 \
        "https://github.com/frida/frida/releases/download/$version/${archive:t}" -o "$temporary"
    [[ "$(/usr/bin/shasum -a 256 "$temporary" | /usr/bin/awk '{print $1}')" == "$digest" ]] || {
        print -u2 'Frida devkit SHA-256 mismatch'; exit 1
    }
    /bin/mv "$temporary" "$archive"
fi
[[ "$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')" == "$digest" ]] || {
    print -u2 "Frida devkit SHA-256 mismatch: $archive"; exit 1
}
# Extract only build inputs, never upstream executables or scripts.
/usr/bin/tar -xf "$archive" -C "$cache" ./frida-core.h ./libfrida-core.a
/usr/bin/xcrun --sdk macosx clang -arch arm64 -mmacosx-version-min=15.0 -O2 \
    -Wall -Wextra -Wno-unused-parameter -I "$cache" \
    -c "$root/VPhoneExecutable/VPhoneVirtualization/Frida/Client/main.c" \
    -o "$output/vphone-frida-client.o"
/usr/bin/xcrun --sdk macosx clang -arch arm64 -mmacosx-version-min=15.0 \
    "$output/vphone-frida-client.o" "$cache/libfrida-core.a" \
    -lbsm -ldl -lresolv -lm -framework Foundation -framework CoreFoundation \
    -framework AppKit -framework CoreServices -o "$output/vphone-frida-client"
/usr/bin/codesign --force --sign - "$output/vphone-frida-client"
