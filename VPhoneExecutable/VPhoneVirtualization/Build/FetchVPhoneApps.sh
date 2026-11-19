#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
output="${1:?Pass the output directory}"
version=0.1.0
archive="$root/.build/vphone-apps/vphone-apps_${version}_darwin_arm64.tar.gz"
digest=03f16e8be3bf3fda39010ca3966c20097bca5efbab8066568315b0f878781fba
cache="$root/.build/vphone-apps/$version"
/bin/mkdir -p "${archive:h}" "$cache" "$output"
if [[ ! -f "$archive" ]]; then
    temporary="$(/usr/bin/mktemp "${archive}.XXXXXX")"
    trap '/bin/rm -f "$temporary"' EXIT
    /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 \
        "https://github.com/securityvoid/vphone-apps/releases/download/v$version/${archive:t}" -o "$temporary"
    [[ "$(/usr/bin/shasum -a 256 "$temporary" | /usr/bin/awk '{print $1}')" == "$digest" ]] || {
        print -u2 'vphone-apps archive SHA-256 mismatch'; exit 1
    }
    /bin/mv "$temporary" "$archive"
fi
[[ "$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')" == "$digest" ]] || {
    print -u2 "vphone-apps archive SHA-256 mismatch: $archive"; exit 1
}
/usr/bin/tar -xf "$archive" -C "$cache" vphone-apps LICENSE NOTICE README.md
/bin/cp "$cache/vphone-apps" "$output/vphone-apps"
/bin/cp "$cache/LICENSE" "$cache/NOTICE" "$cache/README.md" "$output/"
/usr/bin/xattr -dr com.apple.quarantine "$output/vphone-apps" 2>/dev/null || true
/bin/chmod 755 "$output/vphone-apps"
/usr/bin/codesign --force --sign - "$output/vphone-apps"
