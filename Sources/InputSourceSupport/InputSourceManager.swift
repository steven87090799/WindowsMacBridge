// Adapted from vchewing-input-helper @ 43779320 (MIT). See Resources/Licenses/VChewingGuard.txt.
import Carbon
import Foundation
import InputSourceCore

struct InputSourceInfo {
    let identifier: String
    let bundleIdentifier: String?
    let localizedName: String?
    let sourceType: String?
    let isEnabled: Bool
    let isSelectable: Bool
    fileprivate let reference: TISInputSource?

    init(identifier: String, bundleIdentifier: String? = nil, localizedName: String? = nil,
         sourceType: String? = nil, isEnabled: Bool = true, isSelectable: Bool = true,
         reference: TISInputSource? = nil) {
        self.identifier = identifier; self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName; self.sourceType = sourceType
        self.isEnabled = isEnabled; self.isSelectable = isSelectable; self.reference = reference
    }

    var summary: String {
        "\(identifier) (\(localizedName ?? "未命名"), \(sourceType ?? "類型未提供"), \(isEnabled ? "已啟用" : "未啟用")\(isSelectable ? "" : ", 不可選擇"))"
    }
}

struct CurrentInputSourceInfo {
    let identifier: String?
    let localizedName: String?
}

struct InputSourceDiscovery {
    let traditional: InputSourceInfo?
    let abc: InputSourceInfo?
    let vChewingCandidates: [InputSourceInfo]
}

protocol InputSourceProviding {
    var discovery: InputSourceDiscovery { get }
    var traditionalIdentifier: String? { get }
    var abcIdentifier: String? { get }
    func rediscover(logChanges: Bool) -> InputSourceDiscovery
    func currentSource() -> CurrentInputSourceInfo
    func select(_ source: InputSourceInfo) -> OSStatus
}

extension InputSourceProviding {
    func rediscover() -> InputSourceDiscovery { rediscover(logChanges: true) }
    var currentIdentifier: String? { currentSource().identifier }
}

final class InputSourceManager: InputSourceProviding {
    private var lastLoggedFingerprint: String?
    private(set) var discovery = InputSourceDiscovery(
        traditional: nil,
        abc: nil,
        vChewingCandidates: []
    )

    func rediscover(logChanges: Bool = true) -> InputSourceDiscovery {
        let references = (TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
        let all = references.compactMap(Self.describe)

        let vChewingCandidates = all.filter(Self.isVChewing)
        let traditional = vChewingCandidates
            .filter(Self.isTraditionalVChewing)
            .sorted(by: Self.preferTraditionalCandidate)
            .first
        let abc = all
            .filter(Self.isABC)
            .sorted(by: Self.preferUsableCandidate)
            .first

        discovery = InputSourceDiscovery(
            traditional: traditional,
            abc: abc,
            vChewingCandidates: vChewingCandidates
        )

        let fingerprint = [
            traditional?.summary ?? "vChewing Traditional: not found",
            abc?.summary ?? "ABC: not found",
        ].joined(separator: " | ")
        if logChanges, fingerprint != lastLoggedFingerprint {
            lastLoggedFingerprint = fingerprint
            if let traditional {
                FileLogger.shared.log("Found vChewing Traditional: \(traditional.summary)")
            } else {
                FileLogger.shared.log(
                    "vChewing Traditional was not found; candidates: \(vChewingCandidates.map(\.summary).joined(separator: "; "))"
                )
            }
            if let abc {
                FileLogger.shared.log("Found ABC: \(abc.summary)")
            } else {
                FileLogger.shared.log("ABC input source was not found")
            }
        }
        return discovery
    }

    func currentSource() -> CurrentInputSourceInfo {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return CurrentInputSourceInfo(identifier: nil, localizedName: nil)
        }
        return CurrentInputSourceInfo(
            identifier: Self.stringProperty(current, kTISPropertyInputSourceID),
            localizedName: Self.stringProperty(current, kTISPropertyLocalizedName)
        )
    }

    var currentIdentifier: String? { currentSource().identifier }
    var currentName: String? { currentSource().localizedName }

    func select(_ source: InputSourceInfo) -> OSStatus {
        guard source.isEnabled, source.isSelectable, let reference = source.reference else { return OSStatus(paramErr) }
        return TISSelectInputSource(reference)
    }

    var traditionalIdentifier: String? { discovery.traditional?.identifier }
    var abcIdentifier: String? { discovery.abc?.identifier }

    static func observedSource(identifier: String?, discovery: InputSourceDiscovery) -> ObservedInputSource {
        guard let identifier else { return .other }
        if identifier == discovery.traditional?.identifier { return .vChewing }
        if identifier == discovery.abc?.identifier { return .abc }
        return .other
    }

    private static func describe(_ source: TISInputSource) -> InputSourceInfo? {
        guard let identifier = stringProperty(source, kTISPropertyInputSourceID), !identifier.isEmpty else {
            return nil
        }
        return InputSourceInfo(
            identifier: identifier,
            bundleIdentifier: stringProperty(source, kTISPropertyBundleID),
            localizedName: stringProperty(source, kTISPropertyLocalizedName),
            sourceType: stringProperty(source, kTISPropertyInputSourceType),
            isEnabled: booleanProperty(source, kTISPropertyInputSourceIsEnabled),
            isSelectable: booleanProperty(source, kTISPropertyInputSourceIsSelectCapable),
            reference: source
        )
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    private static func booleanProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let value = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }

    private static func isVChewing(_ source: InputSourceInfo) -> Bool {
        let id = source.identifier.lowercased()
        let bundle = source.bundleIdentifier?.lowercased() ?? ""
        let name = source.localizedName?.lowercased() ?? ""
        return bundle.contains("org.atelierinmu.inputmethod.vchewing")
            || id.contains("org.atelierinmu.inputmethod.vchewing")
            || name.contains("vchewing")
            || name.contains("唯音")
            || name.contains("威注音")
    }

    private static func isTraditionalVChewing(_ source: InputSourceInfo) -> Bool {
        let id = source.identifier.lowercased()
        let name = source.localizedName?.lowercased() ?? ""
        let type = source.sourceType ?? ""
        return (id.hasSuffix(".imecht") && type == kTISTypeKeyboardInputMode as String)
            || id.hasSuffix(".traditional")
            || id.hasSuffix(".cht")
            || name.contains("cht")
            || name.contains("繁")
            || name.contains("traditional")
    }

    private static func traditionalRank(_ source: InputSourceInfo) -> Int {
        let id = source.identifier.lowercased()
        if id == "org.atelierinmu.inputmethod.vchewing.imecht" { return 6 }
        if source.bundleIdentifier?.lowercased() == "org.atelierinmu.inputmethod.vchewing" { return 5 }
        if id.hasSuffix(".imecht") { return 4 }
        if id.hasSuffix(".cht") || id.hasSuffix(".traditional") { return 3 }
        return 1
    }

    private static func preferTraditionalCandidate(_ lhs: InputSourceInfo, _ rhs: InputSourceInfo) -> Bool {
        let lhsUsable = lhs.isEnabled && lhs.isSelectable
        let rhsUsable = rhs.isEnabled && rhs.isSelectable
        if lhsUsable != rhsUsable { return lhsUsable }

        if lhs.isEnabled != rhs.isEnabled { return lhs.isEnabled }

        let lhsRank = traditionalRank(lhs)
        let rhsRank = traditionalRank(rhs)
        if lhsRank != rhsRank { return lhsRank > rhsRank }

        return lhs.identifier < rhs.identifier
    }

    private static func preferUsableCandidate(_ lhs: InputSourceInfo, _ rhs: InputSourceInfo) -> Bool {
        let lhsUsable = lhs.isEnabled && lhs.isSelectable
        let rhsUsable = rhs.isEnabled && rhs.isSelectable
        if lhsUsable != rhsUsable { return lhsUsable }
        if lhs.isEnabled != rhs.isEnabled { return lhs.isEnabled }
        return lhs.identifier < rhs.identifier
    }

    private static func isABC(_ source: InputSourceInfo) -> Bool {
        if source.identifier == "com.apple.keylayout.ABC" { return true }
        let name = source.localizedName?.lowercased() ?? ""
        return source.bundleIdentifier == "com.apple.keyboardlayout.all"
            && (source.identifier.lowercased().hasSuffix(".abc") || name == "abc")
    }
}
