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

5. Install a Core Bundle from the same version series in Launchpad, then
   create or select a test VM and start it. For this fork's camera and
   proxy/CA tools, build and install the fork's Core separately and select it
   using **Actions → Change Core Bundle…** while the VM is stopped.
   [Core version matching](Documents/en/get-started/downloads.md) · [Build and install Core](Research/Host/fork_build.md#optional-core-bundle-build)

## Pentest tools in this fork

In this fork's **VPhone Launchpad**, select a machine → **Actions → Pentest Tools…**.
The tools ship in Launchpad's bundled `VPhone Pentest.app`, independently of the
machine's selected Core Bundle. Guest operations still require compatible APIs;
older Core/guest versions may refuse individual operations. Installing an
upstream Core alone does not add these tools to an upstream Launchpad.

| Feature | What it provides |
| --- | --- |
| [App Inspector / App Browser](Research/Host/launchpad_pentest_tools.md) | App icons, Bundle ID, version/build, PID, entitlements, URL schemes, ATS and sandbox paths |
| [Frida Server](Research/Guest/frida_server.md) | Official/custom server installation, version checks, authentication and Start/Stop |
| [Frida Session](Research/Host/gadget_sessions.md) | Server Spawn/Attach or Gadget Attach, local scripts, console, private log export and Detach; explicit Keychain profiles scoped by VM/endpoint |
| [Sandbox Diff](Research/Guest/sandbox_diff.md) | Bounded before/after file hashes and metadata; unreadable or unstable paths remain uncertain |
| [Network Diagnostics + PCAP](Research/Guest/network_diagnostics.md) | Reachability checks and interface-wide packet capture with Stop/export for Wireshark |
| [App Logs & Crash Viewer](Research/Guest/app_logs.md) | Process logs collected in bounded batches with gaps, crash report inspection and local export |
| [Deep Link Tester](Research/Guest/deep_link_tester.md) | URL schemes, editable payloads and test history |
| [Keychain Inspector](Research/Guest/keychain_inspector.md) | Metadata and readable items through the guest agent's access; protected rows stay encrypted and access can differ from the app process |
| [Evidence Export](Research/Guest/evidence_export.md) | Screenshots, logs, app/guest/Core context, hashes and a redaction review |
| [Export Installed IPA](Research/Guest/ipa_export.md) | Export the installed app bundle; excludes sandbox/Keychain data and performs no decryption |
| [Patch IPA with Frida Gadget](Research/Guest/gadget_patchipa.md) | Embed Gadget/config in an unencrypted iOS IPA and sign a new IPA ad hoc for vphone VMs |
| [Install → Launch → Gadget Session](Research/Host/gadget_deployment.md) | Verify the patched IPA hash, select a VM, install/launch explicitly, and transfer endpoint/token through a temporary USB loopback tunnel |

Start the VM for guest operations, then open the tool from **Pentest Tools**.
After a VM restart, use **Reconnect / Check APIs**. You can also open the hub
with `vphone-launchpad-cli vm pentest <name>`. [Launchpad CLI guide](Documents/en/launchpad/launchpad-cli.md)

- **App Inspector and IPA export** — select an app in App Browser, open
  App Inspector, then choose **Export Installed IPA…** to save its bundle.
  Use **Install App Package** in App Browser to install a test IPA or TIPA.
- **Sandbox Diff** — from the selected app's inspector, open **Sandbox Diff…**,
  capture a baseline, run your test, then select **Scan & Compare**.
- **Frida Server and Session** — choose a release in Frida Server, click
  **Download & Install → Start**, then open Frida Session in **Frida Server**
  mode. Enter the reachable endpoint and token, select the app, and choose
  Spawn or Attach. [Frida guest compatibility](Research/Guest/frida_server.md#investigation-lead-missing-opt-in-frida-kernel-relaxations)
- **Network Diagnostics + PCAP** — enter a target for **Test DNS / TCP**.
  Select an interface and filter, then use **Start Capture → Stop → Save PCAP…**.
- **Logs and deep links** — select an app in App Logs & Crash Viewer and
  start App Logs or open Crash Reports. In Deep Link Tester, select an app,
  enter a URL, and click **Open URL in Selected App**.
- **Keychain and evidence** — select an app and group scope for **Scan Metadata**
  or **Dump Readable Values**. In Evidence Export, add files or a guest screenshot,
  then use **Prepare Preview → Export Reviewed Evidence…**.

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

With the fork's Core selected, use **Features → Source: Mac Camera…** in the
VM window, choose a camera, and click **Start Streaming**. Allow macOS Camera
access when prompted. [Mac camera setup](Research/Guest/mac_camera_local.md)

Open **Network → Proxy…** in the VM window, enable the proxy, enter the host
and port reachable from the guest, and click **Apply**. Use
**Import CA Certificate…** to add your test CA. [Proxy and CA setup](Research/Guest/proxy_menu.md)

## Let an agent do it

```text
Set up vphone on this Mac. Read the upstream skill at
https://raw.githubusercontent.com/Lakr233/vphone-cli/main/Skills/vphone-guest-control/SKILL.md
and its references. Check the existing host setup, machines and free space.
For NonBytes' pentest tools, also read this fork's build/install guide:
https://raw.githubusercontent.com/NonBytes/vphone-cli/main/Research/Host/fork_build.md
and its Launchpad tools guide:
https://raw.githubusercontent.com/NonBytes/vphone-cli/main/Research/Host/launchpad_pentest_tools.md
Use the fork's Launchpad for those tools; an upstream Core alone is insufficient.
Do not change SIP, boot-args or other host security settings, create a VM,
replace an installed app or change a VM's Core binding until I authorize it.
When administrator credentials or account sign-in are needed, let me handle them.
Never ask me to send passwords or private signing keys in chat.
```

For fork-specific features, [open an issue here](https://github.com/NonBytes/vphone-cli/issues).
For the original project, see [upstream issues](https://github.com/Lakr233/vphone-cli/issues).

## Acknowledgements

- [Lakr233/vphone-cli](https://github.com/Lakr233/vphone-cli), the upstream project
- [wh1te4ever/super-tart-vphone-writeup](https://github.com/wh1te4ever/super-tart-vphone-writeup)
- [OpenAVB](https://github.com/owngoal-dev/OpenAVB) and [OpenSEP](https://github.com/owngoal-dev/OpenSEP), the boot ROMs used by new VMs

## License

[MIT](LICENSE). Bundled third-party components retain their own license notices.
