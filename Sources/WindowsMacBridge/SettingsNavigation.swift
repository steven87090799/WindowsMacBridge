import SwiftUI

/// One native glass selection, shared by all rows. There is no display link,
/// timer, looping animation, delayed task or retained navigation controller.
struct SettingsNavigation: View {
    @Binding var selection: SettingsPage
    let advanced: Bool
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var pages: [SettingsPage] { SettingsPage.allCases.filter { advanced || $0 != .diagnostics } }
    private var opaque: Bool { reduceTransparency || contrast == .increased }
    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("設定").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).accessibilityAddTraits(.isHeader)
                navigationRows
            }
            .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 12)
        }
        .focusEffectDisabled()
    }

    @ViewBuilder private var navigationRows: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !opaque {
            // The longest jump is 7 rows × 44 pt. Keeping both endpoints in
            // this proximity lets the system morph one lens across any pair.
            GlassEffectContainer(spacing: 340) { rows }
        } else { rows }
        #else
        rows
        #endif
    }

    private var rows: some View {
        VStack(spacing: 4) {
            ForEach(pages, id: \.self) { page in
                Button { selection = page } label: {
                    if selection == page { selectedLabel(page) }
                    else { rowLabel(page) }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(page.detail)
                .accessibilityIdentifier("settings.navigation.\(page.symbol)")
                .accessibilityAddTraits(selection == page ? .isSelected : [])
                .onMoveCommand { direction in
                    guard let index = pages.firstIndex(of: selection) else { return }
                    if direction == .up, index > 0 { selection = pages[index - 1] }
                    if direction == .down, index + 1 < pages.count { selection = pages[index + 1] }
                }
            }
        }
        // Scope animation to navigation. The newly selected settings page and
        // its controls appear immediately, outside this animation transaction.
        .animation(selectionAnimation, value: selection)
    }

    private func rowLabel(_ page: SettingsPage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: page.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(opaque && selection == page ? Color(nsColor: .selectedControlTextColor) : page.navigationColor)
                .frame(width: 22).accessibilityHidden(true)
            Text(page.rawValue)
                .fontWeight(selection == page ? .semibold : .regular)
                .foregroundStyle(opaque && selection == page ? Color(nsColor: .selectedControlTextColor) : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
        .contentShape(Capsule())
    }

    @ViewBuilder private func selectedLabel(_ page: SettingsPage) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !opaque {
            // The label must be the glass content. A separate Color.clear
            // background lens can sample and blur the sibling label on macOS.
            rowLabel(page)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("settings-selection", in: glassNamespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else { rowLabel(page).background { fallbackSelection } }
        #else
        rowLabel(page).background { fallbackSelection }
        #endif
    }

    private var fallbackSelection: some View {
        Capsule().fill(opaque ? Color(nsColor: .selectedContentBackgroundColor) : Color.accentColor.opacity(0.15))
            .matchedGeometryEffect(id: "settings-selection", in: glassNamespace)
    }
}

private extension SettingsPage {
    var navigationColor: Color {
        switch self {
        case .permissions: .blue
        case .general: .secondary
        case .inputSources: .teal
        case .profiles: .indigo
        case .preview: .orange
        case .remoteCalibration: .cyan
        case .performance: .green
        case .diagnostics: .purple
        }
    }
}
