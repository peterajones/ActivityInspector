import Testing
import Foundation
@testable import macOSmonitor

/// The CPU page graphs Performance and Efficiency cores separately, each with its kernel share.
struct PerCoreKernelTests {
    @Test func eachCoreReportsItsOwnKernelShare() async {
        let fake = FakeHostStats()
        fake.ticks = [CoreTicks(busy: 0, total: 0, system: 0), CoreTicks(busy: 0, total: 0, system: 0)]
        let sampler = SystemVitalsSampler(host: fake)
        let first = await sampler.sample()
        #expect(first.perCoreSystemPercent == [0, 0])     // no baseline yet

        fake.ticks = [CoreTicks(busy: 30, total: 100, system: 10), CoreTicks(busy: 70, total: 400, system: 50)]
        let sample = await sampler.sample()
        #expect(sample.perCoreSystemPercent == [10, 12.5])
    }

    @Test func aWrappedCoreReportsNoKernelTime() async {
        let fake = FakeHostStats()
        fake.ticks = [CoreTicks(busy: 0, total: 0, system: 500)]
        let sampler = SystemVitalsSampler(host: fake)
        _ = await sampler.sample()
        fake.ticks = [CoreTicks(busy: 40, total: 100, system: 20)]
        #expect(await sampler.sample().perCoreSystemPercent == [0])
    }
}

@MainActor
struct CoreClassHistoryTests {
    private func model(layout: CoreLayout?) -> (VitalsModel, FakeVitalsSampler) {
        let sampler = FakeVitalsSampler()
        let provider = FakeCoreLayout()
        provider.layout = layout
        return (VitalsModel(sampler: sampler, coreLayoutProvider: provider), sampler)
    }

    private func vitals(load: [Double], kernel: [Double]) -> SystemVitals {
        SystemVitals(cpuUsagePercent: 0, usedMemoryBytes: 0, totalMemoryBytes: 1, coreCount: load.count,
                     activeCoreCount: load.count, thermalState: "Nominal", lowPowerMode: false, uptime: 0,
                     osVersion: "macOS 27.2", perCoreUsagePercent: load, perCoreSystemPercent: kernel)
    }

    @Test func eachClassAveragesItsOwnCores() async {
        // E, E, P, P: the P cores are the last two, so a mix-up gives visibly different numbers.
        let (model, sampler) = model(layout: CoreLayout(kinds: [.efficiency, .efficiency, .performance, .performance]))
        sampler.next = vitals(load: [10, 30, 60, 80], kernel: [4, 6, 15, 25])
        await model.refreshOnce()

        #expect(model.coreClassHistory[.performance]?.load.values == [70])
        #expect(model.coreClassHistory[.performance]?.kernel.values == [20])
        #expect(model.coreClassHistory[.efficiency]?.load.values == [20])
        #expect(model.coreClassHistory[.efficiency]?.kernel.values == [5])
        #expect(model.coreClassHistory[.performance]?.load.capacity == model.history.cpu.capacity)
    }

    @Test func noClassesWithoutALayout() async {
        let (model, sampler) = model(layout: nil)
        sampler.next = vitals(load: [10, 30], kernel: [1, 2])
        await model.refreshOnce()
        #expect(model.coreClassHistory.isEmpty)
    }

    @Test func aSampleThatDoesntMatchTheLayoutIsSkipped() async {
        let (model, sampler) = model(layout: CoreLayout(kinds: [.efficiency, .performance]))
        sampler.next = vitals(load: [10, 30, 50], kernel: [1, 2, 3])
        await model.refreshOnce()
        #expect(model.coreClassHistory[.performance]?.load.values.isEmpty ?? true)
    }
}
