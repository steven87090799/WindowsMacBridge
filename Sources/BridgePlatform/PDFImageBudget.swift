import CoreGraphics
import BridgeCore

/// Runs only on the screenshot worker, before CoreGraphics draws any raster.
/// Page geometry cannot bound XObjects, soft masks or images inside nested forms.
final class PDFImageBudget {
    private var remainingBytes = ImageMemoryBudget.maximumDecodedBytes
    private var remainingNodes = 256
    private var visited = Set<CGPDFDictionaryRef>()
    private var valid = true
    private var pageContent: CGPDFContentStreamRef?

    func allows(_ page: CGPDFPage) -> Bool {
        guard let dictionary = page.dictionary else { return false }
        let content = CGPDFContentStreamCreateWithPage(page)
        pageContent = content
        defer { pageContent = nil; CGPDFContentStreamRelease(content) }
        guard inspectPageResources(dictionary) else { return false }
        return scan(content)
    }
    private func inspectPageResources(_ page: CGPDFDictionaryRef) -> Bool {
        // Resources is inheritable from the Pages tree. Inspecting only the leaf
        // lets a tiny page hide arbitrarily large images in its parent resources.
        var current = page
        var parents = Set<CGPDFDictionaryRef>()
        for _ in 0..<12 {
            guard parents.insert(current).inserted else { return false }
            var object: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(current, "Resources", &object) {
                var resources: CGPDFDictionaryRef?
                guard CGPDFDictionaryGetDictionary(current, "Resources", &resources), let resources else { return false }
                return inspectDictionary(resources, depth: 0)
            }
            var parent: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(current, "Parent", &parent), let parent else { return true }
            current = parent
        }
        return false
    }
    private func scan(_ content: CGPDFContentStreamRef) -> Bool {
        guard let table = CGPDFOperatorTableCreate() else { return false }
        defer { CGPDFOperatorTableRelease(table) }
        // CoreGraphics exposes a complete inline image stream at EI. No raster is
        // decoded by this metadata scan. Malformed or unbounded images fail closed.
        CGPDFOperatorTableSetCallback(table, "EI") { scanner, info in
            guard let info else { CGPDFScannerStop(scanner); return }
            let budget = Unmanaged<PDFImageBudget>.fromOpaque(info).takeUnretainedValue()
            var stream: CGPDFStreamRef?
            guard CGPDFScannerPopStream(scanner, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream),
                  budget.image(dictionary, inline: true) else {
                budget.valid = false; CGPDFScannerStop(scanner); return
            }
        }
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(self).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        return CGPDFScannerScan(scanner) && valid
    }
    private func inspectDictionary(_ dictionary: CGPDFDictionaryRef, depth: Int) -> Bool {
        guard depth <= 12, remainingNodes > 0, CGPDFDictionaryGetCount(dictionary) <= 64 else { return false }
        if visited.contains(dictionary) { return true }
        visited.insert(dictionary); remainingNodes -= 1
        var subtype: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype,
           String(cString: subtype) == "Image", !image(dictionary) { return false }
        var accepted = true
        CGPDFDictionaryApplyBlock(dictionary, { _, object, _ in
            accepted = self.inspectObject(object, depth: depth + 1)
            return accepted
        }, nil)
        return accepted
    }
    private func inspectObject(_ object: CGPDFObjectRef, depth: Int) -> Bool {
        guard depth <= 12, remainingNodes > 0 else { return false }
        remainingNodes -= 1
        switch CGPDFObjectGetType(object) {
        case .dictionary:
            var dictionary: CGPDFDictionaryRef?
            return CGPDFObjectGetValue(object, .dictionary, &dictionary) && dictionary.map { inspectDictionary($0, depth: depth) } == true
        case .stream:
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream), inspectDictionary(dictionary, depth: depth) else { return false }
            var subtype: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype,
               String(cString: subtype) == "Form" {
                var resources: CGPDFDictionaryRef?
                _ = CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
                guard let pageContent else { return false }
                let content = CGPDFContentStreamCreateWithStream(stream, resources ?? dictionary, pageContent)
                defer { CGPDFContentStreamRelease(content) }
                return scan(content)
            }
            return true
        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &array), let array,
                  CGPDFArrayGetCount(array) <= 64 else { return false }
            for index in 0..<CGPDFArrayGetCount(array) {
                var child: CGPDFObjectRef?
                guard CGPDFArrayGetObject(array, index, &child), let child, inspectObject(child, depth: depth + 1) else { return false }
            }
            return true
        default: return true
        }
    }
    private func image(_ dictionary: CGPDFDictionaryRef, inline: Bool = false) -> Bool {
        guard remainingNodes > 0 else { return false }
        remainingNodes -= 1
        var width = 0, height = 0, depth = 0
        guard CGPDFDictionaryGetInteger(dictionary, inline ? "W" : "Width", &width),
              CGPDFDictionaryGetInteger(dictionary, inline ? "H" : "Height", &height) else { return false }
        var mask = false
        _ = CGPDFDictionaryGetBoolean(dictionary, inline ? "IM" : "ImageMask", &mask)
        if mask { depth = 1 }
        else {
            guard CGPDFDictionaryGetInteger(dictionary, inline ? "BPC" : "BitsPerComponent", &depth),
                  (1...16).contains(depth) else { return false }
        }
        // Four channels bounds ordinary screenshot RGB/CMYK, gray and mask
        // rasters. Reject unverified multi-channel color spaces before rendering.
        if !mask {
            var color: CGPDFObjectRef?
            guard CGPDFDictionaryGetObject(dictionary, inline ? "CS" : "ColorSpace", &color), let color,
                  allowsColor(color, depth: 0) else { return false }
        }
        let bytesPerPixel = 4 * ((depth + 7) / 8)
        guard ImageMemoryBudget.allows(width: width, height: height, bytesPerPixel: bytesPerPixel),
              width * height <= remainingBytes / bytesPerPixel else { return false }
        remainingBytes -= width * height * bytesPerPixel
        return true
    }
    private func allowsColor(_ object: CGPDFObjectRef, depth: Int) -> Bool {
        guard depth <= 4 else { return false }
        var name: UnsafePointer<CChar>?
        if CGPDFObjectGetValue(object, .name, &name), let name {
            return ["DeviceRGB", "DeviceGray", "DeviceCMYK", "RGB", "G", "CMYK"].contains(String(cString: name))
        }
        var array: CGPDFArrayRef?
        guard CGPDFObjectGetValue(object, .array, &array), let array, CGPDFArrayGetCount(array) <= 4,
              CGPDFArrayGetName(array, 0, &name), let name else { return false }
        switch String(cString: name) {
        case "ICCBased":
            var profile: CGPDFStreamRef?
            guard CGPDFArrayGetStream(array, 1, &profile), let profile,
                  let dictionary = CGPDFStreamGetDictionary(profile) else { return false }
            var channels = 0, length = 0
            return CGPDFDictionaryGetInteger(dictionary, "N", &channels) && (1...4).contains(channels) &&
                CGPDFDictionaryGetInteger(dictionary, "Length", &length) && (1...4_194_304).contains(length)
        case "Indexed", "I":
            var base: CGPDFObjectRef?
            return CGPDFArrayGetObject(array, 1, &base) && base.map { allowsColor($0, depth: depth + 1) } == true
        default: return false
        }
    }
}
