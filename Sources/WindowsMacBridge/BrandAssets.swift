import AppKit

@MainActor enum BrandAssets {
    static let active = statusImage(named: "MenuBarIcon")
    static let paused = statusImage(named: "MenuBarPausedIcon")

    private static func statusImage(named name: String) -> NSImage {
        let image = Bundle.main.url(forResource: name, withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "WindowsMacBridge")!
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true // Respect macOS light/dark menu bars and accessibility contrast.
        image.accessibilityDescription = "WindowsMacBridge"
        return image
    }
}
