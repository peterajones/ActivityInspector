import Testing
@testable import macOSmonitor

/// The sidebar lists Summary, Performance, Processes and Ports; Performance opens a column of
/// metrics. These rules map between the sidebar's items and the page that shows.
struct PerformanceNavigationTests {
    private let available: [Surface] = [.cpu, .gpu, .memory, .network, .disk, .thermal, .energy, .battery]

    @Test func everyMetricPageHighlightsPerformance() {
        for surface in available {
            #expect(surface.sidebarItem == .performance, "\(surface)")
        }
        #expect(Surface.summary.sidebarItem == .summary)
        #expect(Surface.processes.sidebarItem == .processes)
        #expect(Surface.ports.sidebarItem == .ports)
        #expect(Surface.systemInfo.sidebarItem == .systemInfo)
        #expect(Surface.startupApps.sidebarItem == .startupApps)
        #expect(Surface.services.sidebarItem == .services)
    }

    @Test func sidebarListsFourItemsInOrder() {
        #expect(SidebarItem.allCases == [.summary, .performance, .processes, .ports, .systemInfo, .installedApps, .startupApps, .services])
        #expect(SidebarItem.allCases.map(\.title) == ["Summary", "Performance", "Processes", "Ports", "System Info",
                                                      "Installed Apps", "Startup Apps", "Services"])
    }

    @Test func performanceReopensTheLastMetricViewed() {
        #expect(SidebarItem.performance.surface(lastMetric: .network, available: available) == .network)
    }

    @Test func performanceFallsBackToCPUWhenTheLastMetricIsGone() {
        // A GPU page remembered from before, on a Mac that no longer reports one.
        #expect(SidebarItem.performance.surface(lastMetric: .gpu, available: [.cpu, .memory]) == .cpu)
    }

    @Test func theOtherItemsOpenTheirOwnPages() {
        #expect(SidebarItem.summary.surface(lastMetric: .network, available: available) == .summary)
        #expect(SidebarItem.processes.surface(lastMetric: .network, available: available) == .processes)
        #expect(SidebarItem.ports.surface(lastMetric: .network, available: available) == .ports)
        #expect(SidebarItem.systemInfo.surface(lastMetric: .network, available: available) == .systemInfo)
        #expect(SidebarItem.startupApps.surface(lastMetric: .network, available: available) == .startupApps)
        #expect(SidebarItem.services.surface(lastMetric: .network, available: available) == .services)
    }
}

/// Each row in the Performance column: a detail line and the value, from the same readings as
/// the pages.
struct PerformanceRowTests {
    private func vitals(battery: BatteryInfo? = nil) -> SystemVitals {
        SystemVitals(cpuUsagePercent: 20.4, usedMemoryBytes: 13 * 1_073_741_824, totalMemoryBytes: 18 * 1_073_741_824,
                     coreCount: 12, activeCoreCount: 12, thermalState: "Nominal", lowPowerMode: false,
                     uptime: 0, osVersion: "macOS 27.2",
                     networkInBytesPerSec: 7_000, networkOutBytesPerSec: 1_000, battery: battery,
                     diskReadBytesPerSec: 50_000, diskWriteBytesPerSec: 0,
                     gpu: GPUInfo(utilizationPercent: 9.6, memoryInUseBytes: nil, name: "Apple M3 Pro", coreCount: 18))
    }

    private func row(_ surface: Surface, battery: BatteryInfo? = nil, celsius: Double? = 49.4,
                     watts: Double? = 18.06) -> PerformanceRow {
        PerformanceRow(surface, vitals: vitals(battery: battery),
                       thermal: ThermalReading(cpuDieMax: celsius, cpuDieAverage: nil, boardMax: nil, ssd: nil, battery: nil),
                       power: PowerReading(systemWatts: watts, adapterWatts: nil, batteryWatts: nil, gpuWatts: nil))
    }

    @Test func cpu() {
        #expect(row(.cpu).detail == "12 logical processors")
        #expect(row(.cpu).value == "20%")
    }

    @Test func gpuNamesTheChipAndItsCores() {
        #expect(row(.gpu).detail == "Apple M3 Pro · 18 cores")
        #expect(row(.gpu).value == "10%")
    }

    @Test func memoryShowsUsedOfTotalAndTheShare() {
        #expect(row(.memory).detail == "13.0 / 18 GB")
        #expect(row(.memory).value == "72.2%")
    }

    @Test func networkAndDiskShowTheirSplit() {
        #expect(row(.network).value == "↓ 7 KB/s  ↑ 1 KB/s")
        #expect(row(.disk).value == "R 50 KB/s  W 0 B/s")
    }

    @Test func thermalShowsPressureAndTemperature() {
        #expect(row(.thermal).detail == "Nominal pressure")
        #expect(row(.thermal).value == "49 °C")
    }

    @Test func energySaysWhereThePowerComesFrom() {
        let onPower = BatteryInfo(chargePercent: 80, state: .charging, timeRemainingMinutes: nil)
        let onBattery = BatteryInfo(chargePercent: 80, state: .discharging, timeRemainingMinutes: nil)
        #expect(row(.energy, battery: onPower).detail == "On power")
        #expect(row(.energy, battery: onBattery).detail == "On battery")
        #expect(row(.energy).detail == "On power")              // a desktop has no battery
        #expect(row(.energy).value == "18.1 W")
    }

    @Test func batteryShowsChargeAndState() {
        let battery = BatteryInfo(chargePercent: 52, state: .discharging, timeRemainingMinutes: 90)
        #expect(row(.battery, battery: battery).value == "52%")
        #expect(row(.battery, battery: battery).detail == "1:30 remaining")
    }

    @Test func missingReadingsShowADash() {
        let empty = PerformanceRow(.thermal, vitals: nil, thermal: nil, power: nil)
        #expect(empty.value == "—")
    }
}
