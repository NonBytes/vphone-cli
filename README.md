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

For the IPA flow, open **Local IPA Tools → Patch IPA with Frida Gadget…**.
After patching, use **Install Patched IPA → Launch App → Open Gadget Session**,
then **Test Connection → Attach Gadget**. USB transport selects the target VM's
UDID and reaches guest loopback without adding a guest network listener.
Keep the target app foreground and the VM unlocked during testing. Encrypted
IPAs and physical-device signing/provisioning are outside this patcher's scope.

For repeatable checks with synthetic data, see the
[QA fixture and recorded results](Research/Host/pentest_qa_20261109.md), including
the observed Keychain and log-capture limitations.

Keep VM folders, exported evidence, patched IPAs and signing credentials outside
Git. Evidence may retain identifying metadata; text redaction does not redact
screenshots or PCAP payloads. Use synthetic apps/data for public examples.

Camera and proxy/CA features remain in the VM window and come from its selected
Core: [Mac camera setup](Research/Guest/mac_camera_local.md) and
[proxy/CA setup](Research/Guest/proxy_menu.md). Existing Core panels retain the
UI and capabilities shipped in that Core; use Launchpad's hub for current tools.

## Build and install this fork

Build and sign **this fork's Launchpad** to obtain the current pentest tools.
Building only `VPhone.bundle` does not update Launchpad's bundled tools.
See the [fork build/install guide](Research/Host/fork_build.md) for both outputs,
local signing, helper checks and optional Core installation.

For VM setup, use [Downloads](Documents/en/get-started/downloads.md),
[Create and Run](Documents/en/machines/create-and-run.md), and the
[Launchpad CLI](Documents/en/launchpad/launchpad-cli.md).
Each VM retains its selected Core; opening the tools does not restore a VM or
update its guest environment. Guest/kernel policy and Frida compatibility still
apply; see the [Frida preset investigation](Research/Guest/frida_server.md#investigation-lead-missing-opt-in-frida-kernel-relaxations).

### Let an agent do it

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
