import SwiftUI
import BridgeCore
import BridgePlatform

struct RemoteCalibrationView: View {
    let sources: [RemoteSourceStatus]
    let status: RemoteCalibrationStatus
    let canCalibrate: Bool
    let preferenceNotice: String?
    var onDiscover: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onConfirm: () -> Void = {}
    var onCancel: () -> Void = {}
    var onUndo: () -> Void = {}
    var onCalibrate: (RemoteSourceStatus) -> Void = { _ in }
    var onReset: (RemoteSourceStatus) -> Void = { _ in }
    var onTransport: (RemoteTransport, RemoteSourceStatus) -> Void = { _, _ in }
    var onSemantics: (RemoteSemantics, RemoteSourceStatus) -> Void = { _, _ in }
    var body: some View {
        Form {
            Section("遠端來源校準") {
                Text("校準從其他電腦送入這台 Mac 的按鍵。先在本機文字 App 選取測試文字，再從指定來源按一次 Ctrl+C，確認辨識結果後套用。")
                    .foregroundStyle(.secondary)
                Text("只辨識明確開始後的一次 Ctrl+C；不會自動學習日常打字，也不保存測試文字。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("重新偵測來源", action: onDiscover)
                    if !canCalibrate {
                        Button("開啟一般設定與權限", action: onOpenSettings)
                    }
                }
                if !canCalibrate {
                    Text("請先開啟 Windows 模式總開關，並核准輔助功能及輸入監控。")
                        .foregroundStyle(.orange)
                }
                if let notice = status.notice {
                    Text(notice).textSelection(.enabled)
                }
                if let notice = preferenceNotice { Text(notice).foregroundStyle(.orange) }
                if let target = status.targetName, status.isActive {
                    LabeledContent("指定來源", value: target)
                }
                if let deadline = status.deadline {
                    let expiry = Date().addingTimeInterval(max(0, deadline - ProcessInfo.processInfo.systemUptime))
                    Text("有效至 \(expiry.formatted(date: .omitted, time: .standard))（最多 60 秒）")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if status.phase == .review {
                        Button("確認並套用結果", action: onConfirm).buttonStyle(.borderedProminent)
                    }
                    if status.isActive {
                        Button("取消校準", action: onCancel)
                    }
                    if status.canUndo {
                        Button("還原校準前設定", action: onUndo)
                    }
                }
            }
            if sources.isEmpty {
                Section("尚未觀察到遠端來源") {
                    Text("先連線到這台 Mac，從遠端電腦按一個鍵，再回此頁。只開啟遠端軟體不代表已收到遠端輸入。")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(sources) { source in
                Section(source.displayName) {
                    LabeledContent("輸入狀態", value: source.observedInput ? "已觀察到此來源的輸入" : "已偵測到軟體，尚未觀察到輸入")
                    Text("來源程序 \(source.processID)").font(.caption).foregroundStyle(.secondary)
                    Picker("遠端軟體", selection: Binding(get: { source.transport }, set: { onTransport($0, source) })) {
                        ForEach(RemoteTransport.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("送到 Mac 的按鍵", selection: Binding(get: { source.semantics }, set: { onSemantics($0, source) })) {
                        ForEach(RemoteSemantics.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    HStack {
                        Button("開始校準") { onCalibrate(source) }
                            .disabled(!source.observedInput || !canCalibrate || status.isActive)
                            .accessibilityLabel("開始校準 \(source.displayName)，程序 \(source.processID)")
                        Button("恢復自動判定") { onReset(source) }
                            .disabled(status.isActive)
                        Text(source.learned ? "已套用校準結果" : "自動／手動設定")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("原始 Windows 按鍵需要本機翻譯；已轉成 Mac 的按鍵保持原樣。未知來源的自動模式保持原樣。校準結果只代表本次觀察，遠端軟體或設定改變後可重新校準。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear(perform: onDiscover)
        .onDisappear { if status.isActive { onCancel() } }
    }
}

extension RemoteCalibrationView {
    init(controller: BridgeController) {
        self.init(sources: controller.remoteSources, status: controller.calibrationStatus,
                  canCalibrate: controller.canCalibrateRemote, preferenceNotice: controller.remotePreferenceNotice)
        onDiscover = controller.discoverRemoteSources
        onOpenSettings = { controller.settingsPage = .general }
        onConfirm = controller.confirmRemoteCalibration; onCancel = controller.cancelRemoteCalibration
        onUndo = controller.undoRemoteCalibration; onCalibrate = controller.calibrateRemote
        onReset = controller.resetRemotePreference
        onTransport = { controller.setRemoteTransport($0, source: $1) }
        onSemantics = { controller.setRemoteSemantics($0, source: $1) }
    }
}
