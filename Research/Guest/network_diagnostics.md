# Network Diagnostics and PCAP

The VM window exposes **Network → Diagnostics & PCAP…**. Launchpad users open
the VM window from Launchpad; this menu belongs to the running Core Bundle.
After changing its bound bundle, Stop/Start the VM to load the new menu.

## Diagnostics

Read-only refresh uses existing `device.network`, `network.ipv4.get` (en0),
and the guest proxy reader. The raw IPv4 response preserves the backend's DNS
and router fields. It does not apply proxy settings or change CA trust.

A validated hostname or numeric IPv4/IPv6 address and TCP port are tested
separately from the host VM process and guest. Each probe allows three seconds
for DNS and a further three-second TCP budget across up to eight unique
addresses. DNS calls that exceed the wait may still finish in the system
resolver in the background. TCP sends no application payload and stops after
the first successful address. Results are not HTTP, TLS, CA or pinning tests.
Loopback addresses refer to the side running that probe. Host Local Network
privacy and network policy can affect the host result independently.

## Capture

`vphone-guest-network` is built and ad hoc signed into guest-resources. The UI
uploads it through the existing file transport and invokes it through
`script.eval` / `proc.run`. No new daemon method, firmware patch, external
runtime, package installation or guest environment update is required. The
older `network.capture` RPC is unchanged.

The helper opens a guest BPF descriptor read-only, binds a named interface,
enables immediate delivery, and never enables promiscuous mode. It has no
packet injection operation. A small C bridge handles XNU BPF ioctls and record
layout; Swift owns validation, filtering, lifecycle and classic PCAP writing.
Supported link types are Ethernet, BSD loopback and raw IP (PCAP linktype101).

Capture is interface-wide, not tied to an app or PID. Structured protocol
(any/TCP/UDP/ICMP), numeric IP and port filters match either endpoint. Filtering
occurs in the helper after reading BPF, before writing PCAP; unrelated packets
are not persisted. IPv4/IPv6, Ethernet VLANs and bounded IPv6 extension headers
are parsed. Port filters reject truncated headers and noninitial fragments.
This is not an arbitrary tcpdump expression parser.

Every request limits duration to 1–60 seconds, output to 64 KiB–64 MiB, and
snap length to 64–65535 bytes. The UI offers a subset of these values. Only
whole PCAP records fitting the byte limit are written. Snap truncation and
driver drop counters are shown separately; BPF drop counters cover the
descriptor, not just packets passing the helper's filter. HTTPS payloads
remain encrypted. Other cleartext protocols may contain credentials or data.

## Lifecycle and export

One capture/result is retained in `/private/var/vphone-network` (0700).
Capture, state and lock files use private permissions. Directory/file checks
reject symlinks and unexpected ownership; locks require regular private files.
A management lock serializes operations; a separate worker lease prevents
concurrent workers. Stop writes a request with the capture UUID, never signals
a stored PID. Worker status is updated periodically and after flushing output.

Closing the window requests Stop for a capture it started. If disconnected,
the worker still obeys its own duration and byte limits. Reopening reads status
and recovers a workerless active state as interrupted. An interrupted file may
have stale counters; malformed partial records fail export validation. Stop
and Discard verify capture identity. Discard refuses an active worker and
removes only the managed PCAP/state/stop files. Save or Discard is required
before starting another capture; results are not silently overwritten.

Save PCAP streams to a private temporary host file with the request's byte
limit, validates every PCAP record and completed counters, rechecks capture
identity, then atomically replaces the selected destination. It retains the
guest result until Discard. Save Diagnostics / Capture Metadata exports JSON
separately. Neither operation uploads data to external services.

## Validation

`zsh VPhoneExecutable/VPhoneVirtualization/Tests/run-network-diagnostics-tests.sh`
checks structured filters, fragments/truncation, PCAP round trips and malformed
records, no-follow export, native BPF record decoding and a local TCP listener.
CI runs these fixtures. The full VPhone Xcode scheme builds/signs the guest
helper and validates the finished bundle.

The opt-in `--live doctor-ipad` test uploads uniquely named temporary helpers,
requires an idle capture store, and captures only loopback UDP for a random
exclusive fixture source port and 127.0.0.1. It verifies a known canary, Stop,
exported PCAP counters, the automatic duration limit, guest DNS/TCP and Discard, then removes its helpers and
local export. It does not start or inspect a customer app. This passed on
doctor-ipad (iPadOS 27.0.1); GUI interaction remains separate validation.
