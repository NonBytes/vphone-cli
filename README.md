<div align="right"><a href="Documents/README.md">Docs</a> · <strong>English</strong> · <a href="Documents/zh/README.md">中文</a> · <a href="Documents/ja/README.md">日本語</a> · <a href="Documents/ko/README.md">한국어</a></div>

# vphone-cli

Run a virtual iPhone on an Apple Silicon Mac.

This is [NonBytes' fork](https://github.com/NonBytes/vphone-cli) of
[Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli), with host camera
selection, a per-VM proxy editor, guest root CA management, and a Frida server manager. These additions
are included in this fork's `VPhone.bundle`; build and install it using the
instructions below. Downloading an upstream Core Bundle does not include them.

> [!WARNING]
> This project has never issued or authorized any cryptocurrency or token, and does not accept cryptocurrency payments or donations. Any cryptocurrency or token issued or promoted in this project's name, or claiming any affiliation with it, is a scam.

![Virtual iPhone running on macOS](Documents/demo.jpeg)

vphone-cli runs iOS with Apple's Virtualization.framework and PCC research virtual machines, for security research, reverse engineering, and debugging.

- **Graphical Window:** Use the virtual iPhone's screen on your Mac, browse apps and files, and take screenshots and screen recordings.
- **Custom Firmware:** The system comes pre-patched, and you can install a package environment.
- **Backup and Cloning:** You can export, import, and clone VMs.
- **Automation API:** An optional local HTTP and WebSocket interface.
- **No Extra Dependencies:** Needs no Xcode, Python, or Homebrew at runtime.

## Features in this fork

### Mac and iPhone cameras

Open **Features → Camera** in the VM window; two independent sources are
available:

- **Source: Mac Camera…** (this fork) opens a separately launched companion
  app that owns macOS Camera consent on its own, shares frames over a private
  mapped file, and offers a rotation selector to correct the image
  orientation. See [camera setup and limitations](Research/Guest/mac_camera_local.md).
- **Source: System Camera…** (upstream) opens an in-process picker and
  captures directly with AVFoundation, no companion app involved.

Either way, pick the source, select a camera, and click **Start Streaming**;
allow camera access when macOS prompts. Both support the Mac's built-in
camera, external cameras, available virtual cameras, and iPhone cameras
exposed by macOS Continuity Camera.

An iPhone must first be available to macOS as a Continuity Camera; connecting
a USB cable alone does not guarantee it appears. Continuity Camera provides
the physical iPhone's rear camera, without front-camera switching from
either source.

### Proxy and CA certificates

Open **Network → Proxy…** in the VM window:

1. Enable Proxy and enter a server address reachable from the VM and its port.
   For Burp on the Mac with the default NAT network, this is typically
   `192.168.64.1:8080`. Burp's listener must accept connections on that interface.
2. Click **Apply**. A green checkmark and **Proxy settings applied successfully.**
   confirm success. Clear Enable Proxy and Apply to turn it off.
3. For HTTPS interception, export your proxy's root CA as DER or PEM, click
   **Import CA Certificate…**, verify its fingerprint, and choose **Trust in VM**.

The window lists custom root CAs and lets you remove an individual CA.
Proxy settings persist after closing the window. Existing app connections may
need the app to reopen. Settings and certificate trust apply to that VM;
the Mac's proxy and trust store are unchanged. Importing a CA does not bypass
an app's certificate pinning. See [proxy and CA details](Research/Guest/proxy_menu.md).

### Network diagnostics and PCAP

Open **Network → Diagnostics & PCAP…** in the VM window to inspect guest
addresses, IPv4/DNS/router and proxy settings. Enter a hostname/IP and TCP port
to compare DNS resolution and TCP reachability from the Mac VM process and
the guest. TCP success does not verify HTTP, TLS or certificate trust.

Choose an interface, protocol, optional numeric IP/port, duration, file limit
and snap length, then **Start Capture**. **Stop** flushes the capture;
**Save PCAP…** exports a local file for Wireshark. Capture is interface-wide
and may include other apps' traffic. Save or discard before another capture.
See [capture scope, limits and recovery](Research/Guest/network_diagnostics.md).

### Frida Server

> [!NOTE]
> The default `standard` patch preset blocks four kernel relaxations Frida's
> Stalker and spawn handshake need. Without them, **Spawn** on a sandboxed
> app like Files or Safari can `EXC_CRASH`, and **Attach** to a sandboxed
> system app like Settings can time out. Create the VM (or run
> `fw set-patches <vm>`) with `--preset frida` — `standard` plus exactly
> those four patches, without `experimental`'s unrelated hv_vmm_present and
> identity rewrites — to fix both. The Frida Server and Session windows show
> an orange warning naming the fix when a VM's firmware is missing them. See
> [investigation and fix](Research/Guest/frida_server.md#investigation-lead-missing-opt-in-frida-kernel-relaxations).

Open **Features → Frida Server…**, choose **Latest release** or a recent version
from the dropdown, and click **Download & Install**. **Refresh** reloads the list;
**Other version…** lets you enter an older version. The manager downloads the
official iOS package from
[frida/frida releases](https://github.com/frida/frida/releases), checks its SHA-256
digest and binary signatures, and installs the server and agent in the selected VM.
Stop an existing server before installing another version.

For a locally built or modified server, choose **Custom… → Choose Server…** and
select a signed, uncompressed iOS arm64 `frida-server`. If it uses an external
agent, select the matching `frida-agent.dylib` with **Choose Agent…**; otherwise
the server must embed its agent. Click **Install Custom**, then **Start**.
Custom files stay local to the Mac and selected VM. They must support the
standard Frida server command-line options.

Click **Start**, then **Copy command** to get a `frida-ps -ai` command with the VM's
address and authentication token. Use a matching Frida client on the Mac.
**Stop** ends the managed server; closing the window leaves it running. It does
not automatically start after reboot. See [Frida setup and verification](Research/Guest/frida_server.md).

The suggested command lists installed apps and their identifiers:

```sh
frida-ps -ai -H <guest-ip>:27042 --token '<token>'
```

For USB/usbmux transport, use the VM's ID from `frida-ls-devices` and forward
the port with `iproxy` (an optional Mac tool):

```sh
# First terminal:
iproxy -u <vm-udid> 27043:27042
# Second terminal; use the token from Copy command:
frida-ps -ai -H 127.0.0.1:27043 --token '<token>'
```

The tested Frida client sends `--token` through `-H`; plain `-U` reports
authentication required with this token-protected server.

### App Inspector and Frida sessions

Open **Apps → App Browser**, select an app, and click **App Inspector** (⌘I).
The inspector shows the installed app's version/build, PID, bundle and data
containers, URL schemes, Mach-O signing/entitlements, App Transport Security
configuration and network policy. **Show in Files** opens a guest container;
**Save Report…** exports a local JSON snapshot, including section errors and
the limits of testing a re-signed app inside a VM.

In the inspector's **Data Container** section, open **Sandbox Diff…**. Click
**Capture Baseline**, exercise the app, then **Scan & Compare** to see added,
removed, content/type-changed, metadata-changed and uncertain paths. Captures
use SHA-256 and never follow symlinks. **Save Baseline… / Open Baseline…** keep
a baseline across sessions; **Save Diff…** exports both captures and the diff
as local JSON. App Groups and bundle files are excluded. Large, unreadable,
unstable or unscanned paths are uncertain; this is a bounded live scan, not an
atomic filesystem snapshot or a SQLite row-level comparison.
See [Sandbox Diff details](Research/Guest/sandbox_diff.md).

Open **Diagnostics → App Logs & Crash Viewer…**, or the same button in App
Inspector, and select an app. **App Logs** starts paused: choose **Start** to
collect new unified-log entries, then search, filter by level, inspect rows or
save the visible log. **Crash Reports** lists filename candidates for that
app, with report text, explicit bundle identity when available, and local
export. A mismatched report bundle ID is highlighted. No app is launched or
crashed and no guest report is deleted. See [scope and limits](Research/Guest/app_logs.md).

Start the managed server in **Features → Frida Server…**, then open
**Features → Frida Session…**. Select an app and choose **Spawn** to load a
script before the app resumes, or **Attach to running PID** for a running app.
Refresh Apps updates the PID list. Optionally choose a local UTF-8 `.js` file
(up to 512 KiB); **Load / Replace Script** replaces the session's script.
The console shows script messages and errors, and **Save Log…** saves it locally.
Closing the Session window detaches and leaves the app and server running.
**Use guest transport (VSOCK)** is enabled by default, so Session does not
require a reachable guest IP. Clear it to enter a direct TCP endpoint instead.

The bundle includes native Frida Core 17.25.2; no external Frida client,
Python or Homebrew is needed for this panel. Prefer a matching server.
Frida 17 scripts using ObjC/Swift bridges must bundle their bridges themselves.
See [session details and validation](Research/Guest/frida_server.md#native-session-manager).

### Build and install this fork

Building requires Xcode and an Apple Silicon Mac. Use Launchpad matching the
Core Bundle's version series (currently 2.15).

```sh
git clone https://github.com/NonBytes/vphone-cli.git
cd vphone-cli
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeBundle build

/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli \
  bundle install-local .build/XcodeBundle/Build/Products/Debug/VPhone.bundle --keep-default
```

Note the local version returned by installation. Stop the target VM, bind it
to that version, and start it again (replace both placeholders):

```sh
vphone-launchpad-cli vm stop <vm-name>
vphone-launchpad-cli vm set-bundle <vm-name> <local-version>
vphone-launchpad-cli vm start <vm-name> --wait
```

The short commands assume `vphone-launchpad-cli` is on PATH; otherwise use the
full app path shown above. These host features do not require restoring an
existing VM or updating its guest environment. Bind each new VM to this fork's
Core Bundle to use them too.

## Requirements

- A physical Apple Silicon Mac running macOS 15 or newer. It does not work in a macOS VM.
- Free disk space. Each VM has a 64 GB virtual disk by default, and firmware takes more.
- A network connection. Restoring the system fetches signing tickets online.
- Adjusted security settings. Boot into macOS Recovery, run these commands in Terminal, then restart:

  ```sh
  csrutil enable --without debug
  csrutil allow-research-guests enable
  ```

  SIP stays enabled, with only the debugging restrictions relaxed. For details, see [Host Setup](Documents/en/get-started/host-setup.md).

## Get Started

1. Download `vphone-launchpad-<version>-notarized.zip` from the [latest release](https://github.com/Lakr233/vphone-cli/releases/latest), unzip it, and open it. Not every release is notarized. If the latest one has no `-notarized` file, pick a notarized version from [Downloads](Documents/en/get-started/downloads.md).
2. In **Host Setup**, grant Developer Tools access and install the helper.
3. In **Core Bundle**, click **Download and Install**.
4. In **Machines**, click **New Machine**, choose a firmware pairing, and click **Create**.

Launchpad downloads the firmware, patches it, restores the system, and boots the VM. To use your own iPhone and cloudOS IPSWs, see [Compatibility](Documents/en/firmware/compatibility.md).

To install a package manager in the VM, see [Package Environment](Documents/en/machines/package-environment.md).

### Let an agent do it

If you use a coding agent (Claude Code, Codex, or similar) on this Mac, paste the prompt below instead of following the steps by hand. The agent reads the vphone skill, checks what is already set up, installs Launchpad and `VPhone.bundle`, and stops to ask when a step needs you, such as an administrator password or a change in macOS Recovery.

```text
Set up vphone on this Mac. Read the skill at
https://raw.githubusercontent.com/Lakr233/vphone-cli/main/Skills/vphone-guest-control/SKILL.md
and the files it links under references/ (same folder), then follow them:
install the newest notarized vphone-launchpad (not every release has a
-notarized zip), put vphone-launchpad-cli on PATH, install the VPhone.bundle
that matches Launchpad's series, and check `vphone-launchpad-cli status`.
Do not change SIP, boot-args or any other host security setting, and do not
create a machine until I confirm the firmware and the free disk space. When a
step needs me, tell me exactly what to do and wait.
```

## Command Line

Launchpad drives VMs through the `vphone-cli` inside `VPhone.bundle`. You can also run it in Terminal:

```sh
vphone-cli vm list
vphone-cli vm launch myphone
vphone-cli vm export myphone --out myphone.tzst
```

VMs are stored in `~/.vphone/`. Run `vphone-cli <group> --help` to see all commands. To create a VM without Launchpad, see [Create and Run](Documents/en/machines/create-and-run.md).

To turn on the automation API, add `--api-listen 127.0.0.1:8765` at launch and use the token it prints. See the [API documentation](Research/vphoned_http_api.md).

## Boot ROMs

New VMs start from two open-source ROMs instead of the closed ones in Virtualization.framework:

- [OpenAVB](https://github.com/owngoal-dev/OpenAVB) replaces AVPBooter, the boot ROM. It needs no patch, so `fw patch` leaves it alone.
- [OpenSEP](https://github.com/owngoal-dev/OpenSEP) replaces AVPSEPBooter, the SEP boot ROM.

With both, nothing Apple wrote runs before iBoot and SEPOS. Both ship in `VPhone.bundle`, prebuilt from pinned upstream commits. Each one's README ([OpenAVB](VPhoneExecutable/VPhoneVirtualization/Resources/OpenAVB/README.md), [OpenSEP](VPhoneExecutable/VPhoneVirtualization/Resources/OpenSEP/README.md)) says how to rebuild it and check it byte for byte.

VMs created by earlier versions keep Apple's ROMs. A VM switches either way without a restore, from its next start:

```sh
vphone-cli vm config myphone --rom openavb --seprom opensep   # open-source ROMs
vphone-cli vm config myphone --rom apple --seprom apple       # Apple's ROMs
```

`vphone-cli vm info myphone` shows which ROMs a VM uses. Restoring a VM that boots OpenAVB needs `VPhone.bundle` 2.10.1 or newer. For the details, see [OpenAVB](Research/Firmware/openavb_boot_rom.md) and [OpenSEP](Research/Firmware/opensep_sep_rom.md) in the research notes.

## Documentation

| Document | Contents |
| --- | --- |
| [Downloads](Documents/en/get-started/downloads.md) | Notarized Launchpad versions and matching `VPhone.bundle` versions |
| [Host Setup](Documents/en/get-started/host-setup.md) | SIP and AMFI settings, building from source, environment checks |
| [Create and Run](Documents/en/machines/create-and-run.md) | Firmware sources, the creation process, storage and backups |
| [Snapshots](Documents/en/storage/snapshots.md) | Save a stopped VM's disk state and revert to it |
| [Compatibility](Documents/en/firmware/compatibility.md) | Verified firmware pairings |
| [iPadOS Guests](Documents/en/firmware/ipados.md) | Run iPadOS (iPad mini A17 Pro) instead of iOS |
| [Package Environment](Documents/en/machines/package-environment.md) | Installing and removing a package manager in the VM |
| [Troubleshooting](Documents/en/help/troubleshooting.md) | Common errors and how to fix them |
| [Networking](Documents/en/networking/overview.md) | Network modes, and `tunnel` for a Mac behind a VPN or proxy |
| [Launchpad Command Line](Documents/en/launchpad/launchpad-cli.md) | Install and test a local build with `vphone-launchpad-cli` |
| [Manual Index](Documents/en/README.md) | Full manual: machines, firmware, storage, networking, Launchpad and bundles |

For this fork's camera, proxy, or CA features, [open an issue in this fork](https://github.com/NonBytes/vphone-cli/issues).
For the original project, see [upstream issues](https://github.com/Lakr233/vphone-cli/issues).

## Acknowledgements

- [wh1te4ever/super-tart-vphone-writeup](https://github.com/wh1te4ever/super-tart-vphone-writeup)
- [owngoal-dev/OpenAVB](https://github.com/owngoal-dev/OpenAVB) and [owngoal-dev/OpenSEP](https://github.com/owngoal-dev/OpenSEP), the boot ROMs new VMs start from
