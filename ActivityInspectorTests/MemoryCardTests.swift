import Testing
@testable import ActivityInspector

/// The Summary's Memory card: its graph zooms to the last minute, at least 1 GB tall, and its
/// footer reads Available · Cached · Swap.
struct MemoryCardTests {
    private static let gib: Double = 1_073_741_824

    private func vitals(used: Double, total: Double = 36 * gib) -> SystemVitals {
        SystemVitals(cpuUsagePercent: 0, usedMemoryBytes: UInt64(used), totalMemoryBytes: UInt64(total),
                     coreCount: 1, activeCoreCount: 1, thermalState: "Nominal", lowPowerMode: false,
                     uptime: 0, osVersion: "macOS 27.2")
    }

    private func history(_ used: [Double]) -> VitalsHistory {
        var history = VitalsHistory()
        for bytes in used { history.append(vitals(used: bytes)) }
        return history
    }

    @Test func aSteadyMinuteStillGetsAtLeastAGigabyteBand() {
        // 20.3 GB with a 50 MB wobble: on the whole 36 GB scale it would be a flat line.
        let used = (0..<60).map { 20.3 * Self.gib + Double($0 % 2) * 50_000_000 }
        let range = MemoryCard.graphRange(history(used), totalBytes: UInt64(36 * Self.gib))
        #expect(range.upperBound - range.lowerBound >= Self.gib)
        #expect(range.upperBound - range.lowerBound < 2 * Self.gib)   // zoomed, not the whole 36 GB
        #expect(range.contains(used.min()!) && range.contains(used.max()!))
    }

    @Test func theBandFollowsOnlyTheLastMinute() {
        // A 30 GB peak two minutes ago, then a steady 12 GB minute: the old peak is off the graph.
        let used = Array(repeating: 30 * Self.gib, count: 60) + Array(repeating: 12 * Self.gib, count: 60)
        let range = MemoryCard.graphRange(history(used), totalBytes: UInt64(36 * Self.gib))
        #expect(range.contains(12 * Self.gib))
        #expect(range.upperBound < 14 * Self.gib)
    }

    @Test func aBigSwingFitsInTheBand() {
        let used = (0..<60).map { 8 * Self.gib + Double($0) * 0.1 * Self.gib }   // 8 → 13.9 GB
        let range = MemoryCard.graphRange(history(used), totalBytes: UInt64(36 * Self.gib))
        #expect(range.contains(used.first!) && range.contains(used.last!))
    }

    @Test func theFooterReadsAvailableCachedSwapInOrder() {
        var reading = vitals(used: 20 * Self.gib)
        reading.memoryReading = MemoryReading(used: UInt64(20 * Self.gib), total: UInt64(36 * Self.gib),
                                              cached: UInt64(3.5 * Self.gib))
        reading.swap = SwapUsage(used: UInt64(0.5 * Self.gib), total: UInt64(2 * Self.gib))
        #expect(MemoryCard.footer(reading) == ["Available 16.0 GB", "Cached 3.5 GB", "Swap 0.5 / 2.0 GB"])
    }

    @Test func theFooterShowsDashesBeforeTheFirstReading() {
        #expect(MemoryCard.footer(nil) == ["Available —", "Cached —", "Swap —"])
        #expect(MemoryCard.footer(vitals(used: 1)) == ["Available —", "Cached —", "Swap —"])
    }
}
