import Testing
@testable import BridgePlatform

@Suite @MainActor struct PerformanceMonitorTests {
    private func reading(_ time: Double, _ cpu: Double, ticks: [UInt32] = [100, 20, 80, 0]) -> PerformanceReading {
        PerformanceReading(uptime: time, processCPUSeconds: cpu, cpuTicks: ticks,
            physicalMemory: 16_000, activeMemory: 3_000, wiredMemory: 2_000,
            compressedMemory: 1_000, processFootprint: 400)
    }

    @Test func samplingExistsOnlyWhileVisibleAndNeverIncludesHiddenTime() {
        var reads = 0, starts = 0, cancels = 0
        var next = reading(10, 1)
        var fire: (@MainActor () -> Void)?
        let monitor = PerformanceMonitor(read: { reads += 1; return next }, schedule: { callback in
            starts += 1; fire = callback
            return { cancels += 1; fire = nil }
        })
        #expect(reads == 0 && starts == 0)
        monitor.setVisible(true)
        monitor.setVisible(true)
        #expect(reads == 1 && starts == 1 && monitor.isSampling)
        #expect(monitor.snapshot?.processCPUPercent == nil)
        next = reading(12, 1.4, ticks: [120, 30, 150, 0]); fire?()
        #expect(abs((monitor.snapshot?.processCPUPercent ?? -1) - 20) < 0.001)
        #expect(abs((monitor.snapshot?.systemCPUPercent ?? -1) - 30) < 0.001)
        let stale = fire
        monitor.setVisible(false)
        next = reading(100, 50); stale?()
        #expect(reads == 2 && cancels == 1 && !monitor.isSampling)
        #expect(monitor.snapshot == nil)
        monitor.setVisible(true)
        #expect(reads == 3 && monitor.snapshot?.processCPUPercent == nil)
        monitor.setVisible(false)
        #expect(starts == 2 && cancels == 2)
    }

    @Test func memoryUsesActiveWiredAndPhysicalCompressorWithoutCountingCacheTwice() {
        let result = PerformanceSnapshot(current: reading(1, 0), previous: nil)
        #expect(result.systemUsedMemory == 6_000)
        #expect(result.physicalMemory == 16_000)
        #expect(result.processFootprint == 400)
    }

    @Test func cpuHandlesTickWrapAndFailedReadsAndAppMayUseMultipleCores() {
        let before = reading(10, 1, ticks: [UInt32.max - 4, 20, 100, 0])
        let after = reading(12, 5, ticks: [5, 30, 180, 0])
        let result = PerformanceSnapshot(current: after, previous: before)
        #expect(result.processCPUPercent == 200)
        #expect(abs((result.systemCPUPercent ?? -1) - 20) < 0.001)
        var value: PerformanceReading? = before
        var fire: (@MainActor () -> Void)?
        let monitor = PerformanceMonitor(read: { value }, schedule: { callback in fire = callback; return {} })
        monitor.setVisible(true)
        value = nil; fire?()
        #expect(monitor.snapshot == nil)
        value = after; fire?()
        #expect(monitor.snapshot?.processCPUPercent == nil)
        monitor.setVisible(false)
    }

    @Test func staleCallbackFromPriorVisibilityCannotSampleNewSession() {
        var reads = 0
        var fire: (@MainActor () -> Void)?
        let monitor = PerformanceMonitor(read: { reads += 1; return self.reading(Double(reads), 0) },
            schedule: { callback in fire = callback; return {} })
        monitor.setVisible(true)
        let old = fire
        monitor.setVisible(false); monitor.setVisible(true)
        old?()
        #expect(reads == 2)
        fire?()
        #expect(reads == 3)
        monitor.setVisible(false)
    }

    @Test func destroyingMonitorCancelsTimerWithoutAnExplicitDisappear() {
        var cancelled = 0
        var monitor: PerformanceMonitor? = PerformanceMonitor(read: { self.reading(1, 0) },
            schedule: { _ in { cancelled += 1 } })
        weak var owner = monitor
        monitor?.setVisible(true)
        monitor = nil
        #expect(owner == nil && cancelled == 1)
    }

    @Test func realAdapterReturnsBoundedKernelMetadataOnly() {
        let value = PerformanceReading.readCurrent()
        #expect(value != nil)
        #expect(value?.cpuTicks?.count == 4)
        #expect((value?.physicalMemory ?? 0) > 0)
        #expect((value?.processFootprint ?? 0) > 0)
    }

    @Test func everyHiddenWindowStateStopsSampling() {
        let visible = PerformanceVisibility(pageMounted: true, windowVisible: true, windowOccluded: false,
            windowMiniaturized: false, applicationHidden: false, sessionAwake: true)
        #expect(visible.allowsSampling)
        for key in 0..<6 {
            var state = visible
            switch key {
            case 0: state.pageMounted = false
            case 1: state.windowVisible = false
            case 2: state.windowOccluded = true
            case 3: state.windowMiniaturized = true
            case 4: state.applicationHidden = true
            default: state.sessionAwake = false
            }
            #expect(!state.allowsSampling)
        }
    }
}
