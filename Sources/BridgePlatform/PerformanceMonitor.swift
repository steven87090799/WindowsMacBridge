import Combine
import Darwin
import Foundation

/// Kernel counters only. No process enumeration, screen/input access or disk writes.
public struct PerformanceReading: Sendable {
    public var uptime: Double
    public var processCPUSeconds: Double?
    public var cpuTicks: [UInt32]?
    public var physicalMemory: UInt64
    public var activeMemory: UInt64?
    public var wiredMemory: UInt64?
    public var compressedMemory: UInt64?
    public var processFootprint: UInt64?

    public init(uptime: Double, processCPUSeconds: Double?, cpuTicks: [UInt32]?, physicalMemory: UInt64,
                activeMemory: UInt64?, wiredMemory: UInt64?, compressedMemory: UInt64?, processFootprint: UInt64?) {
        self.uptime = uptime; self.processCPUSeconds = processCPUSeconds; self.cpuTicks = cpuTicks
        self.physicalMemory = physicalMemory; self.activeMemory = activeMemory; self.wiredMemory = wiredMemory
        self.compressedMemory = compressedMemory; self.processFootprint = processFootprint
    }

    public static func readCurrent() -> Self? {
        var cpu = host_cpu_load_info_data_t()
        var cpuCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: cpu) / MemoryLayout<integer_t>.size)
        var vm = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: vm) / MemoryLayout<integer_t>.size)
        // mach_host_self returns a send right; release it on every reading.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let cpuResult = withUnsafeMutablePointer(to: &cpu) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        var task = task_vm_info_data_t()
        var taskCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: task) / MemoryLayout<integer_t>.size)
        let taskResult = withUnsafeMutablePointer(to: &task) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(taskCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &taskCount)
            }
        }
        var usage = rusage()
        let usageResult = getrusage(RUSAGE_SELF, &usage)
        let processCPU = usageResult == 0 ? Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
            Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000 : nil
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        let page = UInt64(pageSize)
        return Self(uptime: ProcessInfo.processInfo.systemUptime, processCPUSeconds: processCPU,
            cpuTicks: cpuResult == KERN_SUCCESS ? [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3] : nil,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            activeMemory: vmResult == KERN_SUCCESS && pageResult == KERN_SUCCESS ? UInt64(vm.active_count) * page : nil,
            wiredMemory: vmResult == KERN_SUCCESS && pageResult == KERN_SUCCESS ? UInt64(vm.wire_count) * page : nil,
            compressedMemory: vmResult == KERN_SUCCESS && pageResult == KERN_SUCCESS ? UInt64(vm.compressor_page_count) * page : nil,
            processFootprint: taskResult == KERN_SUCCESS ? task.phys_footprint : nil)
    }
}

public struct PerformanceVisibility: Sendable {
    public var pageMounted: Bool
    public var windowVisible: Bool
    public var windowOccluded: Bool
    public var windowMiniaturized: Bool
    public var applicationHidden: Bool
    public var sessionAwake: Bool
    public var allowsSampling: Bool {
        pageMounted && windowVisible && !windowOccluded && !windowMiniaturized && !applicationHidden && sessionAwake
    }
    public init(pageMounted: Bool, windowVisible: Bool, windowOccluded: Bool, windowMiniaturized: Bool,
                applicationHidden: Bool, sessionAwake: Bool) {
        self.pageMounted = pageMounted; self.windowVisible = windowVisible; self.windowOccluded = windowOccluded
        self.windowMiniaturized = windowMiniaturized; self.applicationHidden = applicationHidden; self.sessionAwake = sessionAwake
    }
}

public struct PerformanceSnapshot: Equatable, Sendable {
    public let systemCPUPercent: Double?
    /// Activity Monitor convention: 100% is one logical core, so this may exceed 100%.
    public let processCPUPercent: Double?
    public let physicalMemory: UInt64
    public let systemUsedMemory: UInt64?
    public let compressedMemory: UInt64?
    public let processFootprint: UInt64?

    public init(current: PerformanceReading, previous: PerformanceReading?) {
        physicalMemory = current.physicalMemory
        compressedMemory = current.compressedMemory
        processFootprint = current.processFootprint
        if let active = current.activeMemory, let wired = current.wiredMemory, let compressed = current.compressedMemory {
            // Physical compressor pages, not the logical uncompressed page count.
            systemUsedMemory = min(physicalMemory, active + wired + compressed)
        } else { systemUsedMemory = nil }
        if let old = previous, current.uptime > old.uptime,
           let nowCPU = current.processCPUSeconds, let oldCPU = old.processCPUSeconds, nowCPU >= oldCPU {
            processCPUPercent = (nowCPU - oldCPU) / (current.uptime - old.uptime) * 100
        } else { processCPUPercent = nil }
        if let now = current.cpuTicks, let old = previous?.cpuTicks, now.count == 4, old.count == 4 {
            let delta = zip(now, old).map { UInt64($0 &- $1) }
            let total = delta.reduce(0, +)
            systemCPUPercent = total > 0 ? Double(total - delta[Int(CPU_STATE_IDLE)]) / Double(total) * 100 : nil
        } else { systemCPUPercent = nil }
    }
}

/// The cancellation object has no actor-isolated teardown, so deinit also
/// invalidates the timer if SwiftUI removes the owner without an onDisappear.
private final class PerformanceTimerLease: @unchecked Sendable {
    private let cancel: () -> Void
    init(_ cancel: @escaping () -> Void) { self.cancel = cancel }
    deinit { cancel() }
}

@MainActor public final class PerformanceMonitor: ObservableObject {
    @Published public private(set) var snapshot: PerformanceSnapshot?
    public var isSampling: Bool { lease != nil }
    private let read: () -> PerformanceReading?
    private let schedule: (@escaping @MainActor () -> Void) -> (() -> Void)
    private var previous: PerformanceReading?
    private var lease: PerformanceTimerLease?
    private var visible = false
    private var generation: UInt64 = 0

    public convenience init() {
        self.init(read: PerformanceReading.readCurrent, schedule: { callback in
            let timer = Timer(timeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { callback() } }
            timer.tolerance = 0.4
            RunLoop.main.add(timer, forMode: .common)
            return { timer.invalidate() }
        })
    }

    // Injectable kernel/clock/scheduler boundary for regression tests.
    init(read: @escaping () -> PerformanceReading?,
         schedule: @escaping (@escaping @MainActor () -> Void) -> (() -> Void)) {
        self.read = read; self.schedule = schedule
    }

    public func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value; generation &+= 1
        lease = nil; previous = nil; snapshot = nil
        guard value else { return }
        sample()
        let expected = generation
        lease = PerformanceTimerLease(schedule { [weak self] in
            guard let self, self.visible, self.generation == expected else { return }
            self.sample()
        })
    }

    private func sample() {
        let current = read()
        snapshot = current.map { PerformanceSnapshot(current: $0, previous: previous) }
        previous = current
    }
}
