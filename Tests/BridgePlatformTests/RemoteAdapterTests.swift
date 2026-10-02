import Foundation
import CoreGraphics
import Testing
import BridgeCore
@testable import BridgePlatform

struct RemoteAdapterTests {
    @Test func asyncSourceValidationChecksLiveBirthWithoutWaitingForRegistryTick() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let birth = try #require(RemoteProcessResolver.birth(pid))
        let origin = SourceWorkGate(), frame = SourceWorkGate()
        let current = SourceWorkToken(origin: origin, frame: frame, producerProcessID: pid, producerSession: birth)
        let stale = SourceWorkToken(origin: origin, frame: frame, producerProcessID: pid, producerSession: birth &+ 1)
        #expect(current.validForAsyncWork && !stale.validForAsyncWork)
        #expect(stale.isCurrent, "The cached gate alone must not authorize a stale process session")
        frame.invalidate()
        #expect(!current.validForAsyncWork)
    }
    @Test func googleRequiresHostIdentityAndSignatureNotForegroundBrowser() {
        let browser = RemoteProcessIdentity(pid: 10, birth: 1, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                                           signingID: "com.google.Chrome", teamID: "EQHXZ8M8AV", signatureValid: true)
        #expect(RemoteAdapterCatalog.classify(browser).confidence == .unknown)
        var host = browser
        host.signingID = "com.google.chromeremotedesktop.me2me-host"
        let adapter = RemoteAdapterCatalog.classify(host)
        #expect(adapter.transport == .googleRemoteDesktop && adapter.confidence == .known && adapter.independentFlags)
        host.signatureValid = false
        #expect(RemoteAdapterCatalog.classify(host).confidence != .known)
        host.signatureValid = true; host.teamID = "other"
        #expect(RemoteAdapterCatalog.classify(host).confidence != .known)
    }
    @Test func remoteClientsAreCandidatesWithoutClaimingInjectionSemantics() {
        for (id, transport) in [("com.microsoft.rdc.macos", RemoteTransport.microsoftRemoteDesktop),
                                ("com.p5sys.jump.mac.viewer", .jumpDesktop), ("com.anydesk.AnyDesk", .anyDesk),
                                ("com.teamviewer.TeamViewer", .teamViewer), ("tv.parsec.www", .parsec),
                                ("com.carriez.RustDesk", .rustDesk), ("com.nomachine.nxdock", .noMachine),
                                ("com.realvnc.vncviewer", .vnc)] {
            let p = RemoteProcessIdentity(pid: 42, birth: 1, path: "/test", signingID: id, teamID: "", signatureValid: true)
            let a = RemoteAdapterCatalog.classify(p)
            #expect(a.transport == transport && a.confidence == .likely && !a.independentFlags)
        }
        #expect(RemoteTransport.allCases.count == 11)
    }
    @Test func actualCGEventExposesProducerMetadataWithoutPostingOrReadingUserInput() throws {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: true))
        #expect(event.type == .flagsChanged)
        #expect(event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier))
        let identity = try #require(RemoteProcessResolver.identity(ProcessInfo.processInfo.processIdentifier))
        #expect(identity.pid > 0 && identity.birth > 0 && !identity.path.isEmpty)
        #expect(RemoteProcessResolver.birth(identity.pid) == identity.birth)
    }
    @Test func learningIsArmedForOneSourceAndDoesNotStoreTyping() {
        let inbox = RemoteCalibrationInbox()
        inbox.arm(identity: "remoteA", processID: 42, session: 9)
        inbox.observe(processID: 43, key: 8, phase: .down, flags: .control, repeatKey: false)
        #expect(inbox.take() == nil)
        inbox.observe(processID: 42, key: 0, phase: .down, flags: [], repeatKey: false)
        #expect(inbox.take() == nil)
        inbox.observe(processID: 42, key: 8, phase: .down, flags: .command, repeatKey: false)
        let learned = inbox.take()
        #expect(learned?.identity == "remoteA" && learned?.semantics == .alreadyTranslated && learned?.session == 9)
        inbox.observe(processID: 42, key: 8, phase: .down, flags: .control, repeatKey: false)
        #expect(inbox.take() == nil)
        inbox.arm(identity: "remoteA", processID: 42, session: 10); inbox.cancel()
        inbox.observe(processID: 42, key: 8, phase: .down, flags: .control, repeatKey: false)
        #expect(inbox.take() == nil)
    }
}
