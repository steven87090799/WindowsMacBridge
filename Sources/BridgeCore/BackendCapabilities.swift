/// A source-scoped profile must never silently become a global remap.
public enum KeyboardScope: String, Codable, CaseIterable, Sendable {
    case allKeyboards
    case builtInAndApple834
    public var title: String {
        switch self {
        case .allKeyboards: "所有鍵盤（快捷鍵預覽）"
        case .builtInAndApple834: "內建或 Apple 1452/834（需要裝置後端）"
        }
    }
}

public struct KeyboardDevice: Equatable, Sendable {
    public var registryID: UInt64
    public var builtIn: Bool
    public var vendorID: Int
    public var productID: Int
    public var isKeyboard: Bool
    public init(registryID: UInt64, builtIn: Bool, vendorID: Int, productID: Int, isKeyboard: Bool = true) {
        self.registryID = registryID; self.builtIn = builtIn
        self.vendorID = vendorID; self.productID = productID; self.isKeyboard = isKeyboard
    }
    public var matchesRequestedScope: Bool {
        builtIn || (isKeyboard && vendorID == 1452 && productID == 834)
    }
}

public struct BackendCapabilities: Sendable {
    public var deviceIdentity: Bool
    public var selectiveCapture: Bool
    public var modifierRemapping: Bool
    public var fnRemapping: Bool
    public var consumerEvents: Bool
    public static let eventTap = Self(deviceIdentity: false, selectiveCapture: false,
                                     modifierRemapping: false, fnRemapping: false, consumerEvents: false)
    public func supports(_ scope: KeyboardScope) -> Bool {
        scope == .allKeyboards || (deviceIdentity && selectiveCapture)
    }
    public var canReplaceRequestedProfile: Bool {
        deviceIdentity && selectiveCapture && modifierRemapping && fnRemapping && consumerEvents
    }
}
