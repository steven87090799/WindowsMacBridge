# Final production review — 2026-10-03

| Item | Value |
|---|---|
| Repository | https://github.com/steven87090799/WindowsMacBridge |
| Base | `main` @ `caa128e4c088ae122e6b711fbfe691bc64ad9a46` (PR #12), 0.6.0 build 45 |
| Branch | `fix/final-production-hardening-20261003` |
| Result | 0.6.0 build 46; final SHA = PR head (this file is part of the last commit) |
| Toolchain | Swift 6.4 (swift-tools-version 6.0), macOS 27.0.1 arm64, Command Line Tools (no Xcode) |
| Deployment | macOS 14+, arm64 only |

Historical `Docs/*-2026-*.md` files are evidence of earlier states, not proof of current behaviour. Every claim below was re-checked against this branch's code; anything that needs hardware, TCC approval, a second Mac, a Windows host or the DriverKit driver is marked **NOT VERIFIED ON REAL HARDWARE**.

## 1. Architecture (rebuilt from code)

### Modules

```text
BridgeWorkGate (C11 atomic_bool)          InputSourceCore (pure state machines)
        │                                          │
BridgeCore ─ rules, KeyboardEventProcessor, RemoteSourceRouter, RuntimePolicy,
        │    HIDTranslationEngine, HIDDescriptorPolicy, Finder/Screenshot policy
        ├── HIDProtocol (XPC protocol + bounded Codable config/status)
        ├── BridgePlatform ─ InputEngine (EventTap thread), HIDBackendClient/Slot,
        │                    RemoteSourceRegistry, ScreenshotManager, ShortcutActionDispatcher,
        │                    MacBookKeyboardMapper, SettingsStore, KeyboardEventTapCoverage
        ├── InputSourceSupport ─ GuardController, InputSourceCoordinator, HotkeyManager (Swift 5 mode)
        └── HIDRuntime (+ HIDLifecycle, VirtualHID C++ over pqrs SDK) ─ InputService, DeviceCapture
WindowsMacBridge (executable) ─ AppDelegate, BridgeController, SettingsView, installers
Extensions/FinderSync ─ inert (directoryURLs = []), packaged only
```

### Processes and privilege

| Process | User | Started by | Talks to | Privilege boundary |
|---|---|---|---|---|
| `WindowsMacBridge.app` GUI | console user | user / opt-in login item | WindowServer (EventTap, post), TIS, AX (Finder), `screencapture`, XPC client | TCC: Accessibility+Posting, Input Monitoring, Screen Recording (explicit) |
| `…/Application Support/WindowsMacBridge/WindowsMacBridge.app --hid-service` | root | launchd system job on demand (Advanced+HID only) | IOHID (seize), VirtualHID daemon socket, XPC server | authenticates the GUI: console UID + CDHash pin + identifier, per-message code requirement |
| Karabiner VirtualHIDDevice daemon/dext | root / DriverKit | shared official package | VirtualHID clients | not owned by this App; never re-signed, downgraded or deleted when foreign |
| Installer bootstrap → `InstallBackend.sh` | root | explicit "安裝進階背景元件" + admin prompt | filesystem, launchd, pkgutil, codesign | runs only a sealed copy of a verified App in a root 0700 stage (this PR) |
| `screencapture`, `systemextensionsctl`, Manager `activate` | user | explicit actions | — | bounded child processes with timeouts |

### Threads / run loops / actors

| Context | Owner of | Notes |
|---|---|---|
| MainActor (main run loop) | BridgeController, SettingsStore, RemoteSourceRegistry, HIDBackendClient/Slot, ScreenshotManager (incl. its two session taps), MacBookKeyboardMapper, GuardController | screenshot taps run here (open item WMB-36) |
| `WindowsMacBridge.Input` thread (own CFRunLoop) | InputEngine tap, KeyboardEventProcessor, RemoteSourceRouter, NativeAppSwitchLatch, release queue | reads config via `NSLock.try()` mailbox; never waits for main |
| Detached tasks / utility queues | remote identity resolution, image preparation, AX Finder focus, driver status, log drain | results re-validated (epoch/token/birth) on MainActor |
| Root main run loop | InputService, DeviceCapture IOHID callbacks, held-safety one-shot | VirtualHID teardown on a dedicated serial queue |
| pqrs dispatcher thread (root) | VirtualHID client callbacks | only atomics + status callback under lock |

### Input ownership matrix

| Event source | Normal mode owner | Advanced HID owner | Never |
|---|---|---|---|
| Local physical keyboards | EventTap (`physicalFallback`, pid 0/state 1) | DeviceCapture → VirtualHID; tap treats pid-0 output as `virtualPassThrough` unless destination semantics | both at once: a pending/unconfirmed HID release now gates **both** backends |
| Remote producers (CRD host etc.) | RemoteSourceRouter per-producer stream (≤16) | same (session tap) | translation by foreground App alone |
| Universal Control | destination semantics only | same | inferred peer OS |
| Screenshot chords | ScreenshotManager head tap (+ InputEngine rule as fallback, single-flight capture) | VirtualHID native tap only | duplicate capture (single-flight slot) |
| Finder actions | ShortcutActionDispatcher (AX focus evidence) | disabled in capture config | destructive action on unknown focus |
| Fn/Ctrl swap | MacBook UserKeyMapping (built-in only) | HID engine | both (native mapping is restored before HID) |

### Generation / epoch inventory

| Field | Owner | Advances on | Invalidates |
|---|---|---|---|
| `RuntimePolicySnapshot.generation` | RuntimePolicyCoordinator | any policy input change | engine config, action epoch, screenshot jobs, source work policy |
| `modifierEpoch` | RuntimePolicyCoordinator | lifecycle/security gaps (not App continuity) | modifier continuity across coalesced transitions |
| `settingsRevision` | BridgeController | physical-policy settings change | policy snapshot |
| `sessionEpoch` | BridgeController | sleep/screens/session transitions | policy snapshot |
| `restartToken` | BridgeController | explicit restart, backend/advanced change | engine fault/pass-through, HID failClosed, unconfirmed HID release (this PR) |
| `actionEpoch` (engine, HID client) | InputEngine / HIDBackendClient | generation, permission, tap re-enable | queued Finder/system actions |
| `SourceWorkGate` (C atomic) | RemoteProducer.work / stream frame | producer exit (kqueue, this PR), preference change, policy change | async remote work, held remote output |
| `RemoteSourceRegistry.epoch` | registry | active toggle | stale resolution jobs |
| `ScreenshotCaptureLifecycle.revision` | ScreenshotManager | enable/epoch/timeout | clipboard write of an old job |
| `GuardController.workEpoch` | GuardController | cancelled work | TIS retries/verification |
| `HIDBackendClient.stopID`, `connectionIdentity` | client | each stop/connection | late XPC replies |

No two generations were merged: each guards a different domain. `SourceWorkGate` lifetime is ARC-owned (every reader holds a strong reference), so `WMBWorkGateIsCurrent` can never run after `WMBWorkGateDestroy`; release/acquire ordering is sufficient for a single boolean.

## 2. Findings

Severity follows the brief: P0 keyboard unusable / root execution / stuck state; P1 lifecycle race, permission false-state, backend handoff, root crash; P2 defensive or efficiency gap; P3 cleanup/docs.

### Fixed

| ID | Sev | Component | File | Problem | Root cause | Impact | Fix | Regression / verification |
|---|---|---|---|---|---|---|---|---|
| WMB-01 | P0 | HID pointing | `DeviceCapture.swift` `flushPointing` | Composite keyboard+pointer goes dead 1 s after any configure; button-up can be dropped | Heartbeat replaced by XPC lease, but pointing still required `uptime - lastHeartbeat < 1` (only set in `configure`) | Seized trackpad/mouse unusable, stuck button (Advanced mode) | Gate on capture phase/policy; drop only motion under backlog | Code review; **NOT VERIFIED ON REAL HARDWARE** |
| WMB-02 | P0 | HID emergency pause | `DeviceCapture.received`, `HIDTranslationEngine` | Ctrl+Opt+Cmd+P leaves every keyboard seized and silent | Pause set inside the callback; no `tick()` → no release/publish | Panic chord disables keyboard until an unrelated configure | Toggle schedules a tick → release + status; all fault paths publish | Code review; hardware NOT VERIFIED |
| WMB-03 | P0 | Root installer | `LaunchEmbeddedInstall.sh`, `LaunchEmbeddedUninstall.sh` | Root ran `InstallBackend.sh` in place from user-owned `$TMPDIR`; payload bound only by a user-built manifest | Trust boundary placed after a same-UID-writable staging step | Same-user code could alter the script mid-run (bash reads incrementally) or the plists/runner → root | Fixed bootstrap: root copies App to 0700 stage, `codesign --verify --strict -R '=identifier …'`, builds payload from sealed `BackendPayload`, runs sealed copy | `test_root_bootstrap.py` (4); real `osascript` + real `codesign` run on the packaged bundle (sealed script reached, refused at EUID, stage removed) |
| WMB-04 | P1 | MacBook Fn/Ctrl | `NativeMacBookKeyboardBackend.services` | Swap never applied on this MacBook | Total service count (129 on macOS 27) checked against the keyboard bound 128 | Feature unusable on current Apple Silicon portables | Separate scan (4096) and keyboard (128) bounds | Existing native test failed on main here; passes now |
| WMB-05 | P1 | EventTap / Secure Input | `RuntimePolicy`, `InputEngine`, `BridgeController.publish` | After a publish observed Secure Input, translation stayed off in the same App until an App switch | `permitsInput` disabled the engine → tap destroyed; its next event was the only end-of-Secure-Input signal | Ctrl shortcuts silently stop after login forms | Keep the tap when Secure Input is the only blocker (`awaitsSecureInputEnd`) | `secureInputKeepsTheTapSoItsEndIsObservedWithoutAnAppSwitch` |
| WMB-06 | P1 | Backend handoff | `BridgeController.synchronizeHIDMode`, `RuntimePolicy`, `HIDBackendClient` | HID→EventTap started the tap while the root service could still own the keyboard; a timed-out stop was treated as release | Client dropped immediately (stop + deadline destroyed); gate applied only to HID backend | Double translation window; violated HIDIntegration.md contract | `HIDBackendSlot` keeps retiring clients; gate both backends; timeout latches `releaseUnconfirmed` until "恢復／重啟引擎" | 2 real-XPC slot tests + updated policy tests |
| WMB-07 | P1 | VirtualHID (root) | `VirtualHID.cpp` | Null dereference during teardown | libc++ nulls `unique_ptr` before `~client()`; `connected` callback reloads `state->client` | Root helper crash on daemon reconnect during stop | Capture raw client; declare `client` last (destroyed first) | Code review; hardware NOT VERIFIED |
| WMB-08 | P1 | Root session gate | `DeviceCapture.sessionActive` | Session check could never pass in a LaunchDaemon; checked by IPC per HID value; Secure Input latched a permanent fault | `CGSessionCopyCurrentDictionary` returns NULL outside a Quartz GUI session (documented); fault used for transient state | Advanced capture possibly never starts; restart needed after any password field | App-reported session + console UID (configd-notified); transient release for Secure Input/session | Behaviour change is doc-based; **UNCONFIRMED on hardware** |
| WMB-09 | P1 | HID pointing readiness | `DeviceCapture.tick` | Composite device stayed seized after virtual pointing became unready | Readiness checked only at seize | Pointer dead while seized | Release and recapture only ready devices | Code review |
| WMB-10 | P1 | Root XPC auth | `InputService` | Client authenticated once by PID | PID-reuse / exec-after-connect race | Spoofed controller could configure capture | `setCodeSigningRequirement(identifier + pinned cdhash)` per message; pin read via one `O_NOFOLLOW` fd | `ControllerRequirementTests` (real anonymous XPC: matching accepted, mismatched rejected) |
| WMB-11 | P1 | Rollback | `InstallBackend.sh` | Finder tag on installed App made rollback and every later recovery fail | `ditto`/`mv` kept `com.apple.FinderInfo`; `--strict` rejects it | Wedged recovery, uninstall refused | Attribute-free snapshot verified before switching; restore from it | `test_finder_tagged_retired_app_rolls_back_from_the_verified_snapshot`, `test_unverifiable_installed_app_is_never_switched` |
| WMB-12 | P1 | Finder permanent delete | `ShortcutActionDispatcher` | Confirmed Shift+Delete never executed; modal blocked other actions | Clicking the alert activated this accessory App, failing the Finder-frontmost check | Feature broken; queued actions expired | Delegate to Finder's Delete Immediately (always confirms) | Code review; manual check listed |
| WMB-13 | P2 | Tap coverage | `KeyboardEventTapCoverage` | Fixed 128-entry tap list | API reports filled count | Readiness false negative on busy systems | Size from live total, reject full buffer | `registryQueryIsSizedFromTheLiveTotalAndRejectsTruncation` (+ live probe) |
| WMB-14 | P2 | CPU / wakeups | `InputEngine`, `BridgeController` | Every keystroke woke the MainActor for a full tick + publish | Counters part of the change test | 4 TCC reads, policy, `proc_pidinfo` loop, SwiftUI invalidation per key | Counter-only changes silent; diagnostics/neutral-wait keep edges; calibration explicit | `EngineWakePolicyTests` (3) |
| WMB-15 | P2 | Remote lifecycle | `RemoteSourceRegistry` | Producer death noticed late (daemons never) | Polling on unrelated ticks | Stale gate, delayed release of held remote keys | kqueue exit sources, birth re-check after arming | Live probe of dispatch semantics; existing remote suites |
| WMB-16 | P2 | HID pointing | `DeviceCapture`, `VirtualHID` | Backlog of pointer reports latched a fault | Outstanding>256 treated as output failure | Manual restart after a stall | Drop motion above 64 outstanding; buttons always post | Code review |
| WMB-17 | P2 | HID capture | `CaptureLifecycle`, `DeviceCapture` | Key pressed between observe and seize → permanent fault | Neutral race mapped to `faulted` | Manual restart | `captureAborted` + ≤3 bounded retries | `keyPressedDuringSeizeAbortsWithoutRequiringRestart` |
| WMB-18 | P2 | Root XPC | `InputService` | A displaced owner's queued configure could retake the lease | No displaced tracking | Legitimate owner invalidated | Displaced set (bounded) | Code review |
| WMB-19 | P2 | Root lifecycle | `InputService` | Helper stayed resident after a rejected lookup; idle-exit could fire under a new owner | Idle exit armed only on accepted invalidation | Resident root process; spurious disconnect | Arm at start/rejection; re-check idleness after teardown; `_exit` on SIGTERM | Code review |
| WMB-20 | P2 | Root status | `DeviceCapture` fault paths | Released devices but never published status or retired the client | No tick after fault | Stale UI state | `failClose()` schedules a tick | Code review |
| WMB-21 | P2 | Shared Driver | `DriverTransaction.sh` | Recovery could downgrade/delete a Driver Karabiner started using after an interrupted install | Version treated as ownership | Breaks a foreign product | Refuse and keep recovery pending; path overridable for tests | `test_recovery_leaves_the_shared_driver_alone_once_karabiner_also_uses_it` |
| WMB-22 | P2 | Install publish | `InstallBackend.sh` | `mv` into `/Applications` could move the bundle into a directory/symlink | Check far from use | Misplaced App | Re-check + `mv -h` at publish | Installer suite |
| WMB-23 | P2 | Recovery UX | `InstallBackend.sh`, `UninstallBackend.sh`, `BridgeController.summary` | Silent `return 1`s; "reopen the App" never resumes recovery | Missing messages | User stuck | Reasons printed; text points to the install action | Installer suite |
| WMB-24 | P2 | Finder move | `ShortcutActionDispatcher`, `FinderActionPolicy` | Ctrl+V moved files when AX focus read failed | `focus != .text` treated unknown as file view | Surprise file move from a text context | `.folder` positive evidence; unknown pastes | `armedCutMovesOnlyOnPositiveFileViewEvidence` |
| WMB-25 | P2 | Screenshot privacy | `ScreenshotManager` | Quit/crash left captured PNG in `$TMPDIR` | Cleanup only in completion | Screen contents on disk | Remove on stop; sweep own leftovers at launch (production only) | Runtime suites |
| WMB-26 | P2 | Screenshot driver | `ScreenshotCaptureDriver` | Final stderr read blocked until EOF | Inherited write end | Capture slot held until relaunch | Non-blocking final read | `inheritedDiagnosticPipeCannotStallCompletionAndTheCaptureSlot` |
| WMB-27 | P2 | Input source idle cost | `GuardController` | Guard off: full TIS enumeration + 3 log lines per protected-App/Secure Input round trip | Unconditional rediscover/log | Main-thread work, log churn | Rediscover only when changes were missed; log only when enabled | Input source suites |
| WMB-28 | P2 | Input source gate | `GuardController.scheduleVerification` | `selectionInProgress` could stay set | Early return without resolving pending | Windows translation off (`layoutSupported=false`) | Resolve pending on every exit path | Code review |
| WMB-29 | P2 | Single instance | `SingleInstanceGuard` | Lock in purgeable `$TMPDIR`, inheritable, follows symlinks | Location/flags | Possible second instance after weeks | App Support lock, `O_CLOEXEC|O_NOFOLLOW`, still honours legacy lock | Code review |
| WMB-30 | P2 | Pin read | `InputService.init` | Attributes checked by path, content read by path | TOCTOU | Root-only exploitability | One descriptor: `O_NOFOLLOW`, `fstat`, nlink 1 | Code review |
| WMB-31 | P2 | Test isolation | `test_install_backend.py`, `DriverTransaction.sh` | 5 installer tests failed on any Mac with Karabiner-Elements | Hard-coded real path | False red locally | Path variable substituted in fixture | 45/45 installer tests pass on this Mac |
| WMB-39–50 | P3 | various | see commits | ring for observed producers; non-ICU discovery match; deprecated `String(cString:)`; duplicate cookie / usage traps in root; hotkey Carbon handler removed when disabled; unused `ensureLoginEnabled` removed; Esc no longer discards a successful capture; screenshot logs without paths; unmapped PNG read; GuardController `stop()` state; README/UserGuide build 44↔45, HIDIntegration "250 ms heartbeat", DualModeReview↔HIDIntegration conflict | — | — | fixed | suites + review |

### Open (not safely fixable here)

| ID | Sev | Problem | Why not fixed now | Gate |
|---|---|---|---|---|
| WMB-32 | P2 | `HIDDescriptorPolicy` may reject standard keyboard array sub-elements (usage 0–3 / 0xE8–0xFF), refusing capture | Element enumeration needs Input Monitoring for the probe; changing seize policy blind risks seizing unforwardable input | **UNCONFIRMED**; enumerate a USB/BT/built-in keyboard with TCC |
| WMB-33 | P2 | One never-neutral device blocks capture of all devices | Per-device gating is a lifecycle redesign | hardware |
| WMB-34 | P2 | VirtualHID `warning_reported` can leave a sticky FAULT without reconnect | Needs the driver to observe; blind recreate loop risks CPU spin in root | driver |
| WMB-35 | P2 | Finder text keys (Backspace/Return) can reorder or drop while renaming | Requires a cached AX focus observer | Finder AX + hardware |
| WMB-36 | P2 | Screenshot taps run on the main run loop (latency coupling) | Moving taps off MainActor is a subsystem refactor; WMB-14 removed the per-key main-thread work that amplified it | latency measurement |
| WMB-37 | P2 | Virtual-device exclusion relies on names/vendor | `IOHIDUserDevice` exclusion would also exclude Bluetooth LE keyboards | hardware |
| WMB-38 | P2 | Ad-hoc signing: no publisher authenticity; shared Driver has no ownership marker | Needs Developer ID / installer design | release process |
| — | P3 | Inert FinderSync extension still packaged; vendor 0x16c0 excludes all V-USB keyboards; installer logs and `PreviousApplication.*` not pruned | Low risk, packaging churn | — |

## 3. Karabiner comparison (device_grabber principles)

| Area | Karabiner principle | WindowsMacBridge | Difference / risk | Action |
|---|---|---|---|---|
| Ownership | grab only when virtual device ready | `.openPhysicalDevices` only after `KEYBOARD_READY` (+ `POINTING_READY` for composites) | readiness loss after seize was ignored for pointing | WMB-09 fixed |
| Modifier ownership | per-device contributors | per-slot `physical/consumed/ownerSlots`; disconnect clears only its slot | equivalent | none |
| Session | console user via session monitor agent | was `CGSessionCopyCurrentDictionary` in daemon | daemon has no GUI session | WMB-08 fixed |
| Disconnect cleanup | release held output per device | per-device ledger + full-state diff | equivalent | none |
| Event queue | bounded queue | 256 outstanding, 500 ms stall → fault | pointer bursts faulted | WMB-16 fixed |
| Output reset | reset virtual device on ungrab | reset then close, close never depends on reset | teardown race | WMB-07 fixed |
| Loop guard | ignore own virtual device | vendor/name based exclusion | weaker than registry parent check | WMB-37 open |

## 4. CPU and wakeups

| Source | Trigger | Interval | Normal | Advanced | Idle cost | Status |
|---|---|---|---|---|---|---|
| BridgeController runtime timer | pause/debug/**calibration** deadline | one-shot | yes | yes | none when idle | calibration expiry now timed (was only checked on keystrokes) |
| InputEngine host wake | material status change | event | yes | yes | none | **per-keystroke host tick removed** (WMB-14) |
| InputEngine remote expiry | held remote output | one-shot 60 s | only while held | same | none | unchanged |
| RemoteSourceRegistry | producer exit (kqueue), app launch | event | when routing active | same | none | exit now event-driven (WMB-15) |
| HIDBackendClient | request/stop/permission deadlines | one-shot 1.5/1.5/3 s | — | yes | none | unchanged |
| DeviceCapture held-safety | held output while seized | one-shot 1 s | — | yes | none when neutral | unchanged |
| InputService idle exit | no clients | one-shot 2 s | — | yes | none | now also armed at start (WMB-19) |
| GuardController | retries/verification/Secure Input backoff | one-shot, bounded | only after explicit selection or guard on | same | none | guard-off enumeration removed (WMB-27) |
| ScreenshotManager | capture job | one-shot 120 s | only during capture | same | none | unchanged |

No repeating `Timer`, `DispatchSourceTimer`, `Task.sleep` loop or polling remains in any process. Normal mode does not instantiate `HIDBackendClient`, open XPC, probe the Driver or read `IOHIDCheckAccess`; `BundledBackendInstaller` identity checks are lazy and gated on `usesHID`.

Runtime measurement (`scripts/monitor-runtime.py`) was **NOT RUN** for this build: it needs the build installed in `/Applications` with TCC re-approved for the new ad-hoc identity, which this review does not do. No CPU/RSS numbers are claimed.

## 5. Memory and bounds

Bounded: EventTap diagnostics ring 128; release queue 17×128+17; remote streams 16 / registry 32 / pending 16 / inbox 16 / observed ring 32 / exit sources ≤ entries; action inbox; HID devices 16, elements ≤2048, presses 256, outstanding 256; XPC accepted connections 4, displaced ≤ accepted; retiring HID clients ≤4 (1 in practice); logs 128 lines / 64 KiB queued, 512 KiB×2 on disk; screenshots single-flight with decode budgets (overflow-checked); PDF recursion depth 12 / 256 nodes; installer journal ≤1024 bytes. No unbounded growth with uptime was found after WMB-15/39. No "zero leak" claim is made; ASan/TSan results are in §8.

`@unchecked Sendable` safety: mailboxes/inboxes/loggers are lock-protected; `InputEngine` state is input-thread-confined (mailbox crosses threads); `SourceWorkGate` is an atomic with ARC lifetime; `HIDConnectionLifetime` is mutated on MainActor and only invalidated in `deinit`; `NativeScreenshotJob` guards state with locks; `CaptureStatusRelay` only signals a mailbox; `ConnectionRetainer` is lock-protected.

## 6. Security summary

- Normal/Advanced split verified: no privileged component, XPC or Driver probe without explicit Advanced + HID.
- Root execution: only a sealed copy of a verified App in a root 0700 stage (WMB-03). Ad-hoc signatures prove consistency, not publisher; Developer ID + team requirement remains a release gate.
- Controller authentication: console UID + CDHash pin + identifier at accept, plus per-message audit-token requirement (WMB-10); pin read from one descriptor (WMB-30).
- Rollback: attribute-free verified snapshot before switching; recovery never mutates a shared Driver another product now uses; refusals are explicit.
- Symlinks rejected for payload, destinations, runtime root, recovery snapshot; `mv -h` at publish; hardlinked root-only files cannot enter the payload because it is built from the sealed App.

## 7. Remote transports

| Transport | Identification | Confidence | Automatic policy | Real hardware |
|---|---|---|---|---|
| Chrome Remote Desktop host | signing ID + team EQHXZ8M8AV, valid signature | known | raw Ctrl translated at a local destination; Command passes | NOT VERIFIED |
| Microsoft Remote Desktop / Windows App, Jump, AnyDesk, TeamViewer, Parsec, RustDesk, NoMachine, RealVNC | signing ID | likely | pass-through until manual semantics/calibration | NOT VERIFIED |
| Splashtop, other VNC | path match only | unknown | pass-through | NOT VERIFIED |
| Universal Control | `com.apple.universalcontrol` in `/System` | known (kind) | destination semantics only; peer OS never inferred | NOT VERIFIED |

## 8. Validation run on this branch

| Gate | Result |
|---|---|
| `bash scripts/test.sh` (debug) | pass — BridgeCore 149, BridgePlatform 142 (+10), InputSourceCore 34, InputSourceSupport 2, VirtualHID 23 (+3) |
| `bash scripts/test.sh -c release` | pass (same counts) |
| `python3 -m unittest discover -s Tests/InstallerTests` | 45/45 pass (was 38 with 5 environment failures on this Mac) |
| `python3 -m unittest discover -s Tests/MonitoringTests` | 5/5 pass |
| `bash scripts/build-app.sh` | pass; `--self-check` reports 0.6.0 (46) |
| `package-single-app.sh`, `package-app-dmg.sh` | pass; `codesign --verify --deep --strict` pass |
| Real bootstrap on packaged App (no admin) | sealed `InstallBackend.sh` reached, refused at EUID 77, stage removed |
| `git diff --check`, `bash -n` all scripts, `plutil -lint`, workflow YAML | pass |
| ThreadSanitizer (`--sanitize=thread`) | pass, no reports |
| AddressSanitizer (`--sanitize=address`) | pass, no reports |
| `git archive` build without `.git` | see PR description |
| Baseline on `caa128e` (this Mac) | **failed**: `nativeServiceNotificationRegistrationRetainsBridgedKeys` (WMB-04) |

## 9. Manual gates remaining (NOT VERIFIED ON REAL HARDWARE)

1. EventTap: Ctrl chords in TextEdit/Safari; focus a Safari password field, leave it **without switching Apps**, Ctrl+C/V must work again (WMB-05).
2. MacBook built-in keyboard Fn↔left Ctrl on this 129-service MacBook; external and UC keyboards unaffected; crash recovery.
3. Advanced HID with the official Driver: capture, emergency chord releases keyboards and pauses (WMB-02), HID→EventTap switch with no double translation, helper kill/stall shows "Helper 未確認釋放鍵盤" until restart (WMB-06), composite keyboard+trackpad pointer and drag (WMB-01/09), Secure Input/session release and recapture (WMB-08), Driver restart during stop (WMB-07), descriptor acceptance of USB/BT/built-in keyboards (WMB-32).
4. Installer as administrator: fresh install, upgrade, interrupted install recovery, Finder-tagged App rollback, Karabiner coexistence, uninstall.
5. Finder: Shift+Delete shows Finder's confirmation and deletes on confirm (WMB-12); Ctrl+X → empty folder → Ctrl+V moves; Ctrl+V in search/rename fields pastes text.
6. Screenshots: all four Windows shortcuts and ⌘⇧3/4, cancel, quit during capture leaves no temp file.
7. Two-Mac Universal Control and each remote transport above.
8. Idle CPU/RSS/footprint with `scripts/monitor-runtime.py` after TCC approval of build 46.
