> 以下為 0.2 初始設計背景。0.3 的規則、Finder 輸出及 HID 後端界線以 [KarabinerReplacement.md](KarabinerReplacement.md) 為準；目前已有指定 PID 的 Finder down/up 輸出，不再是完全零注入。

# Keyboard implementation boundaries (0.2.0)

The unified input-source architecture, lifecycle policy and migration are documented in [ProjectIntegration.md](ProjectIntegration.md).

```text
WindowsMacBridge (MainActor)
  AppDelegate / NSStatusItem / SwiftUI
  BridgeController / NSWorkspace notifications / SettingsStore
                     |
              EngineConfiguration mailbox
                     v
BridgePlatform.InputEngine (dedicated Thread + CFRunLoop)
  CGEventTap -> marker guard -> normalization
                     |
                     v
BridgeCore.KeyboardEventProcessor
  physical modifiers -> press ledger -> protected profile -> exact rule table
                     |
       pass / suppress / rewrite / emergency pause
                     v
  CGEvent flags/keycode modification, return to current tap
                     |
              bounded diagnostics mailbox
                     v
                Menu Bar / Settings
```

Core has no CGEvent/AppKit/UI dependency. BridgePlatform owns keyboard side effects; InputSourceSupport owns TIS/Carbon/login side effects; the executable is the composition root. There are no synthetic modifier downs, no clipboard accesses and no event posting in this milestone. A process-random marker protects rewritten events if another component sends them back into the tap.

## Concurrency contract

- InputEngine is the single audited `@unchecked Sendable` platform object; its callback/run-loop fields are input-thread-only. EngineMailbox is lock-protected.
- UI publishes immutable configuration. Callback reads with `NSLock.try()` and never waits for the main thread; a missed try uses the last snapshot. The timer retries.
- Core state, rules and the 128-entry press table are owned by the input thread. No per-event Task, AX query, bundle lookup, UserDefaults, disk or network operation.
- Permission/Secure Input and optional neutral-state probes happen in the run-loop timer, outside the callback. This periodic sampling is not an instantaneous security-field detector; the app never collects text regardless.
- Diagnostic ring is fixed at 128 entries and 5 minutes. Only built-in matched rule IDs, app bundle ID and elapsed time are retained. Timer publishes copies; ordinary input has no diagnostic record.
- App activation is notification-driven, not queried per key. This does not eliminate the OS activation/notification race; remote compatibility is a manual release gate.

## Pairing contract

- Each first down creates one ledger entry. Repeats reuse it, up removes it.
- Rule selection is exact; Ctrl+Shift/Option/Command are not generic Ctrl matches.
- Native passed keys remain passed across transitions. Translated presses become suppressed tombstones on focus/profile changes and cannot revive when returning to the original app.
- Pause stops translated repeats but preserves same-context release pairing. Recovery invalidates translated entries, never blindly injects global key-ups.
- A known hardware-neutral probe may clear tombstones after a gap. Caps Lock is excluded from held-key polling and retained in output flags.
- Missing modifier evidence disables new translations. Only neutral recovery resets synchronization.
- All Fn/Globe/IME and layout-specific behavior beyond the explicit US/ABC support remains native.

## Deliberately absent

Alt+Tab needs a separate synthetic-output ownership state machine, mouse interaction and real UI validation. Finder cut needs async metadata coordination and an explicit move confirmation policy. Neither is represented by a fake success flag or placeholder UI toggle.

## Build and distribution

Swift Package executable, macOS 14 minimum, Swift 6 concurrency checking for the host and cores; the imported TIS adapter retains Swift 5 language mode behind its main-actor coordinator. Build scripts use a per-workspace local cache and bundle resources inside Contents/Resources. Ad-hoc signature is for development only. No driver, privileged helper, sandbox entitlement workaround or mandatory login agent (SMAppService login is opt-in).
