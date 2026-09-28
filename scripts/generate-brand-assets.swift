// Deterministic vector artwork. Run with: swift scripts/generate-brand-assets.swift <output>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Brand", isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func stroke(_ points: [NSPoint], width: CGFloat, color: NSColor = .white) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
    color.setStroke(); path.stroke()
}

func drawBridge(in rect: NSRect, paused: Bool, menu: Bool) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current!.cgContext.translateBy(x: rect.minX, y: rect.minY)
    NSGraphicsContext.current!.cgContext.scaleBy(x: rect.width / 600, y: rect.height / 380)
    let ink: NSColor = menu ? .black : .white
    let frame = NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: 580, height: 360), xRadius: 64, yRadius: 64)
    frame.lineWidth = menu ? 28 : 17; ink.setStroke(); frame.stroke()
    if paused {
        stroke([NSPoint(x: 253, y: 150), NSPoint(x: 253, y: 260)], width: 32, color: ink)
        stroke([NSPoint(x: 347, y: 150), NSPoint(x: 347, y: 260)], width: 32, color: ink)
    } else {
        // Opposing arrows sit inside a keyboard: a translation layer, with no lettering.
        stroke([NSPoint(x: 140, y: 260), NSPoint(x: 460, y: 260)], width: menu ? 24 : 18, color: ink)
        stroke([NSPoint(x: 402, y: 310), NSPoint(x: 460, y: 260), NSPoint(x: 402, y: 210)], width: menu ? 24 : 18, color: ink)
        stroke([NSPoint(x: 460, y: 156), NSPoint(x: 140, y: 156)], width: menu ? 24 : 18, color: ink)
        stroke([NSPoint(x: 198, y: 206), NSPoint(x: 140, y: 156), NSPoint(x: 198, y: 106)], width: menu ? 24 : 18, color: ink)
    }
    stroke([NSPoint(x: 224, y: 65), NSPoint(x: 376, y: 65)], width: menu ? 23 : 15, color: ink)
    for x: CGFloat in [144, 416] {
        let key = NSBezierPath(roundedRect: NSRect(x: x, y: 48, width: 40, height: 34), xRadius: 7, yRadius: 7)
        key.lineWidth = menu ? 14 : 10; ink.setStroke(); key.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
}

func png(width: Int, height: Int, drawing: () -> Void) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    drawing()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

func appIcon(size: Int) -> Data {
    png(width: size, height: size) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 204, yRadius: 204)
        NSColor(calibratedWhite: 0.035, alpha: 1).setFill(); tile.fill()
        tile.lineWidth = 3; NSColor(calibratedWhite: 0.16, alpha: 1).setStroke(); tile.stroke()
        drawBridge(in: NSRect(x: 210, y: 315, width: 604, height: 383), paused: false, menu: false)
        NSGraphicsContext.restoreGraphicsState()
    }
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        try appIcon(size: points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try appIcon(size: 1024).write(to: output.appendingPathComponent("AppIcon.png"))
for paused in [false, true] {
    let data = png(width: 56, height: 36) {
        drawBridge(in: NSRect(x: 2, y: 2, width: 52, height: 32), paused: paused, menu: true)
    }
    try data.write(to: output.appendingPathComponent(paused ? "MenuBarPausedIcon.png" : "MenuBarIcon.png"))
}
print("Generated keyboard/translation artwork in \(output.path)")
