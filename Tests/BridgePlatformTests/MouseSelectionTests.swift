import CoreGraphics
import Testing
import BridgeCore
@testable import BridgePlatform

struct MouseSelectionTests {
    @Test func inputTapSubscribesToClickReleaseAndDragAsWellAsKeyboard() {
        #expect(KeyboardEventTapCoverage.includesKeyboardEvents(InputEngine.eventMask))
        for type in [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged] {
            #expect(InputEngine.eventMask & (1 << type.rawValue) != 0)
        }
        #expect(InputEngine.eventMask & (1 << CGEventType.mouseMoved.rawValue) == 0)
    }
    private func configuration() -> EngineConfiguration {
        var config = EngineConfiguration()
        config.enabled = true
        config.context = ApplicationContext(processID: 100, bundleID: "com.apple.finder", mode: .macOS)
        return config
    }
    private func event(_ type: CGEventType, flags: CGEventFlags = .maskControl,
                       pid: Int64 = 0, state: Int64 = 1, target: Int64 = 100) throws -> CGEvent {
        let event = try #require(type == .flagsChanged ?
            CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: true) :
            CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: CGPoint(x: 42, y: 84), mouseButton: .left))
        event.flags = flags
        event.setIntegerValueField(.eventSourceUnixProcessID, value: pid)
        event.setIntegerValueField(.eventSourceStateID, value: state)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: target)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }
    private func apply(_ event: CGEvent, to rewriter: inout MouseSelectionRewriter,
                       config: EngineConfiguration, active: Bool = true) -> Bool {
        let evidence = InputOriginEvidence(processID: Int32(event.getIntegerValueField(.eventSourceUnixProcessID)),
            stateID: event.getIntegerValueField(.eventSourceStateID))
        let origin = config.inputRouting.classify(evidence, physicalBackend: config.physicalBackend)
        return rewriter.apply(to: event, origin: origin, configuration: config, active: active)
    }
    private func producer(semantics: RemoteSemantics = .automatic, confidence: InputConfidence = .known,
                          transport: RemoteTransport = .googleRemoteDesktop) -> RemoteProducer {
        RemoteProducer(processID: 42, identity: "host", session: 1, revision: 1,
            transport: transport, confidence: confidence, semantics: semantics, independentFlags: true)
    }

    @Test func localCtrlClickAndRepeatedSelectionUseCommandWithoutChangingClickMetadata() throws {
        var rewriter = MouseSelectionRewriter()
        let config = configuration()
        for _ in 0..<3 {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                // Real left/right Control include device-dependent side bits.
                let click = try event(type, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x2001))
                let timestamp = click.timestamp
                #expect(apply(click, to: &rewriter, config: config))
                #expect(click.flags == .maskCommand)
                #expect(click.type == type && click.location == CGPoint(x: 42, y: 84))
                #expect(click.timestamp == timestamp)
                #expect(click.getIntegerValueField(.mouseEventClickState) == 1)
                #expect(click.getIntegerValueField(.eventTargetUnixProcessID) == 100)
            }
        }
    }
    @Test func windowsGoogleRemoteCtrlClickUsesItsOwnPointerFlags() throws {
        var rewriter = MouseSelectionRewriter(), config = configuration()
        config.inputRouting = InputRoutingSnapshot(producers: [producer()])
        // No keyboard modifier edges are required from another source/stream.
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let click = try event(type, flags: [.maskControl, .maskShift], pid: 42, state: -1)
            #expect(apply(click, to: &rewriter, config: config))
            #expect(click.flags == [.maskCommand, .maskShift])
            #expect(click.getIntegerValueField(.eventSourceUnixProcessID) == 42)
        }
    }
    @Test func releaseCtrlBeforeMouseUpStillPairsTheSelectionAndLeavesNextClickPlain() throws {
        var rewriter = MouseSelectionRewriter()
        let config = configuration()
        #expect(apply(try event(.leftMouseDown), to: &rewriter, config: config))
        for type in [CGEventType.leftMouseDragged, .leftMouseUp] {
            let click = try event(type, flags: [])
            #expect(apply(click, to: &rewriter, config: config))
            #expect(click.flags == .maskAlternate)
        }
        let next = try event(.leftMouseDown, flags: [])
        #expect(!apply(next, to: &rewriter, config: config) && next.flags.isEmpty)
        #expect(!apply(try event(.leftMouseUp), to: &rewriter, config: config))
    }
    @Test func finderCtrlDragCopiesAndCtrlShiftDragMakesAliasInsteadOfMoving() throws {
        for shift in [false, true] {
            var rewriter = MouseSelectionRewriter()
            let config = configuration()
            let input: CGEventFlags = shift ? [.maskControl, .maskShift] : .maskControl
            #expect(apply(try event(.leftMouseDown, flags: input), to: &rewriter, config: config))
            let drag = try event(.leftMouseDragged, flags: input)
            #expect(apply(drag, to: &rewriter, config: config))
            let expected: CGEventFlags = shift ? [.maskCommand, .maskAlternate] : .maskAlternate
            #expect(drag.flags == expected)
            let drop = try event(.leftMouseUp, flags: [])
            #expect(apply(drop, to: &rewriter, config: config) && drop.flags == expected)
        }
    }
    @Test func nativeModifiersRightClickAndUnpairedEventsAreUntouched() throws {
        let config = configuration()
        for flags: CGEventFlags in [[], .maskCommand, .maskAlternate,
                                    [.maskControl, .maskAlternate], [.maskControl, .maskCommand],
                                    [.maskControl, .maskSecondaryFn]] {
            var rewriter = MouseSelectionRewriter()
            let click = try event(.leftMouseDown, flags: flags)
            #expect(!apply(click, to: &rewriter, config: config) && click.flags == flags)
        }
        for type in [CGEventType.rightMouseDown, .rightMouseUp, .otherMouseDown, .mouseMoved,
                     .flagsChanged, .leftMouseUp, .leftMouseDragged] {
            var rewriter = MouseSelectionRewriter()
            let click = try event(type)
            #expect(!apply(click, to: &rewriter, config: config) && click.flags == .maskControl)
        }
    }
    @Test func unknownAndNativeRemoteSourcesAreNotGuessedFromAPIDOrVNCName() throws {
        for remote in [producer(confidence: .unknown), producer(confidence: .likely, transport: .vnc),
                       producer(semantics: .macOS), producer(semantics: .alreadyTranslated)] {
            var rewriter = MouseSelectionRewriter(), config = configuration()
            config.inputRouting = InputRoutingSnapshot(producers: [remote])
            #expect(!apply(try event(.leftMouseDown, pid: 42), to: &rewriter, config: config))
        }
        var rewriter = MouseSelectionRewriter(), config = configuration()
        #expect(!apply(try event(.leftMouseDown, pid: 999), to: &rewriter, config: config))
        config.inputRouting = InputRoutingSnapshot(producers: [producer(semantics: .windows, confidence: .unknown, transport: .generic)])
        #expect(apply(try event(.leftMouseDown, pid: 42), to: &rewriter, config: config))
    }
    @Test func revokedSourceAndAnotherSourceCannotReuseHeldClick() throws {
        var rewriter = MouseSelectionRewriter(), config = configuration()
        let remote = producer()
        config.inputRouting = InputRoutingSnapshot(producers: [remote])
        #expect(apply(try event(.leftMouseDown, pid: 42), to: &rewriter, config: config))
        #expect(!apply(try event(.leftMouseUp), to: &rewriter, config: config))
        #expect(!apply(try event(.leftMouseUp, pid: 42, state: -1), to: &rewriter, config: config))
        remote.work.invalidate()
        #expect(!apply(try event(.leftMouseUp, pid: 42), to: &rewriter, config: config))
    }
    @Test func pauseSessionGapAndChangedRecipientCannotCarryCommandIntoNewClick() throws {
        for change in 0..<5 {
            var rewriter = MouseSelectionRewriter(), config = configuration()
            #expect(apply(try event(.leftMouseDown), to: &rewriter, config: config))
            switch change {
            case 0: config.enabled = false
            case 1: config.sessionActive = false
            case 2: rewriter.invalidate()
            case 3: config.context.mode = .remoteWindows
            default: config.context = ApplicationContext(processID: 101, bundleID: "other", mode: .macOS)
            }
            let up = try event(.leftMouseUp, target: change == 4 ? 101 : 100)
            #expect(!apply(up, to: &rewriter, config: config) && up.flags == .maskControl)
        }
        var rewriter = MouseSelectionRewriter()
        #expect(!apply(try event(.leftMouseDown), to: &rewriter, config: configuration(), active: false))
    }
    @Test func actualRecipientProtectionAndKeyboardScopeApplyToMouseToo() throws {
        for mode in [ApplicationMode.remoteWindows, .virtualMachine, .game, .disabled] {
            var rewriter = MouseSelectionRewriter(), config = configuration()
            config.recipients[200] = ApplicationContext(processID: 200, bundleID: "protected", mode: mode)
            #expect(!apply(try event(.leftMouseDown, target: 200), to: &rewriter, config: config))
        }
        var rewriter = MouseSelectionRewriter(), config = configuration()
        #expect(!apply(try event(.leftMouseDown, target: 0), to: &rewriter, config: config))
        #expect(!apply(try event(.leftMouseDown, target: 999), to: &rewriter, config: config))
        config.keyboardScope = .builtInAndApple834
        #expect(!apply(try event(.leftMouseDown), to: &rewriter, config: config))
        config.keyboardScope = .allKeyboards
        config.deviceInputs = [.init(identity: "native", experience: .nativeMac)]
        #expect(!apply(try event(.leftMouseDown), to: &rewriter, config: config))
        // Independent Windows remote sources remain usable with a native local keyboard.
        config.inputRouting = InputRoutingSnapshot(producers: [producer()])
        #expect(apply(try event(.leftMouseDown, pid: 42), to: &rewriter, config: config))
    }
    @Test func universalControlAndAllWindowsHIDUseDestinationPolicyButBridgeOutputNeverLoops() throws {
        var rewriter = MouseSelectionRewriter(), config = configuration()
        config.inputRouting = InputRoutingSnapshot(producers: [RemoteProducer(processID: 42, identity: "uc",
            session: 1, revision: 1, transport: .generic, confidence: .known, kind: .universalControl)])
        #expect(apply(try event(.leftMouseDown, pid: 42), to: &rewriter, config: config))
        config.physicalBackend = .deviceHID
        let click = try event(.leftMouseDown)
        #expect(apply(click, to: &rewriter, config: config))
        #expect(!apply(click, to: &rewriter, config: config))
    }
}
