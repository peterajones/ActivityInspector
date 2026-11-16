import Testing
import Foundation
@testable import ActivityInspector

/// Network totals since boot, and the GPU page's memory history.
struct NetworkTotalsTests {
    @Test func totalsSinceBootSumEveryInterface() async {
        let network = FakeNetworkStats()
        network.interfaces = [InterfaceCounters(name: "en0", received: 6_000_000_000, sent: 1_000_000_000),
                              InterfaceCounters(name: "en5", received: 100_000_000, sent: 700_000_000)]
        let sample = await SystemVitalsSampler(host: FakeHostStats(), network: network).sample()
        #expect(sample.networkTotalReceivedBytes == 6_100_000_000)
        #expect(sample.networkTotalSentBytes == 1_700_000_000)
    }

    @Test func noCountersMeansNoTotals() async {
        let network = FakeNetworkStats()
        network.interfaces = nil
        let sample = await SystemVitalsSampler(host: FakeHostStats(), network: network).sample()
        #expect(sample.networkTotalReceivedBytes == 0)
    }

    @Test func pageFiguresInReadingOrder() {
        var vitals = SystemVitals(cpuUsagePercent: 0, usedMemoryBytes: 0, totalMemoryBytes: 1, coreCount: 1,
                                  activeCoreCount: 1, thermalState: "Nominal", lowPowerMode: false,
                                  uptime: 0, osVersion: "macOS 27.2",
                                  networkInBytesPerSec: 9_900, networkOutBytesPerSec: 5_900)
        vitals.networkTotalReceivedBytes = 6_100_000_000
        vitals.networkTotalSentBytes = 1_700_000_000
        let figures = NetworkPanel.figures(vitals)
        #expect(figures.map(\.label) == ["Received", "Sent", "Received since boot", "Sent since boot"])
        #expect(figures.map(\.value) == ["10 KB/s", "6 KB/s", "6.1 GB", "1.7 GB"])
    }
}

struct GPUMemoryHistoryTests {
    private func vitals(gpuMemory: UInt64?) -> SystemVitals {
        SystemVitals(cpuUsagePercent: 0, usedMemoryBytes: 0, totalMemoryBytes: 1, coreCount: 1,
                     activeCoreCount: 1, thermalState: "Nominal", lowPowerMode: false, uptime: 0,
                     osVersion: "macOS 27.2",
                     gpu: GPUInfo(utilizationPercent: 5, memoryInUseBytes: gpuMemory))
    }

    @Test func historyRecordsGPUMemoryInUse() {
        var history = VitalsHistory()
        history.append(vitals(gpuMemory: 916_000_000))
        history.append(vitals(gpuMemory: nil))             // unreadable: no fake drop to 0
        history.append(vitals(gpuMemory: 920_000_000))
        #expect(history.gpuMemory.values == [916_000_000, 920_000_000])
    }
}
