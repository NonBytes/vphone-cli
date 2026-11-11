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

5. Pair this fork's **Launchpad 2.16.1** with a **2.16.x Core Bundle** in
   Launchpad, then create or select a test VM and start it. For this fork's camera and
   proxy/CA tools, build and install the fork's Core separately and select it
   using **Actions → Change Core Bundle…** while the VM is stopped.
   [Core version matching](Documents/en/get-started/downloads.md) · [Build and install Core](Research/Host/fork_build.md#optional-core-bundle-build) · [Core Bundles and local builds](Documents/en/launchpad/core-bundles.md)

### Upgrade an existing VM from 2.15

Install the 2.16 Launchpad and Core together. Stop the VM and select its new
Core with **Actions → Change Core Bundle…**. To bring its guest agent and
guest components up to date, run **Actions → Maintenance → Update Guest
Environment** on the stopped VM before starting it again. Core selection and the guest
environment update are separate steps. [Upstream upgrade notes](https://github.com/Lakr233/vphone-cli/releases/tag/2.16.1)

## Pentest tools in this fork

In this fork's **VPhone Launchpad**, select a machine → **Actions → Pentest Tools…**.
The tools ship in Launchpad's bundled `VPhone Pentest.app`, independently of the
machine's selected Core Bundle. Guest operations still require compatible APIs;
older Core/guest versions may refuse individual operations. Installing an
upstream Core alone does not add these tools to an upstream Launchpad.

| Feature | What it provides |
| --- | --- |
| [App Inspector / App Browser](Research/Host/launchpad_pentest_tools.md) | App icons, Bundle ID, version/build, PID, entitlements, URL schemes, ATS and sandbox paths |
| [Frida Tools](Research/Guest/frida_server.md) | Server and Session in one window as two tabs: official/custom server installation, version checks, authentication and Start/Stop; then Spawn/Attach (server or Gadget) with built-in or local scripts, console, private log export and Detach; explicit Keychain profiles scoped by VM/endpoint |
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
- **Frida Tools** — open **Frida Tools**, choose a release on the **Server**
  tab, click **Download & Install → Start**, then switch to the **Session**
  tab. Enter the reachable endpoint and token, select the app, and choose
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

For Xcode or Instruments, enable **Diagnostics → Keep Developer Tunnel Open**
in the running VM's window so the guest stays listed as online.

## Host-side fixes in this fork

Beyond the upstream sync, this fork carries a few host-side fixes found while
running the fork day to day. Build a fresh Core Bundle and Launchpad (see
[Install the fork](#install-the-fork)) to pick them up.

- **`cfw update-environment` / `cfw install` no longer fail on a transient
  "Resource busy" unmount.** Right after a file on a freshly mounted volume is
  re-signed, macOS can briefly hold it open (code-signing re-scan, Spotlight),
  so unmounting right afterward could fail and abort the whole run with the
  volume otherwise fully patched. The unmount now retries for about a second
  before falling back to a forced unmount, so the run completes instead of
  needing a manual retry.
- **Firmware catalog extended to iOS 27.2 and 27.2.1 for every supported
  iPhone and iPad.** The built-in list of restore-IPSW ↔ cloudOS pairings
  previously stopped at 27.0.1 for most models, even though Apple has since
  shipped 27.2 and 27.2.1. New Machine now offers the newest release by
  default, and `vm create` resolves it the same way. Verified end to end: a
  fresh VM built on 27.2.1 restores, installs CFW and boots.
- **Launchpad's Patches inspector no longer shows "Unavailable" for a large
  patch set, such as the `frida` preset.** A big preset's `fw patches --json`
  output is long enough that an internal line-buffer limit was silently
  dropping the start of the document before Launchpad could parse it, even
  though the command itself had already succeeded — so the inspector had no
  way to tell the difference from a real failure. The **Update Kernel** and
  **Apply to Guest** buttons now appear and work for `frida` and any other
  large preset, with no restore needed for the kernel patches. The same fix
  covers `vm leases` and `vm template list`, which can grow the same way.
- **Switching an existing machine's preset now actually works from
  Launchpad.** The Patches inspector's **Edit…** used to only show the
  current choice; picking a different preset (`standard` → `frida`, say) had
  to go through the CLI by hand. It now saves the change and, if the machine
  is stopped, chains **Update Kernel** and **Apply to Guest** right after, so
  switching preset is one step instead of three.
- **New Machine shows which Core Bundle its firmware list is reading from.**
  With more than one Core Bundle installed, the Device/iOS pickers read from
  whichever one is chosen in Advanced Options → Firmware — easy to miss, and
  the usual reason a newer iOS release doesn't show up. The basic page now
  names that Core Bundle directly, with a one-click way to change it.
- **`scripts/check-firmware-catalog.zsh`** flags any device already in the
  firmware catalog that Apple has since signed a newer build for, by
  checking against [ipsw.me](https://ipsw.me). It only reports; adding the
  pairing is still a manual edit.
- **Building VPhoneLaunchpad through the full workspace no longer fails on a
  package-pin mismatch.** A dependency had been bumped for Launchpad alone
  without updating the workspace's own pin, so a clean build through
  `VPhone.xcworkspace` always failed a licence-staging check. Every pin now
  agrees.
- **The VM window's File Browser shows real transfer progress.** Uploading or
  downloading a large file used to jump its progress bar straight from 0% to
  100%, since the whole file moved in one step with no way to see partway.
  It now reports progress as the file actually moves across the connection.
- **Frida Session has two built-in scripts: SSL Pinning Bypass and Jailbreak
  Detection Bypass.** Previously every session needed a local `.js` file
  chosen by hand, even for the two checks almost every test starts with.
  Pick one from the new **Built-in Scripts** menu next to Choose Script…;
  anything more specific to the target still needs its own script.
- **Frida Server and Frida Session are one window now: Frida Tools.**
  Switching to a session before starting the guest's Frida server used to
  dead-end with "go start it in the other window." They're two tabs of the
  same window today, so starting the server and starting a session no
  longer means leaving one window to find the other.
- **The VM window's own Features menu can open Pentest Tools directly.**
  Pentest Tools ships with Launchpad, not the VM, so using it used to mean
  switching to Launchpad, finding this machine, and opening its Actions
  menu. **Features → Pentest Tools…** now opens it for this machine without
  leaving the VM window, as long as Launchpad is installed.
- **The guest connection no longer flaps on a single transient reset.**
  A health check that failed once — a brief guest-side hiccup from SEP or
  display work — used to flip the whole UI to "Disconnected" immediately,
  even though the very next check a second later would have succeeded. It
  now retries a couple of times first; only a connection that stays down
  reports as disconnected.
- **A failed guest shell/port-relay operation (used by Frida's "Use guest
  transport" option) now shows its real error instead of a raw error
  code.** Its error type was missing the piece that lets `.localizedDescription`
  read its message, so a failure showed as `(VPhoneVirtualMachineKit.
  VPhoneGuestControl.ControlError error 5.)` instead of what actually went
  wrong.
- **Frida Session's app picker is a proper list now, not a menu of
  one-line text.** Picking the app to Spawn or Attach to used to be a
  dropdown with the icon, name, bundle ID and PID all squeezed onto one
  line. It's a popover list now, each row its own icon, name, bundle ID
  and PID.

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
