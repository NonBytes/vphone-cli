<div align="right"><a href="Documents/en/README.md">Docs</a> · <strong>English</strong> · <a href="Documents/zh/README.md">中文</a> · <a href="Documents/ja/README.md">日本語</a> · <a href="Documents/ko/README.md">한국어</a></div>

# vphone-cli

Run a virtual iPhone on an Apple Silicon Mac for security research, reverse engineering, and debugging.

This is [NonBytes' fork](https://github.com/NonBytes/vphone-cli) of
[Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli), with additional
pentest tools, camera selection, and per-VM proxy/CA management.

> [!WARNING]
> This project has never issued or authorized any cryptocurrency or token, and does not accept cryptocurrency payments or donations. Any cryptocurrency or token issued or promoted in this project's name, or claiming any affiliation with it, is a scam.

![Virtual iPhone running on macOS](Documents/demo.jpeg)

A physical Apple Silicon Mac with macOS 15+ is required. The shipped apps need
no Xcode, Python, or Homebrew at runtime. See the
[documentation site](https://lakr233.github.io/vphone-cli/),
[Host Setup](Documents/en/get-started/host-setup.md), and
[manual](Documents/en/README.md) for the base project's requirements and VM setup.
The fork-specific workflows below are documented in this repository.
Already cloned the fork? Use the [AI agent setup prompt](#set-up-with-an-ai-agent).

## Prepare your Mac

Before installing the fork, prepare the physical Apple Silicon Mac for
research guests and choose an APFS volume for the VM library.

1. Shut down the Mac. Hold the power button until startup options appear,
   then choose **Options → Continue** to enter macOS Recovery.
2. Open **Utilities → Terminal** in Recovery and run:

   ```sh
   csrutil enable --without debug
   csrutil allow-research-guests enable
   ```

   This keeps SIP enabled with its debugging restrictions relaxed and enables
   Research Guests. The full guide also documents the SIP-off/AMFI-off option.
   [Host Setup security configurations](Documents/en/get-started/host-setup.md#choose-a-security-configuration)
3. Restart into macOS and continue with the installation below. On first
   launch, use **Host Setup** to grant Launchpad access in **System Settings →
   Privacy & Security → Developer Tools**, authorize its privileged helper,
   and verify the APFS library. The helper handles the `vphone-vm` allowlist
   when needed. [Launchpad host setup](Documents/en/get-started/host-setup.md#with-launchpad)

## Install the fork

1. Install Xcode with the iPhoneOS SDK and clone the fork.

   ```sh
   git clone https://github.com/NonBytes/vphone-cli.git
   cd vphone-cli
   ```

2. Set `VPHONE_LAUNCHPAD_TEAM` in the local
   `VPhoneLaunchpad/Configuration/Developer.xcconfig` to match your signing
   identity in macOS Keychain. See the [fork build guide](Research/Host/fork_build.md).

3. Build, sign and verify Launchpad. Replace the signing placeholder with
   a name or hash from `security find-identity -v -p codesigning`.

   ```sh
   xcodebuild -project VPhoneLaunchpad/VPhoneLaunchpad.xcodeproj \
     -scheme VPhoneLaunchpad -configuration Debug \
     -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath .build/XcodeLaunchpad build

   app=.build/XcodeLaunchpad/Build/Products/Debug/vphone-launchpad.app
   zsh VPhoneLaunchpad/Build/SignLaunchpad.sh "$app" '<signing-identity>'
   codesign --verify --strict --deep "$app"
   ```

4. Quit Launchpad and Pentest Tools. Copy the signed `vphone-launchpad.app`
   from the build path above to **Applications** in Finder. Open it and
   complete **Host Setup**. [Host setup guide](Documents/en/get-started/host-setup.md)

5. Pair this fork's **Launchpad 2.17.1** with a **2.17.x Core Bundle** in
   Launchpad, then create or select a test VM and start it. For this fork's camera and
   proxy/CA tools, build and install the fork's Core separately and select it
   using **Actions → Change Core Bundle…** while the VM is stopped.
   [Core version matching](Documents/en/get-started/downloads.md) · [Build and install Core](Research/Host/fork_build.md#optional-core-bundle-build) · [Core Bundles and local builds](Documents/en/launchpad/core-bundles.md)

### Upgrade an existing VM from 2.16

Install the 2.17 Launchpad and Core together. Stop the VM and select its new
Core with **Actions → Change Core Bundle…**. To bring its guest agent and
guest components up to date, run **Actions → Maintenance → Update Guest
Environment** on the stopped VM before starting it again. Core selection and the guest
environment update are separate steps. [Upstream upgrade notes](https://github.com/Lakr233/vphone-cli/releases/tag/2.17.1)

## Pentest tools in this fork

In this fork's **VPhone Launchpad**, select a machine → **Actions → Pentest Tools…**.
The tools ship in Launchpad's bundled `VPhone Pentest.app`, independently of the
machine's selected Core Bundle. Guest operations still require compatible APIs;
older Core/guest versions may refuse individual operations. Installing an
upstream Core alone does not add these tools to an upstream Launchpad.

| Feature | What it provides |
| --- | --- |
| [App Inspector / App Browser](Research/Host/launchpad_pentest_tools.md) | App icons, Bundle ID, version/build, PID, entitlements, URL schemes, ATS, sandbox paths, **Static Binary & Manifest Security Scanner** (`MH_PIE`, stack canary, ARC, weak crypto/insecure C APIs, cleartext URLs/secrets, `get-task-allow`), and **Add to MASVS Findings** |
| **Storage Inspector** | Browse app data & App Group containers (`files.list`), preview XML/binary Plists, inspect unencrypted/encrypted SQLite 3 databases & table rows read-only, view JSON/UTF-8/Hex, scan for secrets/JWT/PEM/world-writable permissions, and **Add to MASVS Findings** |
| [Frida Tools](Research/Guest/frida_server.md) | Server and Session in one window as two tabs: official/custom server installation, version checks, authentication and Start/Stop; **Multi-Script Composer** + Quick Presets combining 7 built-in Frida 17 scripts (**SSL Pinning Bypass**, **Jailbreak Detection Bypass**, **App Keychain Dump**, **Biometric Bypass**, **Crypto API Tracer**, **HTTP Request Logger**, **Pasteboard Monitor**) or local scripts, console, private log export and Detach; explicit Keychain profiles scoped by VM/endpoint |
| [Sandbox Diff](Research/Guest/sandbox_diff.md) | Bounded before/after file hashes and metadata; unreadable or unstable paths remain uncertain |
| [Network Diagnostics + PCAP](Research/Guest/network_diagnostics.md) | Reachability checks and interface-wide packet capture with Stop/export for Wireshark |
| [App Logs & Crash Viewer](Research/Guest/app_logs.md) | Process logs collected in bounded batches with gaps, crash report inspection and local export |
| [Deep Link Tester](Research/Guest/deep_link_tester.md) | URL schemes, `applinks:` Associated Domains extraction, categorized **Payload Fuzzer** (`XSS`, `Open Redirect`, `Path Traversal`, `Auth Leak`, `Parser Edge Cases`), filtered **Run History Matrix** with latency, and **Add to MASVS Findings** |
| **Zero-Config Proxy & Burp Assistant** | Automatic Burp Suite & mitmproxy profiles, 1-click PortSwigger CA installation into guest trust store (`trustd`), SSL pinning bypass coordination, and proxy reachability verification |
| **Pasteboard / Clipboard Inspector** | Real-time guest UIPasteboard monitoring, automated secret leakage detection (JWT, API keys, passwords, credit cards), custom payload fuzzer (Unicode, RTF, JSON, format strings), and MASVS-STORAGE-2 report export |
| **Device Environment & Mocking Hub** | Real-time battery state & thermal level simulation via `IOPMPowerSource`, and Face ID / Touch ID biometric authentication mocking (Success, Cancel, Lockout) via `LocalAuthentication` C-API hooks |
| **Runtime Class & Method Inspector** | Dynamic Objective-C runtime class dumper, method tracer with live parameter/return value logging, and 1-click method return value override hooks (`libobjc.A.dylib` C-API on Frida 17) |
| **App Memory Search & Scanner** | Live process memory scanner (`rw-` memory ranges), regex & secret hunter (JWT, RSA/EC private keys, API secrets, passwords, credit cards, custom regex), Frida 17 in-process enumeration generator, and MASVS-STORAGE-1 finding export |
| [Keychain Inspector](Research/Guest/keychain_inspector.md) | Metadata and readable items through the guest agent's access; protected rows stay encrypted and access can differ from the app process; send inspected items to **MASVS Findings** |
| [Evidence & MASVS Export](Research/Guest/evidence_export.md) | Screenshots, logs, app/guest/Core context, hashes, interactive **MASVS Findings Builder**, Markdown (`findings-report.md`) & escaped dark HTML (`findings-report.html`) reports, and a redaction review |
| **Photos & Media Browser** | Browse, search, and filter DCIM camera captures, screenshots, and videos; inline preview with metadata (dimensions, file size, date); direct "Copy Image" to Mac clipboard, "Save…", "Open in Preview.app", and batch "Export Selected…" / "Export All…" to Mac |
| [Export Installed IPA](Research/Guest/ipa_export.md) | Export the installed app bundle; excludes sandbox/Keychain data and performs no decryption |
| [Patch IPA with Frida Gadget](Research/Guest/gadget_patchipa.md) | Embed Gadget/config in an unencrypted iOS IPA and sign a new IPA ad hoc for vphone VMs |
| [Install → Launch → Gadget Session](Research/Host/gadget_deployment.md) | Verify the patched IPA hash, select a VM, install/launch explicitly, and transfer endpoint/token through a temporary USB loopback tunnel |

Start the VM for guest operations, then open the tool from **Pentest Tools**.
After a VM restart, use **Reconnect / Check APIs**. You can also open the hub
with `vphone-launchpad-cli vm pentest <name>`. [Launchpad CLI guide](Documents/en/launchpad/launchpad-cli.md)

- **App Inspector, Binary Scanner, and IPA export** — select an app in App Browser,
  open App Inspector to run **Run Security Scan** (arm64 Mach-O protections, weak APIs,
  URLs, entitlements, and ATS), launch **Storage Inspector…**, or choose
  **Export Installed IPA…** to save its bundle. Use **Install App Package** in App
  Browser to install a test IPA or TIPA.
- **Storage Inspector** — open from the Pentest Hub or App Inspector, choose an app and
  data/App Group root, inspect XML/binary Plists or SQLite tables & rows, run **Scan for Secrets**,
  and add findings directly to the MASVS store.
- **Sandbox Diff** — from the selected app's inspector, open **Sandbox Diff…**,
  capture a baseline, run your test, then select **Scan & Compare**.
- **Frida Tools** — open **Frida Tools**, choose a release on the **Server**
  tab, click **Download & Install → Start**, then switch to the **Session**
  tab. Toggle one or more built-in hooks (or a quick preset) in the **Multi-Script Composer**
  alongside custom JS, enter the endpoint and token, select the app, and choose
  Spawn or Attach. [Frida guest compatibility](Research/Guest/frida_server.md#investigation-lead-missing-opt-in-frida-kernel-relaxations)
- **Network Diagnostics + PCAP** — enter a target for **Test DNS / TCP**.
  Select an interface and filter, then use **Start Capture → Stop → Save PCAP…**.
- **Logs and deep links** — select an app in App Logs & Crash Viewer and
  start App Logs or open Crash Reports. In Deep Link Tester, review URL schemes
  and Associated Domains, test manually or run batches on the **Payload Fuzzer** tab,
  filter the **Run History Matrix**, and add interesting runs to MASVS Findings.
- **Proxy, Pasteboard, and Mocking Hub** — configure upstream Burp Suite/mitmproxy with 1-click CA installation into iOS trust store; monitor guest clipboard for leaked secrets and fuzz with test vectors; simulate synthetic battery levels and mock Face ID / Touch ID authentication results.
- **Runtime Inspector and Memory Scanner** — explore loaded Objective-C/Swift classes, trace method calls in real time, force method return values to bypass checks, and scan writable live process memory (RAM/Heap) for leaked credentials and tokens.
- **Keychain, MASVS Findings, and Evidence Export** — select an app and group scope
  for **Scan Metadata** or **Dump Readable Values** (and add flagged rows to MASVS
  Findings). Open **Evidence Export**, manage findings on the **MASVS Findings** tab,
  add attachments or guest screenshots, and run **Prepare Preview → Export Reviewed Evidence…**
  to generate redacted `context.txt`, `findings-report.md`, and `findings-report.html`.

For the IPA flow, open **Local IPA Tools → Patch IPA with Frida Gadget…**.
Choose an unencrypted IPA and download or select iOS Gadget. You can patch
with the VM stopped. Select a running VM for deployment, then use **Install Patched IPA → Launch App → Open Gadget Session**,
then **Test Connection → Attach Gadget**. USB transport selects the target VM's
UDID and reaches guest loopback without adding a guest network listener.
Keep the target app foreground and the VM unlocked during testing. Encrypted
IPAs and physical-device signing/provisioning are outside this patcher's scope.

For repeatable checks with synthetic data, see the
[QA fixture and recorded results](Research/Host/pentest_qa_20261109.md), including
the observed Keychain and log-capture limitations.
The fixture also includes [app-context jailbreak checks](Research/Guest/jailbreak_detection_fixture.md)
with individual observations and an inconclusive result when no selected signal is found.
Build it with `zsh VPhoneLaunchpad/Tests/BuildPentestFixture.sh`, install the
generated `.build/pentest-qa-fixture/PentestFixture.ipa` through **App Browser →
Install App Package**, then open **VPhone Pentest QA → Run jailbreak checks**
inside the guest. Use the unpatched fixture for the baseline.

Keep VM folders, exported evidence, patched IPAs and signing credentials outside
Git. Evidence may retain identifying metadata; text redaction does not redact
screenshots or PCAP payloads. Use synthetic apps/data for public examples.

With the fork's Core selected, use **Data → Photos** in the VM window (or **Pentest Tools → Photos & Media Browser…**) to open the dedicated media browser to preview, copy to clipboard, or export camera roll photos, screenshots, and videos directly to your Mac.

Use **Features → Source: Mac Camera…** in the
VM window, choose a camera, and click **Start Streaming**. Allow macOS Camera
access when prompted. [Mac camera setup](Research/Guest/mac_camera_local.md)

Open **Network → Proxy…** in the VM window, enable the proxy, enter the host
and port reachable from the guest, and click **Apply**. Use
**Import CA Certificate…** to add your test CA. [Proxy and CA setup](Research/Guest/proxy_menu.md)

For Xcode or Instruments, enable **Diagnostics → Keep Developer Tunnel Open**
in the running VM's window so the guest stays listed as online.

## Host-side fixes in this fork

Beyond the upstream sync, this fork carries host-side and workflow fixes found while running the fork day to day:

- **Pentest & Frida Tools** — Unified Frida Tools with 7 built-in safe scripts, storage/binary/deep-link inspectors, photos browser, and MASVS reporting.
- **Guest Stability & VSOCK** — Resolved transient disconnection blips, single-threaded VSOCK event loop, and localized error reporting.
- **Workflow & Launchpad** — Direct Pentest menu in VM window, real transfer progress, preset switching, HTTPS proxy verification, and bounded log streaming.
- **Firmware & Build** — Extended catalog through iOS 27.2.1, unmount retry handling, and consolidated pure-Swift `VPhonePentestKit`.

See [Host-side fork fixes](Research/Host/fork_fixes.md) for the complete list and technical breakdown.

## Set up with an AI agent

After cloning, open the `vphone-cli` folder as your agent's workspace on the
Mac that will run the VM. For a terminal-based agent, start it from the
checkout directory. Paste the prompt below. Replace `<vm-name>` with the name
of an existing test VM, or omit the sentence starting with “Start the existing
test VM” to finish after the setup checks.

```text
Build and install this fork's VPhone Launchpad from the current checkout.
Use the Prepare your Mac and Install the fork sections of README.md.
Read AGENTS.md, Skills/vphone-guest-control/SKILL.md and its relevant local
references, plus Research/Host/fork_build.md for fork-specific signing.

Check macOS, Apple Silicon, Xcode's iPhoneOS SDK, available disk space,
the local signing identity and any existing Launchpad installation.
Build and sign Launchpad with the matching local identity, then verify
the signature. Install the signed app in Applications and open Host Setup.
Ask before replacing an existing app, creating a VM or changing its Core.
Let me handle Recovery settings, administrator prompts and credential entry.
Keep passwords and private signing keys in macOS Keychain or the system prompt.

Use vphone-launchpad-cli status and vm list to verify Host Setup and find a
compatible Core Bundle. Install a compatible Core if one is needed.
Start the existing test VM <vm-name>, wait for the guest connection, and open
its Pentest Tools with vphone-launchpad-cli vm pentest <vm-name>.
Report the installed app path, Core version and where to open the tools.
```

For fork-specific features, [open an issue here](https://github.com/NonBytes/vphone-cli/issues).
For the original project, see [upstream issues](https://github.com/Lakr233/vphone-cli/issues).

## Acknowledgements

- [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli), the upstream project
- [wh1te4ever/super-tart-vphone-writeup](https://github.com/wh1te4ever/super-tart-vphone-writeup)
- [OpenAVB](https://github.com/owngoal-dev/OpenAVB) and [OpenSEP](https://github.com/owngoal-dev/OpenSEP), the boot ROMs used by new VMs

## License

[MIT](LICENSE). Bundled third-party components retain their own license notices.
