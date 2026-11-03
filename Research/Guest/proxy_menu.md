# Guest proxy editor

Open the VM window's **Network > Proxy…** menu. Reload reads the guest's current
configuration. Enable Proxy, enter a hostname/IP and port, and Apply to set the
same endpoint for HTTP and HTTPS. Clear Enable Proxy and Apply to disable both.
Off preserves the saved endpoint and bypass exceptions so it can be enabled
again. Existing app connections may require closing and reopening the app.

The editor targets the virtual guest's en0 network services on iOS/iPadOS 17+.
It changes the guest's persistent SystemConfiguration preferences, not the
Mac's proxy. Automatic proxy/PAC discovery is disabled on Apply, with a notice
when replacing existing automatic or differing HTTP/HTTPS settings. Other
service settings, bypass lists and saved PAC URLs are preserved.

The core bundle carries the signed `vphone-guest-proxy` iOS tool. Each operation
uploads it to `/private/var/tmp/vphone-guest-proxy` with mode 0700, then uses the
existing `script.eval` and `proc.run` interfaces. No new RPC method, TCP listener,
shell, guest-environment update, or host administrator operation is introduced.
Only `read` and `apply <JSON>` are accepted. The tool validates input before
locking preferences or committing any change, and checks commit and activation
separately. Invalid port/host, a script crash, nonzero process status and malformed
output are surfaced as errors instead of reporting success.

JSON configuration: `{ "enabled": true, "host": "192.168.64.1", "port": 8080 }`.
Read/apply return `enabled`, `host`, `port`, `mixed`, `automatic`, `services`.
The configured endpoint must be reachable from the guest; localhost denotes the
guest itself. Proxy authentication and SOCKS are outside this editor's scope.
After Apply succeeds, a green checkmark confirms the settings were applied.

## Guest CA certificates

The same window lists user-installed root CAs and offers **Import CA Certificate…**.
Select one DER or PEM self-signed root CA, inspect its name and SHA-256 fingerprint,
then confirm **Trust in VM**. Remove targets the selected fingerprint only and
requires confirmation. Neither action changes the Mac trust store or system roots.
Import rejects expired/not-yet-valid certificates, server certificates, chains,
private keys, trailing data and files above 64 KiB. Expired installed roots remain
visible and removable.

The iOS-only `vphone-guest-ca` helper accepts `list`, `import <base64>`, and
`remove <sha256>`. It uses Security's user trust-store domain and carries only
`modify-anchor-certificates`; host tools gain no additional entitlements. Each
operation uploads the signed helper and verifies the resulting trust-store state.
It uses the existing guest transport without requiring a guest-environment update.

Verification:

```sh
zsh VPhoneExecutable/VPhoneVirtualization/Proxy/Tests/run-tests.sh
zsh VPhoneExecutable/VPhoneVirtualization/Proxy/Tests/run-ca-tests.sh
```

The tests use the shared validation/transformation/decoding code without writing
host network settings. They cover host and port rejection, IPv6 normalization,
HTTP/HTTPS enable/disable, preserved endpoints/exceptions, mixed/automatic state,
and nested script/child failures. A live guest check read the existing endpoint,
rejected port 0, disabled the proxy, then restored the original endpoint.
The full VPhone build and bundle admission passed. The installed VM exposed
Network > Proxy, loaded the saved endpoint in the editor, and displayed the
applied state; a separate read confirmed HTTP/HTTPS proxy remained enabled.

CA verification on doctor-ipad: a disposable self-signed CA was imported twice
without duplication, confirmed trusted, then removed. The original PortSwigger
CA list was unchanged afterward. DER/PEM and seven invalid-input cases passed.
The full VPhone scheme and bundle admission (including guest-only CA entitlement)
passed. On the installed 2.15 Core, the Proxy window listed PortSwigger CA,
exposed Import CA Certificate, and displayed the success message after Apply.
