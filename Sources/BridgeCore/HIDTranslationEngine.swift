/// USB HID usage <-> macOS virtual key positions. Text/layout decoding is deliberately absent.
public enum HIDKeyMap {
    public static let carbon: [UInt16?] = {
        var result = [UInt16?](repeating: nil, count: 256)
        let letters: [UInt16] = [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6]
        for i in letters.indices { result[4+i] = letters[i] }
        let values: [(Int, UInt16)] = [(30,18),(31,19),(32,20),(33,21),(34,23),(35,22),(36,26),(37,28),(38,25),(39,29),
            (40,36),(41,53),(42,51),(43,48),(44,49),(45,27),(46,24),(47,33),(48,30),(49,42),(50,10),
            (51,41),(52,39),(53,50),(54,43),(55,47),(56,44),(57,57),(58,122),(59,120),(60,99),(61,118),
            (62,96),(63,97),(64,98),(65,100),(66,101),(67,109),(68,103),(69,111),(73,114),(74,115),(75,116),
            (76,117),(77,119),(78,121),(79,124),(80,123),(81,125),(82,126),(83,71),(84,75),(85,67),
            (86,78),(87,69),(88,76),(89,83),(90,84),(91,85),(92,86),(93,87),(94,88),(95,89),(96,91),
            (97,92),(98,82),(99,65),(100,10),(103,81),(104,105),(105,107),(106,113),(107,106),(108,64),
            (109,79),(110,80),(111,90)]
        for (usage, key) in values { result[usage] = key }
        return result
    }()
    public static let usage: [UInt16?] = {
        var result = [UInt16?](repeating: nil, count: 128)
        for i in carbon.indices { if let key = carbon[i], result[Int(key)] == nil { result[Int(key)] = UInt16(i) } }
        return result
    }()
}

public struct HIDOutput: Equatable, Sendable {
    public var modifiers: UInt8 = 0
    public var fn = false
    public var keys = [UInt16](repeating: 0, count: 32)
    public var consumer = [UInt16](repeating: 0, count: 32)
    public var topCase = [UInt16](repeating: 0, count: 32)
    public var vendor = [UInt16](repeating: 0, count: 32)
    public var desktop = [UInt16](repeating: 0, count: 32)
    public var keyCount = 0, consumerCount = 0, topCaseCount = 0, vendorCount = 0, desktopCount = 0
    public init() {}
    public var isEmpty: Bool {
        modifiers == 0 && !fn && keyCount + consumerCount + topCaseCount + vendorCount + desktopCount == 0
    }
}

/// Single input-thread owner. Physical holds, consumed modifiers and output presses are
/// bounded and independent per device. Outputs are never fed back into rule matching.
public struct HIDTranslationEngine: Sendable {
    private struct Press: Equatable, Sendable {
        var device: UInt64 = 0, page: UInt32 = 0
        var usage: UInt16 = 0, outputPage: UInt32 = 0, outputUsage: UInt16 = 0
        var modifiers: Modifiers = [], trigger: Modifiers = []
        var suppressed = false
    }
    private var devices = [UInt64?](repeating: nil, count: 16)
    private var physical = [UInt16](repeating: 0, count: 16)
    private var consumed = [UInt16](repeating: 0, count: 16)
    private var presses = [Press?](repeating: nil, count: 256)
    private var context = ApplicationContext()
    private var layoutSupported = false, finderEnabled = false
    private var waitingForNeutral = false
    public private(set) var manualPassThrough = false
    public private(set) var emergencyPaused = false
    public private(set) var faulted = false
    public private(set) var processed: UInt64 = 0, translated: UInt64 = 0
    public private(set) var lastRuleID: String?
    public init() { _ = RuleEngine.windows; _ = RuleEngine.finder; _ = RuleEngine.browser; _ = RuleEngine.system; _ = HIDKeyMap.usage }
    public mutating func register(_ id: UInt64) -> Bool {
        if devices.contains(id) { return true }
        guard let i = devices.firstIndex(of: nil) else { return false }
        devices[i] = id; return true
    }
    public mutating func disconnect(_ id: UInt64) {
        guard let i = devices.firstIndex(of: id) else { return }
        devices[i] = nil; physical[i] = 0; consumed[i] = 0
        for j in presses.indices where presses[j]?.device == id { presses[j] = nil }
        suppressShortcutsMissingModifiers()
        reconcile()
    }
    public mutating func configure(context: ApplicationContext, layoutSupported: Bool, finderEnabled: Bool) {
        if self.context != context || self.layoutSupported != layoutSupported || self.finderEnabled != finderEnabled { invalidate() }
        self.context = context; self.layoutSupported = layoutSupported; self.finderEnabled = finderEnabled
    }
    public mutating func restart() { manualPassThrough = false; emergencyPaused = false; faulted = false; invalidate() }
    public mutating func invalidate() {
        for i in presses.indices where presses[i] != nil { presses[i]?.suppressed = true }
        for i in physical.indices { consumed[i] = physical[i] }
        waitingForNeutral = true; reconcile()
    }
    private mutating func reconcile() {
        if physical.allSatisfy({ $0 == 0 }) && presses.allSatisfy({ $0 == nil }) {
            waitingForNeutral = false
            for i in consumed.indices { consumed[i] = 0 }
        }
    }
    public static func modifier(page: UInt32, usage: UInt16) -> HIDModifier? {
        if (page == 0xff && usage == 3) || (page == 0xff01 && usage == 3) { return .fn }
        guard page == 7 && (0xe0...0xe7).contains(usage) else { return nil }
        let values: [HIDModifier] = [.leftControl,.leftShift,.leftOption,.leftCommand,.rightControl,.rightShift,.rightOption,.rightCommand]
        return values[Int(usage-0xe0)]
    }
    private var aggregate: UInt16 { physical.reduce(0, |) }
    private mutating func suppressShortcutsMissingModifiers() {
        let held = Self.flags(aggregate)
        for i in presses.indices {
            if let press = presses[i], !press.trigger.isEmpty,
               !held.isSuperset(of: press.trigger) {
                presses[i]?.suppressed = true
            }
        }
    }
    private var local: Bool { context.mode == .macOS && layoutSupported && !manualPassThrough && !emergencyPaused }
    private static func flags(_ bits: UInt16) -> Modifiers {
        var result: Modifiers = []
        for m in HIDModifier.allCases where bits & m.bit != 0 {
            switch m {
            case .leftControl, .rightControl: result.insert(.control)
            case .leftCommand, .rightCommand: result.insert(.command)
            case .leftOption, .rightOption: result.insert(.option)
            case .leftShift, .rightShift: result.insert(.shift)
            case .fn: result.insert(.fn)
            }
        }
        return result
    }
    /// Return an allow-listed non-keyboard action once per physical down.
    public mutating func observe(device: UInt64, page: UInt32, usage: UInt16, down: Bool) -> ShortcutAction? {
        lastRuleID = nil
        guard let slot = devices.firstIndex(of: device), !faulted else { return nil }
        processed &+= 1
        if let m = Self.modifier(page: page, usage: usage) {
            if down { physical[slot] |= m.bit; if waitingForNeutral { consumed[slot] |= m.bit } }
            else {
                physical[slot] &= ~m.bit; consumed[slot] &= ~m.bit
                // A shortcut must not turn into a plain held key when its input
                // modifier is released before the key. Never resurrect it later.
                suppressShortcutsMissingModifiers()
            }
            reconcile(); return nil
        }
        let old = presses.firstIndex { $0?.device == device && $0?.page == page && $0?.usage == usage }
        if !down { if let old { presses[old] = nil }; reconcile(); return nil }
        guard old == nil else { return nil } // Virtual keyboard owns repeat; physical duplicate does not refire actions.
        guard let free = presses.firstIndex(of: nil) else { faulted = true; invalidate(); return nil }
        var press = Press(device: device, page: page, usage: usage, outputPage: page, outputUsage: usage,
                          suppressed: waitingForNeutral || emergencyPaused)
        let flags = Self.flags(aggregate)
        if page == 7 && usage == 0x13 && !waitingForNeutral {
            if flags == [.control,.option,.command] {
                presses[free] = press; emergencyPaused = true; invalidate(); return nil
            }
            if flags == .option && aggregate & HIDModifier.rightOption.bit != 0 && aggregate & HIDModifier.leftOption.bit == 0 {
                presses[free] = press; manualPassThrough.toggle(); invalidate(); return nil
            }
        }
        var rule: ShortcutRule?
        if local && !waitingForNeutral, page == 7, Int(usage) < HIDKeyMap.carbon.count, let key = HIDKeyMap.carbon[Int(usage)] {
            rule = RuleEngine.system.match(keyCode: key, modifiers: flags)
            if flags == .option && (aggregate & HIDModifier.leftOption.bit == 0 || aggregate & HIDModifier.rightOption.bit != 0) { rule = nil }
            if rule == nil && context.bundleID == "com.apple.finder" && finderEnabled { rule = RuleEngine.finder.match(keyCode: key, modifiers: flags) }
            if rule == nil && context.isBrowser { rule = RuleEngine.browser.match(keyCode: key, modifiers: flags) }
            if rule == nil && !(context.bundleID == "com.apple.finder" && key == 7 && !finderEnabled) {
                rule = RuleEngine.windows.match(keyCode: key, modifiers: flags)
            }
        }
        // Rule #77: consumer brightness increment -> Enter, only while local mapping is enabled.
        if local && !waitingForNeutral && page == 0x0c && usage == 0x6f {
            lastRuleID = "karabiner.77.brightness-enter"
            press.outputPage = 7; press.outputUsage = 0x28; translated &+= 1
        }
        if let rule {
            lastRuleID = rule.id
            press.trigger = rule.input.modifiers
            press.modifiers = rule.output.modifiers
            for i in physical.indices {
                for m in HIDModifier.allCases where physical[i] & m.bit != 0 && !Self.flags(m.bit).intersection(rule.input.modifiers).isEmpty {
                    consumed[i] |= m.bit
                }
            }
            translated &+= 1
            if let action = rule.action { press.suppressed = true; presses[free] = press; return action }
            guard let output = HIDKeyMap.usage[Int(rule.output.keyCode)] else { faulted = true; invalidate(); return nil }
            press.outputPage = 7; press.outputUsage = output
        }
        presses[free] = press; return nil
    }
    private static func usb(_ flags: Modifiers) -> UInt8 {
        (flags.contains(.control) ? 1 : 0) | (flags.contains(.shift) ? 2 : 0) |
        (flags.contains(.option) ? 4 : 0) | (flags.contains(.command) ? 8 : 0)
    }
    /// Writes into reusable caller-owned storage; overflow stops capture instead of dropping a release.
    public mutating func render(into output: inout HIDOutput) -> Bool {
        output.modifiers = 0; output.fn = false
        output.keyCount = 0; output.consumerCount = 0; output.topCaseCount = 0; output.vendorCount = 0; output.desktopCount = 0
        guard !waitingForNeutral && !emergencyPaused && !faulted else { return !faulted }
        for i in physical.indices {
            for m in HIDModifier.allCases where physical[i] & ~consumed[i] & m.bit != 0 {
                let mapped = local ? m.windowsMapping : m
                if mapped == .fn { output.fn = true; continue }
                let usb: [UInt8] = [1,16,8,128,4,64,2,32,0]
                output.modifiers |= usb[mapped.rawValue]
            }
        }
        let live = Self.flags(aggregate)
        for press in presses {
            guard let press, !press.suppressed else { continue }
            guard live.isSuperset(of: press.trigger) else { continue }
            output.modifiers |= Self.usb(press.modifiers)
            if press.modifiers.contains(.fn) { output.fn = true }
            let ok: Bool
            switch press.outputPage {
            case 7: ok = append(press.outputUsage, to: &output.keys, count: &output.keyCount)
            case 0x0c: ok = append(press.outputUsage, to: &output.consumer, count: &output.consumerCount)
            case 0xff: ok = append(press.outputUsage, to: &output.topCase, count: &output.topCaseCount)
            case 0xff01: ok = append(press.outputUsage, to: &output.vendor, count: &output.vendorCount)
            case 1: ok = append(press.outputUsage, to: &output.desktop, count: &output.desktopCount)
            default: ok = false
            }
            if !ok { faulted = true; invalidate(); return false }
        }
        return true
    }
    private func append(_ value: UInt16, to array: inout [UInt16], count: inout Int) -> Bool {
        for i in 0..<count where array[i] == value { return true }
        guard count < array.count else { return false }
        array[count] = value; count += 1; return true
    }
}
