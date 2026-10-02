/// Screenshot chords are App-independent. Rewrite within the original native
/// input route before WindowServer handles shortcuts; never open a source App or
/// write its clipboard. A receiving Bridge sees a native chord, not Win+Shift+S.
public struct NativeScreenshotMapping: Sendable {
    public struct Output: Equatable, Sendable {
        public var key: UInt16
        public var modifiers: Modifiers
        public var suppress = false
    }
    private var s: (key: UInt16, pid: Int32)?
    private var printScreen: (key: UInt16, pid: Int32)?
    public var hasHeldKeys: Bool { s != nil || printScreen != nil }
    public init() {}
    public mutating func reset() -> [UInt16] {
        let keys = [s, printScreen].compactMap { $0?.key }; s = nil; printScreen = nil
        return keys
    }
    public mutating func handle(key: UInt16, down: Bool, repeating: Bool, modifiers: Modifiers,
                               windowsKey: WindowsKeyModifier, printScreen behavior: PrintScreenBehavior,
                               allowed: Bool, sourcePID: Int32 = 0) -> Output? {
        guard key == 1 || key == 105 else { return nil }
        let held = key == 1 ? s : printScreen
        if !down {
            guard let held, held.pid == sourcePID else { return nil }
            if key == 1 { s = nil } else { printScreen = nil }
            return Output(key: held.key, modifiers: modifiers)
        }
        if let held {
            guard held.pid == sourcePID else { return nil }
            return Output(key: held.key, modifiers: modifiers, suppress: true)
        }
        guard allowed, !repeating,
              let kind = WindowsScreenshotShortcuts.match(key: key, modifiers: modifiers,
                  windowsKey: windowsKey, printScreen: behavior) else { return nil }
        let output: Output
        switch kind {
        // Saving first lets the lifecycle-checked observer copy the image.
        // A native clipboard chord would finish writing even after Pause.
        case .region: output = .init(key: 21, modifiers: [.command, .shift])
        case .fullScreen: output = .init(key: 20, modifiers: [.command, .shift])
        case .fullScreenSave: output = .init(key: 20, modifiers: [.command, .shift])
        case .activeWindow: return nil // Destination-specific window capture stays in its verified route.
        }
        if key == 1 { s = (output.key, sourcePID) } else { printScreen = (output.key, sourcePID) }
        return output
    }
}
