import AppKit
import Foundation
import ImageIO
import Testing
import BridgeCore
@testable import BridgePlatform

struct ScreenshotShortcutTests {
    private func nativeEvent(isDown: Bool) throws -> CGEvent {
        let source = try #require(CGEventSource(stateID: .privateState))
        return try #require(CGEvent(keyboardEventSource: source, virtualKey: 1, keyDown: isDown))
    }

    @Test func configuredPhysicalWindowsKeyDoesNotAcceptAltOrControl() throws {
        for selected in WindowsKeyModifier.allCases {
            var shortcut = ScreenshotShortcut(windowsKeyModifier: selected)
            let wanted = try nativeEvent(isDown: true)
            wanted.flags = selected == .option ? [.maskAlternate, .maskShift] : [.maskCommand, .maskShift]
            let other = try nativeEvent(isDown: true)
            other.flags = selected == .option ? [.maskCommand, .maskShift] : [.maskAlternate, .maskShift]
            #expect(shortcut.handle(type: .keyDown, event: other) == .passThrough)
            #expect(shortcut.handle(type: .keyDown, event: wanted) == .capture)
            let released = try nativeEvent(isDown: false)
            #expect(shortcut.handle(type: .keyUp, event: released) == .suppress)
            let control = try nativeEvent(isDown: true)
            control.flags = selected == .option ? [.maskControl, .maskAlternate, .maskShift] : [.maskControl, .maskCommand, .maskShift]
            #expect(shortcut.handle(type: .keyDown, event: control) == .passThrough)
        }
    }

    @Test func protectedProfileDoesNotClaimShortcutButPairsEarlierCaptureRelease() throws {
        var shortcut = ScreenshotShortcut(windowsKeyModifier: .option)
        let down = try nativeEvent(isDown: true)
        down.flags = [.maskAlternate, .maskShift]
        let up = try nativeEvent(isDown: false)
        #expect(shortcut.handle(type: .keyDown, event: down, allowsCapture: false) == .passThrough)
        #expect(shortcut.handle(type: .keyUp, event: up, allowsCapture: false) == .passThrough)
        #expect(shortcut.handle(type: .keyDown, event: down) == .capture)
        #expect(shortcut.handle(type: .keyUp, event: up, allowsCapture: false) == .suppress)
    }

    @Test func exactShortcutClaimsOneBalancedPair() {
        var shortcut = ScreenshotShortcut(windowsKeyModifier: .command)
        #expect(shortcut.handle(keyCode: 1, isDown: true, isRepeat: false,
                                command: true, shift: true, option: false, control: false) == .capture)
        #expect(shortcut.handle(keyCode: 1, isDown: true, isRepeat: true,
                                command: true, shift: true, option: false, control: false) == .suppress)
        #expect(shortcut.handle(keyCode: 1, isDown: false, isRepeat: false,
                                command: false, shift: false, option: false, control: false) == .suppress)
        #expect(shortcut.handle(keyCode: 1, isDown: false, isRepeat: false,
                                command: false, shift: false, option: false, control: false) == .passThrough)
    }

    @Test func otherChordsAndResetPassThrough() {
        var shortcut = ScreenshotShortcut(windowsKeyModifier: .command)
        for (key, command, shift, option, control) in [
            (UInt16(21), true, true, false, false),
            (UInt16(1), false, true, false, false),
            (UInt16(1), true, false, false, false),
            (UInt16(1), true, true, true, false),
            (UInt16(1), true, true, false, true)
        ] {
            #expect(shortcut.handle(keyCode: key, isDown: true, isRepeat: false,
                                    command: command, shift: shift, option: option, control: control) == .passThrough)
        }
        #expect(shortcut.handle(keyCode: 1, isDown: true, isRepeat: false,
                                command: true, shift: true, option: false, control: false) == .capture)
        shortcut.reset()
        #expect(shortcut.handle(keyCode: 1, isDown: false, isRepeat: false,
                                command: false, shift: false, option: false, control: false) == .passThrough)
    }

    @Test func missedReleaseCanRecoverOnFreshDown() {
        var shortcut = ScreenshotShortcut(windowsKeyModifier: .command)
        for _ in 0..<2 {
            #expect(shortcut.handle(keyCode: 1, isDown: true, isRepeat: false,
                                    command: true, shift: true, option: false, control: false) == .capture)
        }
    }

    @Test func thirtyDayScheduleUsesPersistentTimestamp() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ScreenshotCheckSchedule.delay(lastCheck: nil, now: now) == ScreenshotCheckSchedule.interval)
        #expect(ScreenshotCheckSchedule.delay(lastCheck: now.addingTimeInterval(-10), now: now) == ScreenshotCheckSchedule.interval - 10)
        #expect(ScreenshotCheckSchedule.delay(lastCheck: now.addingTimeInterval(-ScreenshotCheckSchedule.interval - 1), now: now) == 1)
        #expect(ScreenshotCheckSchedule.delay(lastCheck: now.addingTimeInterval(100), now: now) == ScreenshotCheckSchedule.interval)
    }

    @Test func translatedControlShiftSaveNeverStartsScreenshot() throws {
        var processor = KeyboardEventProcessor()
        processor.configure(context: .init(processID: .max, bundleID: "test.privateSave", mode: .macOS),
                            enabled: true, layoutSupported: true)
        processor.reconcileNeutralHardware()
        _ = processor.process(.init(.flagsChanged, keyCode: 59, modifiers: .control,
                                     modifierSide: .leftControl, modifierDown: true))
        _ = processor.process(.init(.flagsChanged, keyCode: 56, modifiers: [.control, .shift],
                                     modifierSide: .leftShift, modifierDown: true))
        var shortcut = ScreenshotShortcut(windowsKeyModifier: .command)
        for (phase, repeatKey) in [(KeyPhase.down, false), (.down, true), (.up, false)] {
            let decision = processor.process(.init(phase, keyCode: 1, modifiers: [.control, .shift],
                                                   isRepeat: repeatKey))
            guard case let .rewrite(key, modifiers, rule) = decision else {
                Issue.record("Save As translation must remain available: \(decision)")
                return
            }
            #expect(rule == "karabiner.20")
            let event = try nativeEvent(isDown: phase == .down)
            event.flags = [.maskControl, .maskShift]
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            EventRewriter.apply(to: event, keyCode: key, modifiers: modifiers,
                                marker: EventRewriter.generatedEventMarker)
            #expect(InputEngine.modifiers(event.flags) == [.command, .shift])
            // Reproduce the production order: Windows translation precedes the screenshot tap.
            #expect(shortcut.handle(type: event.type, event: event) == .passThrough)
        }
        #expect(processor.activePressCount == 0)
    }

    @Test func nativeWinAndControlChordsWorkWithEitherTapOrder() throws {
        for screenshotFirst in [false, true] {
            for useControl in [false, true] {
                var processor = KeyboardEventProcessor()
                processor.configure(context: .init(processID: .max, bundleID: "test.tapOrder", mode: .macOS),
                                    enabled: true, layoutSupported: true)
                processor.reconcileNeutralHardware()
                let modifier: Modifiers = useControl ? .control : .command
                _ = processor.process(.init(.flagsChanged, keyCode: useControl ? 59 : 55, modifiers: modifier,
                                             modifierSide: useControl ? .leftControl : .leftCommand, modifierDown: true))
                _ = processor.process(.init(.flagsChanged, keyCode: 56, modifiers: [modifier, .shift],
                                             modifierSide: .leftShift, modifierDown: true))
                var shortcut = ScreenshotShortcut(windowsKeyModifier: .command)
                for phase in [KeyPhase.down, .up] {
                    let event = try nativeEvent(isDown: phase == .down)
                    event.flags = useControl ? [.maskControl, .maskShift] : [.maskCommand, .maskShift]
                    // Actual macOS modifier flags, not the key legends or a synthetic Ctrl alias.
                    #expect(event.getIntegerValueField(.eventSourceUserData) == 0)
                    if screenshotFirst {
                        let screenshotDecision = shortcut.handle(type: event.type, event: event)
                        #expect(screenshotDecision == (useControl ? .passThrough : (phase == .down ? .capture : .suppress)))
                        if screenshotDecision != .passThrough { continue }
                    }
                    let decision = processor.process(.init(phase, keyCode: 1, modifiers: [modifier, .shift]))
                    if useControl {
                        guard case let .rewrite(key, output, rule) = decision else {
                            Issue.record("Ctrl Save As must still translate: \(decision)")
                            return
                        }
                        #expect(rule == "karabiner.20")
                        EventRewriter.apply(to: event, keyCode: key, modifiers: output,
                                            marker: EventRewriter.generatedEventMarker)
                        #expect(InputEngine.modifiers(event.flags) == [.command, .shift])
                    } else { #expect(decision == .passThrough) }
                    if !screenshotFirst {
                        #expect(shortcut.handle(type: event.type, event: event) ==
                                (useControl ? .passThrough : (phase == .down ? .capture : .suppress)))
                    }
                }
                #expect(processor.activePressCount == 0)
            }
        }
    }

    @Test func generatedEventsCannotReleaseOrRepeatAnOriginalScreenshotPress() throws {
        var shortcut = ScreenshotShortcut(windowsKeyModifier: .command)
        let down = try nativeEvent(isDown: true)
        down.flags = [.maskCommand, .maskShift]
        #expect(down.getIntegerValueField(.eventSourceUserData) == 0)
        #expect(shortcut.handle(type: .keyDown, event: down) == .capture)
        let ownUp = try nativeEvent(isDown: false)
        EventRewriter.apply(to: ownUp, keyCode: 1, modifiers: [.command, .shift],
                            marker: EventRewriter.generatedEventMarker)
        #expect(shortcut.handle(type: .keyUp, event: ownUp) == .passThrough)
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(shortcut.handle(type: .keyDown, event: down) == .suppress)
        let up = try nativeEvent(isDown: false)
        up.flags = [] // Modifiers released before the original S key.
        #expect(shortcut.handle(type: .keyUp, event: up) == .suppress)
        #expect(shortcut.handle(type: .keyUp, event: up) == .passThrough)
        // Another source's nonzero metadata is not our marker and remains eligible.
        let foreignDown = try nativeEvent(isDown: true)
        foreignDown.flags = [.maskCommand, .maskShift]
        foreignDown.setIntegerValueField(.eventSourceUserData, value: -1)
        #expect(shortcut.handle(type: .keyDown, event: foreignDown) == .capture)
    }
}

@MainActor struct ScreenshotClipboardTests {
    @Test func savedImageCopiesAsImageAndMissingFileIsRejected() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeScreenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let data = try #require(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
        try data.write(to: path)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("BridgeScreenshot-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(ScreenshotClipboard.copyImage(at: path, to: pasteboard) == .success)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) == data)
        #expect(NSImage(pasteboard: pasteboard) != nil)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) != nil)
        // AppKit can synthesize TIFF on request; this item only stores one PNG payload.
        #expect(pasteboard.pasteboardItems?.first?.types == [NSPasteboard.PasteboardType("public.png")])
        let changeCount = pasteboard.changeCount
        #expect(ScreenshotClipboard.copyImage(at: path.appendingPathExtension("missing"), to: pasteboard) == .unreadableImage)
        #expect(pasteboard.changeCount == changeCount)
    }

    @Test func jpegScreenshotIsConvertedToPasteablePNG() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeScreenshot-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: path) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                      bitsPerPixel: 0)
        try #require(bitmap?.representation(using: .jpeg, properties: [:])).write(to: path)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("BridgeScreenshot-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(ScreenshotClipboard.copyImage(at: path, to: pasteboard) == .success)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) != nil)
    }

    @Test func tiffAndPdfScreenshotFormatsStillProducePasteablePNG() throws {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        let pdf = view.dataWithPDF(inside: view.bounds)
        for (suffix, data) in [("tiff", tiff), ("pdf", pdf)] {
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeScreenshot-\(UUID().uuidString).\(suffix)")
            defer { try? FileManager.default.removeItem(at: path) }
            try data.write(to: path)
            let pasteboard = NSPasteboard(name: .init("BridgeScreenshot-\(UUID().uuidString)"))
            defer { pasteboard.releaseGlobally() }
            #expect(ScreenshotClipboard.copyImage(at: path, to: pasteboard) == .success, "format: \(suffix)")
            #expect(NSImage(pasteboard: pasteboard) != nil, "format: \(suffix)")
        }
    }

    @Test func backgroundImagePreparationPublishesOnlyImmutableImageData() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeWorker-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let original = try #require(bitmap.representation(using: .png, properties: [:]))
        try original.write(to: path)
        let payload = try #require(await Task.detached { ScreenshotImagePreparation.prepare(at: path) }.value)
        let pasteboard = NSPasteboard(name: .init("BridgeWorker-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(ScreenshotClipboard.write(payload, to: pasteboard) == .success)
        #expect(pasteboard.data(forType: .init("public.png")) == original)
        #expect(NSImage(pasteboard: pasteboard) != nil)
    }
}

@MainActor struct ScreenshotImageBudgetTests {
    @Test func inheritedPDFResourcesCannotBypassRasterBudget() throws {
        for width in [1, 40000] {
            let text = "%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 /Resources << /XObject << /Im 5 0 R >> >> >> endobj\n3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 8 8] /Contents 4 0 R >> endobj\n4 0 obj << /Length 6 >> stream\n/Im Do\nendstream endobj\n5 0 obj << /Type /XObject /Subtype /Image /Width \(width) /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 3 >> stream\nabc\nendstream endobj\ntrailer << /Root 1 0 R >>\n%%EOF"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeInheritedPDF-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: url) }
            try Data(text.utf8).write(to: url)
            let document = try #require(CGPDFDocument(url as CFURL))
            let page = try #require(document.page(at: 1))
            // Inspect metadata only: a failing guard must not try to render the oversized fixture.
            #expect(PDFImageBudget().allows(page) == (width == 1))
        }
    }
    @Test func ordinaryRasterPDFAndInlineScreenshotStaySupported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeRasterPDF-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let imageContext = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        imageContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        imageContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(imageContext.makeImage())
        var bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        let pdf = try #require(CGContext(url as CFURL, mediaBox: &bounds, nil))
        pdf.beginPDFPage(nil); pdf.draw(image, in: bounds); pdf.endPDFPage(); pdf.closePDF()
        #expect(ScreenshotImagePreparation.prepare(at: url) != nil)
        // Tiny inline RGB image, containing no XObject resource dictionary.
        let text = "%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 8 8] /Resources << >> /Contents 4 0 R >> endobj\n"
        for width in [1, 40000] {
            let command = "BI /W \(width) /H 1 /CS /RGB /BPC 8 ID abc EI"
            try Data((text + "4 0 obj << /Length \(command.utf8.count) >> stream\n\(command)\nendstream endobj\ntrailer << /Root 1 0 R >>\n%%EOF").utf8).write(to: url)
            #expect((ScreenshotImagePreparation.prepare(at: url) != nil) == (width == 1))
        }
    }
    @Test func smallPDFPageCannotHideAnOversizedRasterOrNestedImage() throws {
        for nested in [false, true] {
            let resources = nested ? "<< /XObject << /F 6 0 R >> >>" : "<< /XObject << /Im 5 0 R >> >>"
            let command = nested ? "/F Do" : "/Im Do"
            let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 8 8] /Resources \(resources) /Contents 4 0 R >>",
                "<< /Length \(command.utf8.count) >>\nstream\n\(command)\nendstream",
                "<< /Type /XObject /Subtype /Image /Width 40000 /Height 40000 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 3 >>\nstream\nabc\nendstream",
                "<< /Type /XObject /Subtype /Form /BBox [0 0 8 8] /Resources << /XObject << /Im 5 0 R >> >> /Length 6 >>\nstream\n/Im Do\nendstream"]
            var data = Data("%PDF-1.4\n".utf8); var offsets = [0]
            for (index, object) in objects.enumerated() {
                offsets.append(data.count); data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
            }
            let start = data.count
            let rows = offsets.dropFirst().map { String(format: "%010d 00000 n \n", $0) }.joined()
            data.append(Data("xref\n0 7\n0000000000 65535 f \n\(rows)trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n".utf8))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("BridgePDFBudget-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: url) }
            try data.write(to: url)
            #expect(CGPDFDocument(url as CFURL)?.page(at: 1) != nil)
            if case .failure(let error) = ScreenshotImagePreparation.prepareResult(at: url) {
                #expect(error == .decodeFailure)
            } else { Issue.record("PDF page dimensions bypassed the embedded raster budget") }
        }
    }
    @Test func oversizedPNGMetadataIsRejectedBeforeBitmapCreation() throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        var data = try #require(bitmap.representation(using: .png, properties: [:]))
        data.replaceSubrange(16..<20, with: [0, 0, 0x9c, 0x40]) // width 40000, valid PNG IHDR checksum
        var crc: UInt32 = .max
        for byte in data[12..<29] {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        crc ^= .max
        data.replaceSubrange(29..<33, with: (0..<4).map { UInt8(truncatingIfNeeded: crc >> (24 - $0 * 8)) })
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeBudget-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        try data.write(to: path)
        let result = ScreenshotImagePreparation.prepareResult(at: path)
        if case .failure(let failure) = result { #expect(failure == .decodeFailure) }
        else { Issue.record("Oversized image passed decoding policy") }
    }
}

struct ScreenshotEncodingBudgetTests {
    @Test func realPNGEncoderStopsAtEncodedByteBudgetAndProducesDecodableOutputWithinBudget() throws {
        let bitmap = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let image = try #require(bitmap.makeImage())
        if case .failure(let error) = ScreenshotImagePreparation.encodePNG(image, maximumBytes: 32) {
            #expect(error == .encodeFailure)
        } else { Issue.record("Encoder exceeded its 32-byte test budget") }
        let encoded = try ScreenshotImagePreparation.encodePNG(image, maximumBytes: 4096).get()
        #expect(encoded.png.count <= 4096)
        let source = try #require(CGImageSourceCreateWithData(encoded.png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 32 && decoded.height == 32)
    }
}
