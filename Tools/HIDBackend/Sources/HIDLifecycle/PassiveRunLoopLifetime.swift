import CoreFoundation

/// Keeps an IPC-only run loop alive without initializing HID, adding a timer,
/// or causing periodic wakeups. Own and release it on the run loop's thread.
public final class PassiveRunLoopLifetime {
    private let loop: CFRunLoop
    private let source: CFRunLoopSource
    public init?() {
        var context = CFRunLoopSourceContext(version: 0, info: nil,
            retain: nil, release: nil, copyDescription: nil, equal: nil, hash: nil,
            schedule: nil, cancel: nil, perform: { _ in })
        guard let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else { return nil }
        self.loop = CFRunLoopGetCurrent()
        self.source = source
        CFRunLoopAddSource(loop, source, .commonModes)
    }
    deinit { CFRunLoopRemoveSource(loop, source, .commonModes) }
}
