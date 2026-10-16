import Foundation

public enum ShortcutPreviewSource: String, CaseIterable, Sendable {
    case local, remoteWindows, remoteMac, remoteAutomatic
    public var title: String {
        switch self {
        case .local: "本機鍵盤"
        case .remoteWindows: "遠端：原始 Windows 按鍵"
        case .remoteMac: "遠端：已轉成 Mac 按鍵"
        case .remoteAutomatic: "遠端：未知來源自動判定"
        }
    }
}

/// Value-only input to the same processors used by live input. No event posting,
/// process lookup, keyboard capture, permissions or persisted settings here.
public struct ShortcutPreviewConfiguration: Equatable, Sendable {
    public var context = ApplicationContext()
    public var enabled = true
    public var layoutSupported = true
    public var finderEnabled = true
    public var finderPermanentDeleteEnabled = true
    public var textNavigationEnabled = true
    public var altF4Enabled = true
    public var windowsKeyModifier: WindowsKeyModifier = .command
    public var winRunEnabled = false, winSettingsEnabled = false, winTaskViewEnabled = false
    public var screenshotEnabled = true
    public var printScreen: PrintScreenBehavior = .snipping
    public var source: ShortcutPreviewSource = .local
    public init() {}
}

public struct ShortcutPreviewResult: Equatable, Sendable, Identifiable {
    public let input: Shortcut
    public let decision: EventDecision
    public var id: Shortcut { input }
    public var output: String {
        switch decision {
        case .passThrough: ShortcutPreview.label(input) + "（原樣通過）"
        case .suppress: "不輸出按鍵"
        case .rewrite(let key, let flags, _): ShortcutPreview.label(.init(keyCode: key, modifiers: flags))
        case .emergencyPause: "暫停所有輸入輔助"
        case .togglePassThrough: "切換原樣通過"
        case .action(let action, _):
            switch action {
            case .terminalCopyOrInterrupt: "有選取：複製；無選取：中斷命令"
            case .finder(let action):
                switch action {
                case .copy: "Finder：複製"
                case .cut: "Finder：標記剪下，貼上時移動"
                case .paste: "Finder：貼上／移動已剪下檔案"
                case .open: "Finder：開啟"
                case .rename: "Finder：重新命名"
                case .trash: "Finder：移到垃圾桶"
                case .permanentDelete: "Finder：顯示立即刪除確認"
                case .parentFolder: "Finder：上一層資料夾"
                case .newFolder: "Finder：新增資料夾"
                case .goToFolder: "Finder：前往資料夾"
                }
            case .system(let action):
                switch action {
                case .openFinder: "開啟 Finder"
                case .openSettings: "開啟系統設定"
                case .activityMonitor: "開啟活動監視器"
                }
            case .window(.close): "關閉目前視窗（保留未儲存提示）"
            case .screenshot(let kind):
                switch kind {
                case .region: "框選截圖並複製"
                case .activeWindow: "擷取目前視窗並複製"
                case .fullScreen: "擷取全螢幕並複製"
                case .fullScreenSave: "儲存全螢幕並複製"
                }
            }
        }
    }
}

public enum ShortcutPreview {
    public static func evaluate(_ input: Shortcut, configuration c: ShortcutPreviewConfiguration) -> ShortcutPreviewResult {
        let decision: EventDecision
        // The screenshot interceptor precedes the ordinary translation processor
        // and also works in Terminal/IDE. Reuse its matcher rather than a rule copy.
        var policyInput = RuntimePolicyInput()
        policyInput.shortcutEnabled = c.enabled; policyInput.screenshotEnabled = c.screenshotEnabled
        policyInput.foreground = c.context
        var policy = RuntimePolicyCoordinator()
        if c.source == .local, policy.transition(policyInput).permitsScreenshots,
           let kind = WindowsScreenshotShortcuts.match(key: input.keyCode, modifiers: input.modifiers,
                windowsKey: c.windowsKeyModifier, printScreen: c.printScreen) {
            decision = .action(.screenshot(kind), ruleID: "windows.screenshot")
        } else if c.source == .local {
            var processor = KeyboardEventProcessor()
            processor.configure(context: c.context, enabled: c.enabled, layoutSupported: c.layoutSupported,
                controlsEnabled: c.enabled, finderEnabled: c.finderEnabled,
                finderPermanentDeleteEnabled: c.finderPermanentDeleteEnabled,
                textNavigationEnabled: c.textNavigationEnabled, altF4Enabled: c.altF4Enabled,
                windowsKeyModifier: c.windowsKeyModifier, winRunEnabled: c.winRunEnabled,
                winSettingsEnabled: c.winSettingsEnabled, winTaskViewEnabled: c.winTaskViewEnabled,
                nativeAppSwitchEnabled: true, screenshotEnabled: c.screenshotEnabled, printScreen: c.printScreen)
            processor.reconcileNeutralHardware()
            for event in modifierEvents(input.modifiers) { _ = processor.process(event) }
            decision = processor.process(.init(.down, keyCode: input.keyCode, modifiers: input.modifiers))
        } else {
            var router = RemoteSourceRouter()
            let semantics: RemoteSemantics = c.source == .remoteWindows ? .windows :
                (c.source == .remoteMac ? .alreadyTranslated : .automatic)
            let producer = RemoteProducer(processID: 7, identity: "offline-preview", session: 1, revision: 1,
                transport: .generic, confidence: .unknown, semantics: semantics, independentFlags: true)
            var policy = SourceTranslationConfiguration()
            policy.context = c.context; policy.enabled = c.enabled; policy.layoutSupported = c.layoutSupported
            policy.finderEnabled = c.finderEnabled; policy.finderPermanentDeleteEnabled = c.finderPermanentDeleteEnabled
            policy.textNavigationEnabled = c.textNavigationEnabled; policy.altF4Enabled = c.altF4Enabled
            policy.winRunEnabled = c.winRunEnabled; policy.winSettingsEnabled = c.winSettingsEnabled
            policy.winTaskViewEnabled = c.winTaskViewEnabled; policy.screenshotEnabled = c.screenshotEnabled
            policy.printScreen = c.printScreen
            router.update(.init(producers: [producer]), configuration: policy)
            let evidence = InputOriginEvidence(processID: 7, stateID: -1)
            for event in modifierEvents(input.modifiers) { _ = router.process(event, evidence: evidence) }
            decision = router.process(.init(.down, keyCode: input.keyCode, modifiers: input.modifiers), evidence: evidence).decision
        }
        return .init(input: input, decision: decision)
    }

    public static func samples(windowsKey: WindowsKeyModifier) -> [Shortcut] {
        [.init(keyCode: 8, modifiers: .control), .init(keyCode: 8, modifiers: [.control, .shift]),
         .init(keyCode: 9, modifiers: .control), .init(keyCode: 7, modifiers: .control),
         .init(keyCode: 0, modifiers: .control), .init(keyCode: 1, modifiers: .control),
         .init(keyCode: 6, modifiers: .control), .init(keyCode: 16, modifiers: .control),
         .init(keyCode: 17, modifiers: .control), .init(keyCode: 48, modifiers: windowsKey.altFlag),
         .init(keyCode: 118, modifiers: windowsKey.altFlag), .init(keyCode: 15, modifiers: windowsKey.flag),
         .init(keyCode: 1, modifiers: windowsKey.flag.union(.shift)), .init(keyCode: 105, modifiers: []),
         .init(keyCode: 120, modifiers: []), .init(keyCode: 117, modifiers: []),
         .init(keyCode: 117, modifiers: .shift), .init(keyCode: 115, modifiers: [])]
    }

    public static let selectableKeys: [UInt16] = {
        Array(Set((WindowsCompatibilityRules.general + WindowsCompatibilityRules.browser +
            WindowsCompatibilityRules.finder + WindowsCompatibilityRules.finderExtras +
            WindowsCompatibilityRules.system + WindowsCompatibilityRules.systemExtras +
            WindowsCompatibilityRules.textNavigation).map(\.input.keyCode) + [48, 105, 118])).sorted()
    }()

    public static func label(_ chord: Shortcut) -> String {
        var parts: [String] = []
        for (flag, name): (Modifiers, String) in [(.control, "Ctrl"), (.option, "Option"), (.command, "Command"), (.shift, "Shift"), (.fn, "Fn")] {
            if chord.modifiers.contains(flag) { parts.append(name) }
        }
        parts.append(keyLabel(chord.keyCode))
        return parts.joined(separator: "+")
    }

    private static let keyNames: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
            12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",
            25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"Return",
            37:"L",38:"J",40:"K",43:",",45:"N",46:"M",48:"Tab",49:"Space",51:"Backspace",53:"Esc",
            105:"PrintScreen",115:"Home",117:"Delete",118:"F4",119:"End",120:"F2",123:"←",124:"→",125:"↓",126:"↑"]
    public static func keyLabel(_ key: UInt16) -> String {
        keyNames[key] ?? "Key \(key)"
    }

    private static func modifierEvents(_ flags: Modifiers) -> [KeyboardEvent] {
        var accumulated: Modifiers = []
        var events: [KeyboardEvent] = []
        for (side, key): (ModifierSide, UInt16) in [(.leftControl,59),(.leftOption,58),(.leftCommand,55),(.leftShift,56)] where flags.contains(side.group) {
            accumulated.insert(side.group)
            events.append(.init(.flagsChanged, keyCode: key, modifiers: accumulated, modifierSide: side, modifierDown: true))
        }
        return events
    }
}
