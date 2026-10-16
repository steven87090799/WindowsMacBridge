import BridgeCore

extension BridgeSettings {
    public func shortcutPreview(context: ApplicationContext, enabled: Bool = true,
                                source: ShortcutPreviewSource = .local) -> ShortcutPreviewConfiguration {
        var value = ShortcutPreviewConfiguration()
        value.context = context; value.enabled = enabled; value.source = source
        value.finderEnabled = finderEnabled; value.finderPermanentDeleteEnabled = finderPermanentDeleteEnabled
        value.textNavigationEnabled = textNavigationEnabled; value.altF4Enabled = altF4Enabled
        value.windowsKeyModifier = windowsKeyModifier
        value.winRunEnabled = winRunEnabled; value.winSettingsEnabled = winSettingsEnabled
        value.winTaskViewEnabled = winTaskViewEnabled
        value.screenshotEnabled = screenshotAutoCopy; value.printScreen = printScreenBehavior
        return value
    }
}
