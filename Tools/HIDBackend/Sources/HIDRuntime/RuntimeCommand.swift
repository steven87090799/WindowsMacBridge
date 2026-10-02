import Foundation
import Darwin
import VirtualHID
import Security

public enum HIDRuntimeCommand {
    @MainActor public static func handle(_ arguments: [String]) -> Bool {
        if arguments.count == 2 && arguments[0] == "--controller-pin" {
            var code: SecStaticCode?, info: CFDictionary?
            guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: arguments[1]) as CFURL, [], &code) == errSecSuccess, let code,
                  SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil) == errSecSuccess,
                  SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                  let values = info as? [String: Any], values[kSecCodeInfoIdentifier as String] as? String == "local.WindowsMacBridge",
                  let hash = values[kSecCodeInfoUnique as String] as? Data, hash.count == 20,
                  let data = try? PropertyListSerialization.data(fromPropertyList: ["CDHash": hash], format: .xml, options: 0) else { exit(1) }
            FileHandle.standardOutput.write(data); return true
        }
        if arguments == ["--hid-service"] {
            guard geteuid() == 0, let service = InputService() else { print("Root-owned installation pin unavailable; no capture started."); exit(77) }
            service.run(); return true
        }
        if arguments == ["--hid-self-check"] {
            var state = WMBHIDState()
            state.fn = true
            var buffer = [UInt8](repeating: 0, count: 128)
            let size = wmb_encode_fn(&state, &buffer, buffer.count)
            guard size == 65, buffer[0] == 3, buffer[1] == 3 else { exit(1) }
            print("WindowsMacBridge HID codec OK; driver=\(wmb_driver_version()) protocol=\(wmb_client_protocol_version())")
            print("No service connection, virtual keyboard, device capture or output was started.")
            return true
        }
        if arguments == ["--probe-driver"] {
            guard geteuid() == 0 else {
                print("Driver probe requires the WindowsMacBridge privileged input context; no escalation attempted.")
                exit(77)
            }
            guard let client = wmb_virtual_hid_create() else { print("Unable to create driver client."); exit(1) }
            var ready = false
            for _ in 0..<150 {
                let status = wmb_virtual_hid_status(client)
                if status & UInt32(WMB_DRIVER_MISMATCH) != 0 { break }
                if status & UInt32(WMB_KEYBOARD_READY) != 0 && status & UInt32(WMB_CONNECTION_FAULT) == 0 {
                    ready = true; break
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            print("Driver status flags: \(wmb_virtual_hid_status(client)); ready=\(ready)")
            wmb_virtual_hid_destroy(client)
            print("No physical device was seized; no non-empty keyboard report was sent.")
            exit(ready ? 0 : 1)
        }
        return false
    }
}
