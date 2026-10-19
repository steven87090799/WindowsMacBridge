import AppKit
import SwiftUI

extension View {
    @ViewBuilder func bridgeGlassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { buttonStyle(.glass) }
        else { buttonStyle(.bordered) }
        #else
        buttonStyle(.bordered)
        #endif
    }
}

/// AppKit counterpart for the nonactivating screenshot panel. Accessibility
/// changes are applied while the panel exists, without a timer or polling.
@MainActor final class BridgeGlassPanelView: NSView {
    private let content: NSView
    private let radius: CGFloat

    init(frame: NSRect, content: NSView, cornerRadius: CGFloat) {
        self.content = content; radius = cornerRadius
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        rebuildMaterial()
    }

    @objc private func displayOptionsChanged() {
        DispatchQueue.main.async { [weak self] in self?.rebuildMaterial() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuildMaterial()
    }

    private func rebuildMaterial() {
        content.removeFromSuperview()
        subviews.forEach { $0.removeFromSuperview() }
        content.frame = bounds; content.autoresizingMask = [.width, .height]
        let workspace = NSWorkspace.shared
        let opaque = workspace.accessibilityDisplayShouldReduceTransparency || workspace.accessibilityDisplayShouldIncreaseContrast
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !opaque {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular; glass.cornerRadius = radius
            glass.autoresizingMask = [.width, .height]; glass.contentView = content
            addSubview(glass)
            return
        }
        #endif
        let effect = NSVisualEffectView(frame: bounds)
        effect.material = .popover; effect.blendingMode = .behindWindow
        effect.state = opaque ? .inactive : .active
        effect.autoresizingMask = [.width, .height]; effect.wantsLayer = true
        effect.layer?.cornerRadius = radius; effect.layer?.masksToBounds = true
        effect.layer?.backgroundColor = opaque ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        effect.layer?.borderWidth = opaque ? 1 : 0.5
        addSubview(effect); effect.addSubview(content)
    }

    required init?(coder: NSCoder) { nil }
}
