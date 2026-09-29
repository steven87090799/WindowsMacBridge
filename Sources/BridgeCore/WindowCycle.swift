/// Deterministic selection logic for an Alt-held window switch transaction.
/// The caller decides when Alt is released and only then commits the selection.
public struct WindowCycle: Sendable {
    public private(set) var selectedIndex: Int?
    public private(set) var count = 0
    public init() {}
    public mutating func advance(count candidateCount: Int, reverse: Bool) {
        guard candidateCount > 0 else { reset(); return }
        if count != candidateCount || selectedIndex == nil {
            count = candidateCount
            selectedIndex = candidateCount == 1 ? 0 : (reverse ? candidateCount - 1 : 1)
        } else if let selectedIndex {
            self.selectedIndex = (selectedIndex + (reverse ? count - 1 : 1)) % count
        }
    }
    public mutating func commit() -> Int? {
        defer { reset() }
        return selectedIndex
    }
    public mutating func reset() { selectedIndex = nil; count = 0 }
}

/// Keeps observed window focus order without sampling the screen in the background.
public struct WindowHistory: Sendable {
    private var identifiers: [String] = []
    public init() {}
    public mutating func record(_ id: String) {
        identifiers.removeAll { $0 == id }
        identifiers.insert(id, at: 0)
        if identifiers.count > 256 { identifiers.removeLast(identifiers.count - 256) }
    }
    public mutating func remove(processID: Int32) {
        identifiers.removeAll { $0.hasPrefix("\(processID):") }
    }
    public func rank(of id: String) -> Int { identifiers.firstIndex(of: id) ?? Int.max }
}

public enum WindowSwitchPolicy {
    public static func intercepts(mode: ApplicationMode, enabled: Bool,
                                  layoutSupported: Bool, inputReady: Bool,
                                  manualPassThrough: Bool,
                                  emergencyPaused: Bool) -> Bool {
        mode == .macOS && enabled && layoutSupported && inputReady &&
            !manualPassThrough && !emergencyPaused
    }
}
