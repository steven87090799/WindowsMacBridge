import Foundation
import Darwin
import VirtualHID

@main enum BridgeHIDHelperMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--self-check"] {
            var state = WMBHIDState()
            state.fn = true
            var buffer = [UInt8](repeating: 0, count: 128)
            let size = wmb_encode_fn(&state, &buffer, buffer.count)
            guard size == 65, buffer[0] == 3, buffer[1] == 3 else { exit(1) }
            print("BridgeHIDHelper codec OK; driver=\(wmb_driver_version()) protocol=\(wmb_client_protocol_version())")
            print("No service connection, virtual keyboard, device capture or output was started.")
            return
        }
        if arguments == ["--probe-driver"] {
            guard geteuid() == 0 else {
                print("Driver probe requires the installed privileged helper context; no escalation attempted.")
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
        print("Usage: BridgeHIDHelper --self-check | --probe-driver")
        print("Capture/IPC installation is not available in this development helper.")
        exit(64)
    }
}
