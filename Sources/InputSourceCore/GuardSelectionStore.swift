import Foundation

/// Persist only requests made through the app's buttons or Carbon hotkey.
/// The legacy preservedSourceIdentifier was inferred from TIS notifications,
/// which carry no initiator; it must never become an explicit guard target.
public final class GuardSelectionStore {
    private let defaults: UserDefaults
    private let key = "inputSource.guardDesiredSource"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public var desired: DesiredInputSource {
        DesiredInputSource(rawValue: defaults.string(forKey: key) ?? "") ?? .vChewing
    }

    public func recordRequest(_ source: DesiredInputSource) {
        defaults.set(source.rawValue, forKey: key)
    }
}
