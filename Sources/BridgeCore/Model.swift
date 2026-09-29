import Foundation

public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1)
    public static let command = Self(rawValue: 2)
    public static let option = Self(rawValue: 4)
    public static let shift = Self(rawValue: 8)
    public static let fn = Self(rawValue: 16)
}

/// The macOS modifier produced by the key the user treats as Windows/Win.
/// This selects only Win-specific shortcuts; it never swaps global modifiers.
public enum WindowsKeyModifier: String, CaseIterable, Codable, Sendable {
    case option, command
    public var flag: Modifiers { self == .option ? .option : .command }
    public var altFlag: Modifiers { self == .option ? .command : .option }
}

public enum ModifierSide: Int, CaseIterable, Sendable {
    case leftControl, rightControl, leftCommand, rightCommand
    case leftOption, rightOption, leftShift, rightShift
    public var group: Modifiers {
        switch self {
        case .leftControl, .rightControl: .control
        case .leftCommand, .rightCommand: .command
        case .leftOption, .rightOption: .option
        case .leftShift, .rightShift: .shift
        }
    }
    public var peer: Self { Self(rawValue: rawValue ^ 1)! }
}

public struct ModifierStateMachine: Sendable {
    private var sides: UInt8 = 0
    public private(set) var synchronized = true
    public init() {}
    public func isDown(_ side: ModifierSide) -> Bool { sides & (1 << side.rawValue) != 0 }
    public var aggregate: Modifiers {
        var value: Modifiers = []
        if sides & 0b00000011 != 0 { value.insert(.control) }
        if sides & 0b00001100 != 0 { value.insert(.command) }
        if sides & 0b00110000 != 0 { value.insert(.option) }
        if sides & 0b11000000 != 0 { value.insert(.shift) }
        return value
    }
    public mutating func observe(_ side: ModifierSide, down: Bool, aggregate: Modifiers) {
        if down { sides |= 1 << side.rawValue } else { sides &= ~(1 << side.rawValue) }
        let sideGroupDown = isDown(side) || isDown(side.peer)
        if sideGroupDown != aggregate.contains(side.group) { synchronized = false }
    }
    public mutating func invalidate() { synchronized = false }
    public mutating func reset() { sides = 0; synchronized = true }
}

public enum ApplicationMode: String, CaseIterable, Codable, Sendable {
    case macOS, terminal, remoteWindows, virtualMachine, game, ide, disabled
    public var allowsTranslation: Bool { self == .macOS }
    public var title: String {
        switch self {
        case .macOS: "Default macOS"
        case .terminal: "Terminal — Pass-through"
        case .remoteWindows: "Remote Session — Pass-through"
        case .virtualMachine: "Virtual Machine — Pass-through"
        case .game: "Game — Pass-through"
        case .ide: "IDE — Pass-through"
        case .disabled: "Disabled — Pass-through"
        }
    }
}

public struct ApplicationContext: Equatable, Sendable {
    public var processID: Int32
    public var bundleID: String
    public var displayName: String
    public var mode: ApplicationMode
    public var executablePath: String
    public var isBrowser: Bool
    public init(processID: Int32 = 0, bundleID: String = "", displayName: String = "Unknown",
                mode: ApplicationMode = .disabled, executablePath: String = "", isBrowser: Bool = false) {
        self.processID = processID; self.bundleID = bundleID
        self.displayName = displayName; self.mode = mode
        self.executablePath = executablePath; self.isBrowser = isBrowser
    }
}

public enum KeyPhase: Sendable { case down, up, flagsChanged }
public struct KeyboardEvent: Sendable {
    public var phase: KeyPhase
    public var keyCode: UInt16
    public var modifiers: Modifiers
    public var isRepeat: Bool
    public var isOwnEvent: Bool
    public var modifierSide: ModifierSide?
    public var modifierDown: Bool?
    public init(_ phase: KeyPhase, keyCode: UInt16, modifiers: Modifiers = [],
                isRepeat: Bool = false, isOwnEvent: Bool = false,
                modifierSide: ModifierSide? = nil, modifierDown: Bool? = nil) {
        self.phase = phase; self.keyCode = keyCode; self.modifiers = modifiers
        self.isRepeat = isRepeat; self.isOwnEvent = isOwnEvent
        self.modifierSide = modifierSide; self.modifierDown = modifierDown
    }
}

public struct Shortcut: Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: Modifiers
    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
}
public struct ShortcutRule: Sendable {
    public let id: String
    public let input: Shortcut
    public let output: Shortcut
    public let action: ShortcutAction?
    public init(id: String, input: Shortcut, output: Shortcut, action: ShortcutAction? = nil) {
        self.id = id; self.input = input; self.output = output
        self.action = action
    }
}

public enum EventDecision: Equatable, Sendable {
    case passThrough
    case suppress
    case rewrite(keyCode: UInt16, modifiers: Modifiers, ruleID: String)
    case emergencyPause
    case togglePassThrough
    case action(ShortcutAction, ruleID: String)
}

public enum FinderAction: String, Sendable, CaseIterable {
    case copy, cut, paste, open, rename, trash, permanentDelete, parentFolder, newFolder, goToFolder
}
public enum SystemAction: String, Sendable, CaseIterable { case openFinder, openSettings, activityMonitor }
public enum WindowAction: Equatable, Sendable {
    case close
}
public enum ShortcutAction: Equatable, Sendable {
    case finder(FinderAction)
    case system(SystemAction)
    case window(WindowAction)
}
