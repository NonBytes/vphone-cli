# Launchpad Developer Tools grant mismatch

## Observed behavior

On macOS 27.2, a locally signed Launchpad 2.15.2 showed Developer Tools enabled
in System Settings while Host Setup reported access unavailable after relaunch.
The installed app's control API also returned `developerTools: false` and
`hostReady: false`; this was not just the appearance of the Settings toggle.
The privileged helper was ready at version 21.

The running executable was in `/Applications/vphone-launchpad.app`. Its
signature was valid and used an Apple Development identity. A second copy in
the checkout's build output had the same bundle identifier. Earlier versions
installed on this workstation used the upstream distribution signature.

A stale grant associated with an earlier signing identity is a hypothesis,
not a confirmed diagnosis. Multiple app copies can also make it unclear which
copy was selected in Settings. These observations do not establish that either
condition caused the refusal. The VM's Core Bundle binding is separate from
Launchpad's own Developer Tools grant.

## How Launchpad checks

`VPhoneLaunchpadHostSetup.developerTools()` asks for an execution-policy
exception for its own running executable. A successful request passes the
check; a `notADeveloperTool` refusal fails it. For other errors it falls back
to the process's reported `EPDeveloperTool.authorizationStatus`.

The code accounts for the reported status remaining stale within a running
process after a Settings change. Repeatedly relaunching cannot repair a grant
that does not apply to the installed app. An enabled toggle alone does not
prove that the running process can add execution-policy exceptions.

## Re-register the installed copy

This is a proposed recovery procedure; its result on the affected workstation
has not yet been verified. The user must approve the grant in macOS Settings.

1. Quit Launchpad.
2. Open **System Settings → Privacy & Security → Developer Tools**.
3. Select the Launchpad entry and remove it with **−**.
4. Use **+** to select `/Applications/vphone-launchpad.app`, then enable it.
   Choose the installed app directly rather than a copy under `.build`.
5. Open that same app from Applications and choose **Host Setup → Check Again**.
6. Relaunch once more and verify that access still passes. From the command
   line, the following should report `developerTools: true`:

   ```sh
   /Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli status
   ```

`hostReady` also depends on the other Host Setup checks. If Developer Tools
still fails, record the installed app path, signing identity, reported status
and whether another copy shares the identifier before investigating further.
Avoid editing the TCC database or resetting unrelated privacy grants. No SIP,
AMFI, helper policy or guest firmware change is part of this procedure.

## Follow-up verification — 2026-11-05

Launchpad subsequently reported `developerTools: true` and `hostReady: true`
on fresh launches, including after quitting and reopening it during this
session. The helper remained ready at version 21. The final status after
starting doctor-ipad and completing the Logs/Crash UI tests also passed both
checks. No TCC reset, permission change, signing change or host-policy change
was performed during this verification.

The earlier refusal was not reproduced in this session. This confirms current
authorization across the tested launches, but does not establish what changed
before this session or prove the proposed re-registration procedure fixed it.
