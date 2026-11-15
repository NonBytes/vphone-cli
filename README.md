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
Already cloned the fork? Use the [AI agent quick setup](#quick-setup-with-an-ai-agent-recommended).

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

## Quick setup with an AI agent (Recommended)

The easiest way to install and configure this fork: clone the repository, open the `vphone-cli` folder as your agent's workspace (Antigravity, Claude Code, Cursor, Codex, etc.), and paste the prompt below. The agent will inspect your Mac environment, configure local code-signing identities, build Launchpad, install it to `/Applications`, and guide you through Host Setup automatically.

```sh
git clone https://github.com/NonBytes/vphone-cli.git
cd vphone-cli
```

Paste this prompt into your AI agent:

```text
Build and install this fork's VPhone Launchpad from the current checkout.
Use the Prepare your Mac and Manual installation sections of README.md.
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

Replace `<vm-name>` with the name of an existing test VM, or omit the sentence starting with “Start the existing test VM” to finish after setup checks.

## Manual installation

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
| [App Inspector / App Browser](Research/Host/launchpad_pentest_tools.md) | App icons, Bundle ID, version/build, PID, entitlements, URL schemes, ATS, sandbox paths, **App Framework & Tech Stack Detection** (Native Swift/ObjC, Flutter Dart AOT, React Native Hermes/JSC, Unity IL2CPP, Cordova/Capacitor, .NET MAUI/Xamarin, Unreal), **Commercial Protector & RASP Detection** (DexProtector/Licel, iXGuard, Promon SHIELD, Talsec freeRASP, AppSealing, Arxan), anti-debug/anti-jailbreak heuristics, **Tailored Pentest Guidance**, **Static Binary & Manifest Security Scanner** (`MH_PIE`, stack canary, ARC, weak crypto/insecure C APIs, cleartext URLs/secrets, `get-task-allow`), and **Add to MASVS Findings** |
| **Storage Inspector** | Browse app data & App Group containers (`files.list`), preview XML/binary Plists, interactive SQLite 3 database & table row browser, live in-app SQL query runner with mutations and commit back to guest (`files.write`), direct **Export to Mac…** and **Open in Default Mac App** (DB Browser / Xcode / VS Code), selectable & 1-click copyable container paths, scan for secrets/JWT/PEM/world-writable permissions, and **Add to MASVS Findings** |
| **File Browser** | Full-featured interactive guest filesystem explorer with double-click and Return-key folder navigation, forward/back/parent history, editable path bar with "Go", quick-jump presets (`App Data`, `App Bundles`, `Mobile Home`, `DCIM`, `Root`), file upload from Mac (`control.uploadFile`), download to Mac (`control.pullFile`), new directory creation, deletion, copy path, and automatic deep-link reveal from App Inspector for Data Containers and App Bundles |
| **In-App Network & API Flow Inspector** | Real-time HTTP/HTTPS transaction capture (`NSURLSession` / `CFNetwork`), status/method filtering, formatted request/response headers and body viewers, 1-click cURL generator, in-app request tampering and replay engine (`[Replay]`), active **Map Local / Rewrite / Drop Mock Rules Engine** directly in-process without external proxy tools, and HAR 1.2 export for Postman/Proxyman |
| **SSL Pinning & Jailbreak Bypass Studio** | Multi-engine runtime evasion studio with real-time toggleable modules: SecTrustEvaluate / TrustKit SSL unpinning, Jailbreak & Root detection cloaking (file checks, dyld hooks, fork/syscall, C-API stat bypass), dynamic Frida script synthesis, and event log telemetry |
| **Dynamic Crypto Tracer & Key Sniffer** | Dynamic cryptanalysis engine hooking CommonCrypto (`CCCrypt`, `CCHmac`, `CC_MD5`, `CC_SHA*`), SecKey, and Apple CryptoKit; detects insecure ECB modes, hardcoded/static IVs, weak keys, and deprecated hashes in real time, with MASVS-CRYPTO finding export |
| **Mach-O & Entitlements Security Visualizer** | Interactive 64-bit Mach-O binary inspector: visual hardening status grid (PIE, Stack Canary, ARC, W^X stack, FairPlay cryptid), search & danger rating for sensitive entitlements, dynamic library & RPATH search paths, load commands viewer, and raw XML export |
| **Sandbox File Watcher & File Integrity Monitor (FIM)** | Real-time app container filesystem watcher (`Documents/`, `Caches/`, `Preferences/`, `Application Support/`, `tmp/`), Frida C hooks, optional Foundation hooks when the ObjC bridge is available, and recursive guest polling for creates, writes, and deletes, automated detection of leaked JWTs/secrets/unencrypted SQLite DBs/sensitive plist keys, 1-click **Add to MASVS Findings**, and CSV/JSON timeline export |
| [Frida Tools](Research/Guest/frida_server.md) | Server, Session, and **REPL Console** in one window as three tabs: official/custom server installation, version checks, authentication and Start/Stop; **Multi-Script Composer** + Quick Presets combining 7 built-in Frida 17 scripts (**SSL Pinning Bypass**, **Jailbreak Detection Bypass**, **App Keychain Dump**, **Biometric Bypass**, **Crypto API Tracer**, **HTTP Request Logger**, **Pasteboard Monitor**) or local scripts, console, private log export and Detach; explicit Keychain profiles scoped by VM/endpoint |
| **Frida Live REPL & Interactive Scratchpad** | Integrated live JavaScript scratchpad and REPL console; single & multi-line command execution directly in the target iOS process, command history navigation, built-in pentest snippets library (UI view hierarchy, loaded modules, pasteboard, ptrace bypass), and real-time output stream |
| **Protector & RASP Dynamic Decryptor** | Dedicated runtime string, URL, and anti-tamper sniffer intercepting decryption engines across commercial protectors (DexProtector/Licel, iXGuard, Promon SHIELD, Talsec freeRASP); live plaintexts capture, searchable stream, and JSON export |
| [Sandbox Diff](Research/Guest/sandbox_diff.md) | Bounded before/after file hashes and metadata; unreadable or unstable paths remain uncertain |
| [Network Diagnostics + PCAP](Research/Guest/network_diagnostics.md) | Reachability checks and interface-wide packet capture with Stop/export for Wireshark |
| [App Logs & Crash Viewer](Research/Guest/app_logs.md) | Process logs collected in bounded batches with gaps, crash report inspection and local export |
| [Deep Link Tester](Research/Guest/deep_link_tester.md) | URL schemes, `applinks:` Associated Domains extraction, categorized **Payload Fuzzer** (`XSS`, `Open Redirect`, `Path Traversal`, `Auth Leak`, `Parser Edge Cases`), filtered **Run History Matrix** with latency, and **Add to MASVS Findings** |
| **Zero-Config Proxy & Burp Assistant** | Automatic Burp Suite & mitmproxy profiles, 1-click PortSwigger CA installation into guest trust store (`trustd`), SSL pinning bypass coordination, and proxy reachability verification |
| **Pasteboard / Clipboard Inspector** | Real-time guest UIPasteboard monitoring, automated secret leakage detection (JWT, API keys, passwords, credit cards), custom payload fuzzer (Unicode, RTF, JSON, format strings), and MASVS-STORAGE-2 report export |
| **Device Environment & Mocking Hub** | Real-time battery state & thermal level simulation via `IOPMPowerSource`, and Face ID / Touch ID biometric authentication mocking (Success, Cancel, Lockout) via `LocalAuthentication` C-API hooks. Supports software UI gate bypass and edge-case simulation; see Biometric Boundaries below for Secure Enclave (SEP) hardware constraints |
| **Runtime Class & Method Inspector** | Dynamic Objective-C runtime class dumper, method tracer with live parameter/return value logging, and 1-click method return value override hooks (`libobjc.A.dylib` C-API on Frida 17) |
| **App Memory Search & Scanner** | Live process memory scanner (`rw-` memory ranges), regex & secret hunter (JWT, RSA/EC private keys, API secrets, passwords, credit cards, custom regex), Frida 17 in-process enumeration generator, and MASVS-STORAGE-1 finding export |
| **Automated MASVS Compliance & Audit** | 1-click Static & **Dynamic MASVS Test Runner**; spawns target process, probes live pasteboard isolation, in-memory heap secret retention, biometric policy resilience, and sandbox storage security alongside 12 binary checks; executive score & grade (A+ to F), standalone HTML/Markdown reports with dynamic badges, and 1-click export to Evidence Store |
| **Flutter BoringSSL Unpinning Assistant** | Multi-strategy Frida 17 unpinning script generator for Flutter iOS apps; in-memory ARM64 BoringSSL verification prologue pattern scanner (`Memory.scanSync`), export resolver, 1-click script copy, and file export |
| **Hermes & React Native Bundle Inspector** | Extracts `main.jsbundle` / `index.bundle`, parses Hermes Bytecode (HBC) magic/version header, and runs an automated secret miner across API keys (Google/Firebase, AWS, Stripe), JWT tokens, private keys, and internal backend endpoints with 1-click JSON/bundle export |
| **APFS Instant Snapshot & Rollback Hub** | Zero-copy instant VM snapshots using macOS APFS Copy-on-Write (`clonefile`); snapshot state timeline, 1-click instant rollback, machine locking and recovery of the original state if a rollback fails |
| [Keychain Inspector & Injector](Research/Guest/keychain_inspector.md) | Metadata scan, secret dump, **Security Audit Summary Bar** (counts for High Risk, Medium Risk, Best Practice), **Issues Only filter**, OWASP MASVS risk evaluation (deprecated `AccessibleAlways` detection, missing `ThisDeviceOnly` check, sensitive token plaintext heuristics), live value editing (`SecItemUpdate`), item deletion (`SecItemDelete`), new item injection (`SecItemAdd`, enabled by default via `system-securityd-exp-keychain_eligibility` in the `pentest` preset on iOS 27.2+; or synthesize in-app Frida scripts), in-app Frida QuickJS script synthesis, and 1-click **Add All Issues to MASVS Findings** |
| **Binary Diff & Baseline Scanner** | Deep structural Mach-O binary & IPA comparison (Base/Prod vs Target/Staging), security regression detection (PIE, Stack Canary, W^X Executable Stack, ARC, FairPlay, sensitive entitlements like `get-task-allow`, suspicious injected dylibs), visual split-view inspector, and 1-click export to MASVS Findings (MASVS-CODE-1 / CODE-4) |
| **Live Exception & Crash Signal Monitor** | Frida native exception events and Objective-C throws, available fault address and ARM64 registers (`PC`, `LR`, `SP`, `FP`), symbolicated backtraces, Frida 17 QuickJS sentinel script synthesizer, and 1-click export to MASVS Findings (MASVS-RESILIENCE-1) |
| [Evidence & MASVS Export](Research/Guest/evidence_export.md) | Screenshots, logs, app/guest/Core context, hashes, interactive **MASVS Findings Builder**, Markdown (`findings-report.md`) & escaped dark HTML (`findings-report.html`) reports, and a redaction review |
| **Photos & Media Browser** | Browse, search, and filter DCIM camera captures, screenshots, and videos; inline preview with metadata (dimensions, file size, date); direct "Copy Image" to Mac clipboard, "Save…", "Open in Preview.app", and batch "Export Selected…" / "Export All…" to Mac |
| [Export Installed IPA](Research/Guest/ipa_export.md) | Export the installed app bundle; excludes sandbox/Keychain data and performs no decryption |
| [Patch IPA with Frida Gadget](Research/Guest/gadget_patchipa.md) | Embed Gadget/config in an unencrypted iOS IPA and sign a new IPA ad hoc for vphone VMs |
| [Install → Launch → Gadget Session](Research/Host/gadget_deployment.md) | Verify the patched IPA hash, select a VM, install/launch explicitly, and transfer endpoint/token through a temporary USB loopback tunnel |

Start the VM for guest operations, then open tools from **Actions → Pentest Tools…** or via CLI:
```sh
vphone-launchpad-cli vm pentest <name>
```

### Workflows

- **App & Storage Analysis** — Select an app in App Browser to run **Run Security Scan** (detects frameworks, DexProtector/iXGuard/Promon RASP, and binary hardening), or inspect files via **Storage Inspector** (live SQLite/Plist editor) and **File Browser** (double-click navigation, upload/download, and 1-click **Show in Files** from App Inspector).
- **Runtime Instrumentation & Evasion** — Open **Frida Tools** with `--preset pentest` (enables kernel relaxations and keychain eligibility out of the box). Capture HTTP/HTTPS traffic in **Network Flow Inspector** with request tampering/replay, or toggle SSL unpinning and jailbreak cloaking in **Bypass Studio**.
- **Mocking & Biometrics** — Simulate battery states, thermal levels, and mock Face ID / Touch ID authentication via `LocalAuthentication` hooks. *(SEP hardware-bound private keys remain inside the Secure Enclave).*
- **Audit, Diffing & Evidence** — Run 1-click **Automated MASVS Compliance** checks, capture zero-copy **APFS Snapshots** for instant rollback, detect regressions in **Binary Diff**, and compile redacted reports in **Evidence Export**.
- **IPA Tools & Gadget Injection** — Embed Frida Gadget in unencrypted IPAs via **Local IPA Tools → Patch IPA with Frida Gadget…**, or export installed app bundles via **Export Installed IPA…**.

### VM Integrations (Core Bundle)

- **Photos & Media**: Open **Data → Photos** (or **Photos & Media Browser…**) to preview and export guest DCIM media to Mac.
- **Mac Camera**: Stream host camera input into the VM via **Features → Source: Mac Camera…**.
- **Proxy & CA**: Configure upstream proxies and install root CAs in **Network → Proxy…**.
- **Developer Tunnel**: Enable **Diagnostics → Keep Developer Tunnel Open** for Xcode/Instruments connectivity.

## Host-side fixes in this fork

Beyond the upstream sync, this fork carries host-side and workflow fixes found while running the fork day to day:

- **Pentest Preset, Tech Stack Engine & Frida Tools** — Shipped `pentest` preset (renamed from `frida`) enabling Frida kernel relaxations plus `securityd` keychain eligibility out of the box, automatic App Framework & Commercial Protector (DexProtector/iXGuard/Promon/Talsec) detection engine with tailored reverse engineering guidance, unified Frida Tools with 7 built-in safe scripts, storage/binary/deep-link inspectors, photos browser, and MASVS reporting.
- **Guest Stability & VSOCK** — Resolved transient disconnection blips, single-threaded VSOCK event loop, and localized error reporting.
- **Workflow & Launchpad** — Direct Pentest menu in VM window, real transfer progress, preset switching, HTTPS proxy verification, and bounded log streaming.
- **Firmware & Build** — Extended catalog through iOS 27.2.1, unmount retry handling, and consolidated pure-Swift `VPhonePentestKit`.

See [Host-side fork fixes](Research/Host/fork_fixes.md) for the complete list and technical breakdown.

For fork-specific features, [open an issue here](https://github.com/NonBytes/vphone-cli/issues).
For the original project, see [upstream issues](https://github.com/Lakr233/vphone-cli/issues).

## Acknowledgements

- [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli), the upstream project
- [wh1te4ever/super-tart-vphone-writeup](https://github.com/wh1te4ever/super-tart-vphone-writeup)
- [OpenAVB](https://github.com/owngoal-dev/OpenAVB) and [OpenSEP](https://github.com/owngoal-dev/OpenSEP), the boot ROMs used by new VMs

## License

[MIT](LICENSE). Bundled third-party components retain their own license notices.
