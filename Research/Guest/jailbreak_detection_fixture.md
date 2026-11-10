# App-context jailbreak observations

## Fixture and scope

`VPhoneLaunchpad/Tests/PentestFixtures/JailbreakProbe.swift` adds **Run jailbreak
checks** to the synthetic QA app, `com.vphone.fixture.pentest`, version 1.0,
build 2. Build with `zsh VPhoneLaunchpad/Tests/BuildPentestFixture.sh`; the IPA
is `.build/pentest-qa-fixture/PentestFixture.ipa`. It is ad hoc signed for vphone
testing, not provisioned for physical devices. It is not a new shipped tool.

The app presents JSON and saves `Documents/jailbreak-result.json`. No report
is uploaded. It records only fixed probe paths, matching image basenames,
capability/boolean observations, its own app identity and timestamp. Environment
variable values, serial numbers, UDIDs, tokens and customer data are excluded.
An exact temporary canary path is retained only if its cleanup fails.

Checks are deliberately bounded:

- `lstat` of selected jailbreak/package-manager/tool paths; failed lookups may
  be sandbox-hidden and are never proof of absence.
- Declared `canOpenURL` queries for cydia/sileo/zbra/filza, without opening URLs.
- Exclusive creation of an empty UUID-named canary in `/private` and
  `/private/var/tmp`; only a successfully created own file is unlinked.
- Loaded-image basename matches for Frida/Gadget/Substrate/Substitute/libhooker/
  ElleKit; debugger flag and DYLD environment presence reported separately.
- Two fixed research-agent paths and `DCAppAttestService.isSupported`, separately
  from the jailbreak summary. No App Attest key or attestation is requested.

There is no fork test, shell execution, exploit, additional privilege grant,
firmware patch or other app data access.

## Observed VM results — 2026-11-10

Two explicit app-UI runs on the dedicated test VM (anonymized label
`pentest-test-vm`), iOS 27.0.1 (24A446), produced the same observation fields.
The first report was at 04:22:00Z. The IPA was **not patched with Gadget** and
no debugger was attached. Launchpad's `apps.install` re-signed/registered it;
this is not an installd validation or an App Store distribution test.

| Check | Result |
| --- | --- |
| Selected jailbreak paths | 0 of 11 observed; all returned ENOENT |
| Cydia/Sileo/Zebra/Filza URL handlers | All false |
| Canary in `/private` | Denied with EROFS (30), not a sandbox-specific error |
| Canary in `/private/var/tmp` | Created outside the app container; successfully removed on both runs |
| Instrumentation image-name matches | None |
| Debugger flag | Query succeeded; traced false |
| DYLD environment | `DYLD_INSERT_LIBRARIES` present, `DYLD_LIBRARY_PATH` absent; no values collected |
| Research-agent paths | `/usr/bin/vphoned` observed |
| App Attest capability | false; attestation itself not attempted |
| Simulator compilation | false; not evidence of physical hardware |
| UID / effective UID | 501 / 501 |

The installed app's entitlements were its exact application identifier and
Keychain group, container-required identifier and the guest's
`jb.pmap_cs_custom_trust` value. The fixture requested no sandbox exemption or
get-task-allow entitlement. Guest installation policy/re-signing still affects
the app context, so these observations are specific to this VM environment.

The displayed summary was **Jailbreak-like indicators observed**, triggered by
the outside-container canary. This demonstrates a concrete heuristic an app
could flag even when package-manager paths are not observed. It does not prove
how any particular customer's app would classify this environment. A stock
iPhone and a physical jailbroken iPhone were not tested; false-positive and
false-negative rates are unknown. Attestation, virtualization and instrumentation
must not be collapsed into a single jailbreak boolean.

Both canaries were removed. The QA app/report were retained for user review;
the test VM was stopped after testing. No customer app/VM was opened or modified.
Live reports and install metadata remain private under `.build/` and are not
committed. The VM label in this note is a placeholder, not a machine selector.

## References

- [OWASP jailbreak detection techniques](https://mas.owasp.org/MASTG/knowledge/ios/MASVS-RESILIENCE/MASTG-KNOW-0084/)
- [Apple App Attest capability](https://developer.apple.com/documentation/devicecheck/dcappattestservice/issupported)
