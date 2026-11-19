#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="$(cd "${0:a:h}/../../.." && pwd)"
output="${1:?Pass the output directory}"
version=0.1.0
ipatool_rev=3b02b4c55576562f2a55284cda9db9a4411d3067
archive="$root/.build/vphone-apps/vphone-apps_${version}_darwin_arm64.tar.gz"
digest=03f16e8be3bf3fda39010ca3966c20097bca5efbab8066568315b0f878781fba
cache="$root/.build/vphone-apps/$version"
patched_bin="$root/.build/vphone-apps/vphone-apps-${version}-ipatool-${ipatool_rev:0:12}-r2"
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

# Build vphone-apps with the updated ipatool v2.8.2+ authentication backend
# (fixes Apple's November 2026 HTTP 500/204 legacy auth deprecation).
go_bin=""
for candidate in /opt/homebrew/bin/go /usr/local/bin/go "$(command -v go 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        go_bin="$candidate"
        break
    fi
done

if [[ ! -f "$patched_bin" && -n "$go_bin" ]]; then
    src_dir="$root/.build/vphone-apps/src-$version"
    /bin/rm -rf "$src_dir"
    /usr/bin/git clone --depth 1 https://github.com/securityvoid/vphone-apps.git "$src_dir"
    (
        cd "$src_dir"
        PATH="${go_bin:h}:/usr/bin:/bin:/usr/sbin:/sbin" "$go_bin" get "github.com/majd/ipatool/v2@$ipatool_rev"
        PATH="${go_bin:h}:/usr/bin:/bin:/usr/sbin:/sbin" "$go_bin" mod tidy
        PATH="${go_bin:h}:/usr/bin:/bin:/usr/sbin:/sbin" "$go_bin" build -o "$patched_bin" ./cmd/vphone-apps
    )
fi

if [[ -f "$patched_bin" ]]; then
    /bin/cp "$patched_bin" "$output/vphone-apps"
else
    /bin/cp "$cache/vphone-apps" "$output/vphone-apps"
fi
/bin/cp "$cache/LICENSE" "$cache/NOTICE" "$cache/README.md" "$output/"
/usr/bin/xattr -dr com.apple.quarantine "$output/vphone-apps" 2>/dev/null || true
/bin/chmod 755 "$output/vphone-apps"
/usr/bin/codesign --force --sign - "$output/vphone-apps"
