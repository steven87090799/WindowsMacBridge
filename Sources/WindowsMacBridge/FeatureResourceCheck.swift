import Foundation
import Darwin
import MachO

/// Explicit metadata-only check. No AppKit startup, controller, permissions,
/// image analysis, screen contents or clipboard access.
enum FeatureResourceCheck {
    static func handle(_ arguments: [String]) -> Bool {
        guard arguments == ["--resource-self-check"] else { return false }
        let names = (0..<_dyld_image_count()).compactMap { index -> String? in
            guard let name = _dyld_get_image_name(index) else { return nil }
            return String(cString: name)
        }
        let frameworks = names.filter { name in
            ["/Vision.framework/", "/VisionKit.framework/", "/CoreML.framework/"].contains { name.contains($0) }
        }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let result: [String: Any] = ["scope":"metadata-only-no-GUI-or-input-engine",
            "loaded_ocr_frameworks":frameworks, "loaded_image_count":names.count,
            "physical_footprint_bytes":status == KERN_SUCCESS ? info.phys_footprint : 0]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
        return true
    }
}
