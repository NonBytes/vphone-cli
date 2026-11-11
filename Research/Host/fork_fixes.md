# Host-side fixes in this fork

Beyond the upstream sync, this fork carries host-side and workflow fixes
found while running the fork day to day. Build a fresh Core Bundle and
Launchpad (see [Build and install this fork](fork_build.md)) to pick them up.

## Frida Tools & Built-in Scripts

- **Frida Server and Frida Session are one window now: Frida Tools.**
  Switching to a session before starting the guest's Frida server used to
  dead-end with "go start it in the other window." They are two tabs of the
  same window today, so starting the server and starting a session no longer
  mean leaving one window to find the other.
- **Frida Session has two built-in scripts: SSL Pinning Bypass and Jailbreak
  Detection Bypass.** Previously every session needed a local `.js` file
  chosen by hand, even for the two checks almost every test starts with. Pick
  one from the **Built-in Scripts** menu next to **Choose Script…**; anything
  more specific to the target still needs its own script.
- **Frida Session's app picker is its own process-manager-style window now, not
  a dropdown.** Picking the app to Spawn or Attach to used to be a menu with
  the icon, name, bundle ID and PID all squeezed onto one line. **Choose
  App…** now opens a sortable, searchable table — the same columns App Browser
  uses — and double-click or **Choose** picks one.
- **Fixed: both built-in Frida scripts (SSL Pinning Bypass, Jailbreak Detection
  Bypass) threw `TypeError: not a function` on load.** They called the static
  `Module.findExportByName()`, which Frida 17 removed. They now use
  `Process.findModuleByName(...).findExportByName(...)` for the named-module
  lookup and `Module.findGlobalExportByName(...)` for the global one.
- **Fixed: the built-in Jailbreak Detection Bypass Frida script threw
  `ReferenceError: 'ObjC' is not defined` on Frida 17.** Frida 17 dropped the
  built-in `ObjC` bridge from the default QuickJS runtime, and the VM-window
  copy of the script still accessed `ObjC.available` directly. Both copies now
  check `typeof ObjC !== 'undefined'` first and fall back to resolving
  `-[NSFileManager fileExistsAtPath:]` and `-[UIApplication canOpenURL:]`
  straight through `libobjc.A.dylib` (`objc_getClass`, `sel_registerName`,
  `class_getInstanceMethod`, `method_getImplementation`, `objc_msgSend`), while
  also guarding against null path pointers in the `access()` hook.

## Guest Connection & VSOCK Transport

- **Fixed: intermittent `"The guest agent is not connected"` errors when
  clicking Reload or Start in Frida Tools (or running back-to-back guest
  requests).** When Darwin's `fcntl(F_SETNOSIGPIPE / O_NONBLOCK)` briefly
  returned `EINVAL` on a freshly `accept()`ed VSOCK socket or a child channel
  hopped across SwiftNIO EventLoop threads during setup, the guest closed the
  socket before reading the request and the host mistook the 0-byte read for a
  full guest disconnect. `vphoned` now runs its HTTP/VSOCK server on a
  single-threaded `EventLoopGroup` so accepted sockets stay on the accepting
  loop, and `VPhoneGuestControl.http` distinguishes a mid-request socket drop
  (`connectionLost`) from `notConnected` and automatically retries on a fresh
  VSOCK connection.
- **The guest connection no longer flaps on a single transient reset.** A
  health check that failed once — a brief guest-side hiccup from SEP or display
  work — used to flip the whole UI to "Disconnected" immediately, even though
  the very next check a second later would have succeeded. It now retries a
  couple of times first; only a connection that stays down reports as
  disconnected.
- **A failed guest shell/port-relay operation (used by Frida's "Use guest
  transport" option) now shows its real error instead of a raw error code.** Its
  error type was missing the piece that lets `.localizedDescription` read its
  message, so a failure showed as `(VPhoneVirtualMachineKit.
  VPhoneGuestControl.ControlError error 5.)` instead of what actually went
  wrong.

## Launchpad, VM Window & Workflow

- **The VM window's own Features menu can open Pentest Tools directly.**
  Pentest Tools ships with Launchpad, not the VM, so using it used to mean
  switching to Launchpad, finding this machine, and opening its Actions menu.
  **Features → Pentest Tools…** now opens it for this machine without leaving
  the VM window, as long as Launchpad is installed.
- **The VM window's File Browser shows real transfer progress.** Uploading or
  downloading a large file used to jump its progress bar straight from 0% to
  100%, since the whole file moved in one step with no way to see partway. It
  now reports progress as the file actually moves across the connection.
- **Launchpad's Patches inspector no longer shows "Unavailable" for a large
  patch set, such as the `frida` preset.** A big preset's `fw patches --json`
  output is long enough that an internal line-buffer limit was silently
  dropping the start of the document before Launchpad could parse it, even
  though the command itself had already succeeded — so the inspector had no way
  to tell the difference from a real failure. The **Update Kernel** and
  **Apply to Guest** buttons now appear and work for `frida` and any other large
  preset, with no restore needed for the kernel patches. The same fix covers
  `vm leases` and `vm template list`, which can grow the same way.
- **Switching an existing machine's preset now actually works from Launchpad.**
  The Patches inspector's **Edit…** used to only show the current choice;
  picking a different preset (`standard` → `frida`, say) had to go through the
  CLI by hand. It now saves the change and, if the machine is stopped, chains
  **Update Kernel** and **Apply to Guest** right after, so switching preset is
  one step instead of three.
- **New Machine shows which Core Bundle its firmware list is reading from.**
  With more than one Core Bundle installed, the Device/iOS pickers read from
  whichever one is chosen in **Advanced Options → Firmware** — easy to miss, and
  the usual reason a newer iOS release doesn't show up. The basic page now
  names that Core Bundle directly, with a one-click way to change it.

## Firmware, CFW & Build

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
- **`scripts/check-firmware-catalog.zsh`** flags any device already in the
  firmware catalog that Apple has since signed a newer build for, by checking
  against [ipsw.me](https://ipsw.me). It only reports; adding the pairing is
  still a manual edit.
- **Building VPhoneLaunchpad through the full workspace no longer fails on a
  package-pin mismatch.** A dependency had been bumped for Launchpad alone
  without updating the workspace's own pin, so a clean build through
  `VPhone.xcworkspace` always failed a licence-staging check. Every pin now
  agrees.
