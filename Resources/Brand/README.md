# Brand assets

Black rounded tile, white keyboard outline, opposing arrows for shortcut translation.
The menu bar uses monochrome template PNGs; pause swaps arrows for two vertical bars.
No letters or Chinese text appear in either icon.

Source artwork is `scripts/generate-brand-assets.swift`, drawn with public AppKit/CoreGraphics.
The checked-in AppIcon.icns contains 16, 32, 128, 256 and 512 point images at 1x/2x.
Menu assets are compact 16×16 points at 2x and adapt to macOS light/dark appearance.

Regenerate outside a synchronized source folder, then copy the four output assets:

```sh
swift scripts/generate-brand-assets.swift "$TMPDIR/WindowsMacBridge-Brand"
iconutil -c icns "$TMPDIR/WindowsMacBridge-Brand/AppIcon.iconset" -o "$TMPDIR/WindowsMacBridge-Brand/AppIcon.icns"
```
