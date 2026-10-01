import Foundation
import BridgeCore

/// Event-driven settings handshake for a sandboxed Finder Sync extension.
/// No shared container, timer, file access or permission request is needed.
@MainActor public final class FinderModePublisher {
    private let center: DistributedNotificationCenter
    private let channel: FinderModeChannel
    private var observer: NSObjectProtocol?
    private var enabled = false
    private var replyPending = false
    private var generation: UInt64 = 0
    public init(center: DistributedNotificationCenter = .default(), channel: FinderModeChannel = .current) {
        self.center = center; self.channel = channel
    }
    public func start(enabled: Bool) {
        stop()
        self.enabled = enabled
        observer = center.addObserver(forName: channel.requestName, object: FinderModeChannel.requestObject,
                                       queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.queueReply() }
        }
        publish(enabled)
    }
    public func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if observer != nil { publish(value) }
    }
    public func stop() {
        generation &+= 1
        replyPending = false
        if let observer {
            publish(false)
            center.removeObserver(observer)
        }
        observer = nil
    }
    private func queueReply() {
        guard !replyPending, observer != nil else { return }
        replyPending = true
        let expected = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == expected, self.observer != nil else { return }
            self.replyPending = false
            self.publish(self.enabled)
        }
    }
    private func publish(_ value: Bool) {
        center.postNotificationName(channel.stateName, object: FinderModeChannel.object(enabled: value),
                                    userInfo: nil, deliverImmediately: true)
    }
}
