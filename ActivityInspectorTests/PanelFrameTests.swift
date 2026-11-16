import Testing
@testable import ActivityInspector

/// Every Performance page opens with the same header: a wide meter, filled by the same rule the
/// rest of the app uses for that metric.
struct PerformanceMeterTests {
    private func vitals(battery: BatteryInfo? = nil) -> SystemVitals {
        SystemVitals(cpuUsagePercent: 20, usedMemoryBytes: 9, totalMemoryBytes: 12, coreCount: 12,
                     activeCoreCount: 12, thermalState: "Nominal", lowPowerMode: false, uptime: 0,
                     osVersion: "macOS 27.2", networkInBytesPerSec: 8, networkOutBytesPerSec: 2,
                     battery: battery, diskReadBytesPerSec: 50, diskWriteBytesPerSec: 50,
                     gpu: GPUInfo(utilizationPercent: 40, memoryInUseBytes: nil))
    }

    private func history(_ pairs: [(Double, Double)], network: Bool) -> VitalsHistory {
        var history = VitalsHistory()
        for (a, b) in pairs {
            var v = vitals()
            if network { v.networkInBytesPerSec = a; v.networkOutBytesPerSec = b }
            else { v.diskReadBytesPerSec = a; v.diskWriteBytesPerSec = b }
            history.append(v)
        }
        return history
    }

    private func fraction(_ surface: Surface, vitals: SystemVitals? = nil, history: VitalsHistory = VitalsHistory(),
                          celsius: Double? = 55, watts: Double? = 20, powerHistory: MetricHistory = MetricHistory()) -> Double {
        PerformanceMeter.fraction(surface, vitals: vitals ?? self.vitals(),
                                  thermal: ThermalReading(cpuDieMax: celsius, cpuDieAverage: nil, boardMax: nil, ssd: nil, battery: nil),
                                  power: PowerReading(systemWatts: watts, adapterWatts: nil, batteryWatts: nil, gpuWatts: nil),
                                  history: history, powerHistory: powerHistory)
    }

    @Test func percentagesFillByTheirShare() {
        #expect(fraction(.cpu) == 0.2)
        #expect(fraction(.gpu) == 0.4)
        #expect(fraction(.memory) == 0.75)
    }

    @Test func networkAndDiskMatchTheSummaryTiles() {
        // The same busiest-second rule as the Summary tiles: 10 of a 40 peak.
        let net = history([(30, 10), (8, 2)], network: true)
        #expect(fraction(.network, history: net) == 0.25)
        let disk = history([(300, 100), (50, 50)], network: false)
        #expect(fraction(.disk, history: disk) == 0.25)
    }

    @Test func temperatureAndPowerUseTheirPanelsScales() {
        #expect(fraction(.thermal, celsius: 55) == ThermalPanel.meterFraction(55))
        var power = MetricHistory(capacity: 60)
        [10.0, 40, 20].forEach { power.append($0) }
        #expect(fraction(.energy, watts: 20, powerHistory: power) == EnergyPanel.meterFraction(20, history: power))
    }

    @Test func batteryIsItsCharge() {
        let battery = BatteryInfo(chargePercent: 52, state: .discharging, timeRemainingMinutes: nil)
        #expect(fraction(.battery, vitals: vitals(battery: battery)) == 0.52)
    }

    @Test func networkAndDiskHeadersShowTheTotalOthersTheColumnsValue() {
        let v = vitals()
        let row = { (surface: Surface) in PerformanceRow(surface, vitals: v, thermal: nil, power: nil) }
        #expect(PerformanceMeter.headerValue(.network, row: row(.network), vitals: v) == "10 B/s")
        #expect(PerformanceMeter.headerValue(.disk, row: row(.disk), vitals: v) == "100 B/s")
        #expect(PerformanceMeter.headerValue(.cpu, row: row(.cpu), vitals: v) == "20%")
        #expect(PerformanceMeter.headerValue(.network, row: PerformanceRow(.network, vitals: nil, thermal: nil, power: nil),
                                             vitals: nil) == "—")
    }

    @Test func noReadingMeansAnEmptyMeter() {
        #expect(PerformanceMeter.fraction(.cpu, vitals: nil, thermal: nil, power: nil,
                                          history: VitalsHistory(), powerHistory: MetricHistory()) == 0)
    }
}

/// The CPU page's figures, in reading order, each only where this Mac reports it.
struct CPUFiguresTests {
    private func vitals() -> SystemVitals {
        var vitals = SystemVitals(cpuUsagePercent: 25, usedMemoryBytes: 0, totalMemoryBytes: 1, coreCount: 4,
                                  activeCoreCount: 4, thermalState: "Nominal", lowPowerMode: false,
                                  uptime: 90_000, osVersion: "macOS 27.2",
                                  perCoreUsagePercent: [10, 30, 60, 80],
                                  coreFrequencies: ["P1": CoreFrequency(activeFraction: 1, averageMHz: 3_000),
                                                    "P2": CoreFrequency(activeFraction: 1, averageMHz: 3_000),
                                                    "E1": CoreFrequency(activeFraction: 1, averageMHz: 1_000),
                                                    "E2": CoreFrequency(activeFraction: 1, averageMHz: 1_000)])
        vitals.cpuSystemPercent = 7.4
        return vitals
    }

    @Test func everyFigureWhenTheLayoutAndClocksAreKnown() {
        let layout = CoreLayout(kinds: [.efficiency, .efficiency, .performance, .performance])
        let figures = CPUPanel.figures(vitals(), layout: layout)
        #expect(figures.map(\.label) == ["Utilisation", "Kernel", "Cores", "P cores", "E cores",
                                         "P clock", "E clock", "Active", "Up time"])
        let value = Dictionary(uniqueKeysWithValues: figures.map { ($0.label, $0.value) })
        #expect(value["Kernel"] == "7%")
        #expect(value["P cores"] == "70%")                 // (60 + 80) / 2: the P cores are the last two
        #expect(value["E cores"] == "20%")
        #expect(value["Cores"] == "4 (2P + 2E)")
        #expect(value["Up time"] == "1d 1h")
    }

    @Test func noCoreKindsOrClocksWithoutALayout() {
        var vitals = vitals()
        vitals.coreFrequencies = [:]
        let figures = CPUPanel.figures(vitals, layout: nil)
        #expect(figures.map(\.label) == ["Utilisation", "Kernel", "Cores", "Active", "Up time"])
        #expect(figures.first { $0.label == "Cores" }?.value == "4")
    }
}
