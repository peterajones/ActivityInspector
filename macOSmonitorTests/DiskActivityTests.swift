import Testing
import Foundation
@testable import macOSmonitor

/// The Disk page's active time, response time, totals and capacity, from the block storage
/// driver's public statistics and the startup volume.
struct DiskActivityTests {
    private func sampler(_ disk: FakeDiskStats, clock: FakeClock) -> SystemVitalsSampler {
        SystemVitalsSampler(host: FakeHostStats(), disk: disk, now: { clock.now })
    }

    @Test func activeTimeIsTheShareOfTheIntervalSpentOnRequests() async {
        let disk = FakeDiskStats()
        let clock = FakeClock()
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 1_000_000_000, operations: 100)
        let sampler = sampler(disk, clock: clock)
        let first = await sampler.sample()
        #expect(first.diskActivePercent == 0)              // no baseline yet

        clock.now = 2_000_000_000                          // 2 s later
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 1_500_000_000, operations: 300)
        let sample = await sampler.sample()
        #expect(sample.diskActivePercent == 25)            // 0.5 s busy of 2 s
        #expect(sample.diskResponseMillis == 2.5)          // 0.5 s over 200 operations
    }

    @Test func overlappingRequestsCapAtFullyActive() async {
        // Two disks, or several queued requests, can add up to more time than passed.
        let disk = FakeDiskStats()
        let clock = FakeClock()
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 0, operations: 0)
        let sampler = sampler(disk, clock: clock)
        _ = await sampler.sample()
        clock.now = 1_000_000_000
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 3_000_000_000, operations: 10)
        #expect(await sampler.sample().diskActivePercent == 100)
    }

    @Test func noOperationsMeansNoResponseTime() async {
        let disk = FakeDiskStats()
        let clock = FakeClock()
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 0, operations: 50)
        let sampler = sampler(disk, clock: clock)
        _ = await sampler.sample()
        clock.now = 1_000_000_000
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 0, operations: 50)
        let sample = await sampler.sample()
        #expect(sample.diskResponseMillis == nil)
        #expect(sample.diskActivePercent == 0)
    }

    @Test func countersGoingBackwardsCountAsIdle() async {
        let disk = FakeDiskStats()
        let clock = FakeClock()
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 9_000_000_000, operations: 900)
        let sampler = sampler(disk, clock: clock)
        _ = await sampler.sample()
        clock.now = 1_000_000_000
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 1_000, operations: 1)   // a disk went away
        let sample = await sampler.sample()
        #expect(sample.diskActivePercent == 0)
        #expect(sample.diskResponseMillis == nil)
    }

    @Test func anOperationsCounterGoingBackwardsAloneDoesntTrap() async {
        // Busy time rises while the operation count drops (one disk reset): unsigned
        // subtraction would trap, so the interval counts as idle.
        let disk = FakeDiskStats()
        let clock = FakeClock()
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 0, operations: 900)
        let sampler = sampler(disk, clock: clock)
        _ = await sampler.sample()
        clock.now = 1_000_000_000
        disk.next = DiskCounters(read: 0, written: 0, busyNanos: 500_000_000, operations: 5)
        let sample = await sampler.sample()
        #expect(sample.diskActivePercent == 0)
        #expect(sample.diskResponseMillis == nil)
    }

    @Test func totalsSinceBootAndCapacityPassThrough() async {
        let disk = FakeDiskStats()
        disk.next = DiskCounters(read: 1_700_000_000_000, written: 382_000_000_000, busyNanos: 0, operations: 0)
        disk.volume = VolumeCapacity(total: 1_000_000_000_000, available: 400_000_000_000)
        let sample = await sampler(disk, clock: FakeClock()).sample()
        #expect(sample.diskTotalReadBytes == 1_700_000_000_000)
        #expect(sample.diskTotalWrittenBytes == 382_000_000_000)
        #expect(sample.startupVolume == VolumeCapacity(total: 1_000_000_000_000, available: 400_000_000_000))
    }

    @Test func historyRecordsActiveTime() {
        var history = VitalsHistory()
        var vitals = SystemVitals(cpuUsagePercent: 0, usedMemoryBytes: 0, totalMemoryBytes: 1, coreCount: 1,
                                  activeCoreCount: 1, thermalState: "Nominal", lowPowerMode: false,
                                  uptime: 0, osVersion: "macOS 27.2")
        vitals.diskActivePercent = 12.5
        history.append(vitals)
        #expect(history.diskActive.values == [12.5])
    }

    @Test func capacityText() {
        let volume = VolumeCapacity(total: 994_662_584_320, available: 412_000_000_000)
        #expect(volume.totalText == "994.7 GB")
        #expect(volume.availableText == "412.0 GB")
    }

    @Test func pageFiguresInReadingOrder() {
        var vitals = SystemVitals(cpuUsagePercent: 0, usedMemoryBytes: 0, totalMemoryBytes: 1, coreCount: 1,
                                  activeCoreCount: 1, thermalState: "Nominal", lowPowerMode: false,
                                  uptime: 0, osVersion: "macOS 27.2")
        vitals.diskActivePercent = 4.8
        vitals.diskResponseMillis = 0.24
        vitals.diskTotalReadBytes = 1_700_000_000_000
        let figures = DiskPanel.figures(vitals)
        #expect(figures.map(\.label) == ["Read", "Write", "Active time", "Response time",
                                         "Read since boot", "Written since boot"])
        let value = Dictionary(uniqueKeysWithValues: figures.map { ($0.label, $0.value) })
        #expect(value["Active time"] == "5%")
        #expect(value["Response time"] == "0.2 ms")
        #expect(value["Read since boot"] == "1.7 TB")

        vitals.startupVolume = VolumeCapacity(total: 994_662_584_320, available: 412_000_000_000)
        #expect(DiskPanel.figures(vitals).suffix(2).map(\.label) == ["Startup disk", "Available"])
    }
}
