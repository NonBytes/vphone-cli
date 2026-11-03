#!/bin/zsh
# vphone-tier: build
set -euo pipefail
root="${0:a:h:h:h}"
work="$(mktemp -d "${TMPDIR:-/tmp}/vphone-ca-tests.XXXXXX")"
trap '/bin/rm -rf "$work"' EXIT
cat > "$work/openssl.cnf" <<'CONFIG'
[req]
distinguished_name=dn
x509_extensions=ca
prompt=no
[dn]
CN=VPhone Disposable Test CA
[ca]
basicConstraints=critical,CA:true
keyUsage=critical,keyCertSign,cRLSign
CONFIG
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -config "$work/openssl.cnf" -keyout "$work/key.pem" -out "$work/ca.pem" 2>/dev/null
openssl x509 -in "$work/ca.pem" -outform DER -out "$work/ca.der"
sed 's/CA:true/CA:false/; s/keyCertSign,cRLSign/digitalSignature/' "$work/openssl.cnf" > "$work/leaf.cnf"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -config "$work/leaf.cnf" -subj /CN=Leaf -keyout "$work/leaf-key.pem" -out "$work/leaf.pem" 2>/dev/null
xcrun --sdk macosx swiftc -swift-version 6 -parse-as-library \
    "$root/UI/GuestCommunication/VPhoneProxyConfiguration.swift" \
    "$root/UI/GuestCommunication/VPhoneCACertificate.swift" \
    "${0:a:h}/CACertificateTests.swift" -o "$work/ca-tests" -framework Security -framework CryptoKit
"$work/ca-tests" "$work"
