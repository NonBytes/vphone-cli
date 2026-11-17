<div align="right"><a href="Documents/en/README.md">Docs</a> · <strong>English</strong> · <a href="Documents/zh/README.md">中文</a> · <a href="Documents/ja/README.md">日本語</a> · <a href="Documents/ko/README.md">한국어</a></div>

# vphone-cli (Pentest Edition)

[![Release](https://img.shields.io/github/v/release/NonBytes/vphone-pentest?color=blue&label=Latest%20Release)](https://github.com/NonBytes/vphone-pentest/releases/latest)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015%2B%20(Apple%20Silicon)-lightgrey.svg)](https://support.apple.com)

Run a virtual iPhone or iPad on an Apple Silicon Mac for security research, reverse engineering, and mobile penetration testing.

This is [NonBytes' fork](https://github.com/NonBytes/vphone-pentest) of
[Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli), featuring 17 integrated iOS pentest tools, unified system camera with 4-way rotation, guest SOCKS5 pivoting tunnel, and per-VM proxy/CA management.

> 🚀 **Quick Download**: Grab the signed app from [Latest Releases](https://github.com/NonBytes/vphone-pentest/releases/latest) (`vphone-launchpad-v2.17.1-arm64.zip`) without compiling.

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

Clone the repo, open the `vphone-cli` workspace in your AI agent (Antigravity, Claude Code, Cursor, Codex), and paste:

```text
Build and install VPhone Launchpad from this repository following README.md and Research/Host/fork_build.md:
1. Check macOS, Apple Silicon, Xcode (iPhoneOS SDK), and local code-signing identity.
2. Build, sign with the local identity, verify, and install to /Applications.
3. Launch the app and verify Host Setup via vphone-launchpad-cli status.
4. If a VM name is provided (<vm-name>), start it and open Pentest Tools via vphone-launchpad-cli vm pentest <vm-name>.
```

## Manual installation

1. Install Xcode with the iPhoneOS SDK and clone the fork.

   ```sh
   git clone https://github.com/NonBytes/vphone-pentest.git
   cd vphone-pentest
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

### VM Controls & Hotkeys

When running a VM, the following global hotkeys and built-in controls are available:

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `⌃⌘R` (`Ctrl+Cmd+R`) | **Cycle Camera Rotation** | Rotates camera feed 90° clockwise (`0° → 90° → 180° → 270°`) to fix iPad/landscape orientation |
| `⌃⌘P` (`Ctrl+Cmd+P`) | **Open Pentest Tools** | Opens the Pentest Tools Hub for the active VM |
| `⌃⌘F` (`Ctrl+Cmd+F`) | **Open Frida Tools** | Opens the Frida Server, Session & Multi-Script Composer window |

**Built-in Fork Enhancements:**
- **Unified Camera with 4-Way Rotation**: Native GPU-accelerated rotation & aspect-fit letterboxing directly in the system camera pipeline (no external helper app needed).
- **SOCKS5 Pivoting Tunnel**: Route Mac traffic (Burp Suite, curl, browsers) through the VM's network environment via `socks5://<guest-ip>:1080`.
- **Per-VM HTTP/HTTPS Proxy & CA**: 1-click PortSwigger Burp CA injection into `trustd` and automatic system proxy configuration.

## Fork Details & Issues

See [Host-side fork fixes](Research/Host/fork_fixes.md) for changes beyond upstream, and [open an issue here](https://github.com/NonBytes/vphone-pentest/issues) for fork-specific bugs (or [upstream issues](https://github.com/Lakr233/vphone-cli/issues) for the original project).

## Acknowledgements

- [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli), the upstream project
- [wh1te4ever/super-tart-vphone-writeup](https://github.com/wh1te4ever/super-tart-vphone-writeup)
- [OpenAVB](https://github.com/owngoal-dev/OpenAVB) and [OpenSEP](https://github.com/owngoal-dev/OpenSEP), the boot ROMs used by new VMs

## License

[MIT](LICENSE). Bundled third-party components retain their own license notices.
