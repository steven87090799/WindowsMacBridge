# WindowsMacBridge agent notes

For Apple Screen Sharing / VNC shortcut work, read [the incident and acceptance record](Docs/ScreenSharingVNC-2026-10-24.md) before changing routing, calibration, or the MacBook Fn/Ctrl switch.

- The **receiving** Mac runs the remote-source router. The MacBook switch changes only that MacBook's built-in Fn/left-Control mapping. Each Mac needs its own Bridge installation and permissions; preferences are not shared.
- Apple `com.apple.screensharing.agent` is an incoming source only when its signature and system executable path match. Automatic mode may translate its raw Control shortcuts, while already-Command shortcuts pass through. Never infer Windows semantics from an arbitrary synthetic PID or a VNC process name alone.
- The input run-loop must consume the latest mailbox revision on a coalesced wake. Do not restore a `try()`-and-return configuration read without arranging a guaranteed retry. Keep process lookup, signing checks, and scanning outside the keyboard callback.
- Unknown first input may pass through while asynchronous source identity resolves. Treat a successful MacBook-to-Mac test as one direction only; verify Mac-to-MacBook with a real connection before claiming it works on that hardware.
- Do not confuse shared clipboard transport with Ctrl/Cmd shortcut routing on the same receiving Mac. Keep tests free of clipboard contents and typed text; use key metadata and disposable TextEdit text.
- In the Mac mini → MacBook direction, test the Mac mini's external **Ctrl** key. In the MacBook → Mac direction, test the MacBook's built-in **Fn** key only when its Fn/left-Control switch is enabled. A virtual Karabiner keyboard being present does not prove it has seized the built-in keyboard; confirm with physical Fn input before changing Karabiner's per-device settings.
- Keep Screen Sharing, Universal Control, and local MacBook-keyboard acceptance separate. For 1.0.1's observed results and remaining reconnect checks, use `Resources/TwoMacAcceptance.md`; do not convert a stray character into a routing failure without confirming how it was typed.
