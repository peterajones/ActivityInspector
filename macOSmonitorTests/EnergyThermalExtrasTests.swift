import Testing
import Foundation
@testable import macOSmonitor

/// The Energy page's tiles: power figures where this Mac reports them, then where the power
/// comes from.
struct EnergyTilesTests {
    private func vitals(battery: BatteryInfo?, lowPower: Bool = false) -> SystemVitals {
        SystemVitals(cpuUsagePercent: 0, usedMemoryBytes: 0, totalMemoryBytes: 1, coreCount: 1,
                     activeCoreCount: 1, thermalState: "Nominal", lowPowerMode: lowPower, uptime: 0,
                     osVersion: "macOS 27.2", battery: battery)
    }

    @Test func laptopOnBatteryShowsEveryTileWithAnIcon() {
        let power = PowerReading(systemWatts: 17.8, adapterWatts: 0, batteryWatts: 17.9, gpuWatts: 0.4)
        let battery = BatteryInfo(chargePercent: 85, state: .discharging, timeRemainingMinutes: 160)
        let tiles = EnergyPanel.tiles(power: power, vitals: vitals(battery: battery, lowPower: true))
        #expect(tiles.map(\.label) == ["System total", "From power adapter", "Battery, in or out", "GPU",
                                       "Power source", "Low Power Mode", "Battery"])
        #expect(tiles.map(\.value) == ["17.8 W", "0.0 W", "17.9 W", "0.4 W", "Battery", "On", "85%"])
        #expect(tiles.allSatisfy { $0.systemImage != nil })
    }

    @Test func desktopHasNoBatteryTilesAndSaysPowerAdapter() {
        let power = PowerReading(systemWatts: 30, adapterWatts: 31, batteryWatts: nil, gpuWatts: nil)
        let tiles = EnergyPanel.tiles(power: power, vitals: vitals(battery: nil))
        #expect(tiles.map(\.label) == ["System total", "From power adapter", "Power source", "Low Power Mode"])
        #expect(tiles.first { $0.label == "Power source" }?.value == "Power adapter")
        #expect(tiles.first { $0.label == "Low Power Mode" }?.value == "Off")
    }

    @Test func aChargingLaptopIsOnThePowerAdapter() {
        let battery = BatteryInfo(chargePercent: 60, state: .charging, timeRemainingMinutes: nil)
        let tiles = EnergyPanel.tiles(power: nil, vitals: vitals(battery: battery))
        #expect(tiles.first { $0.label == "Power source" }?.value == "Power adapter")
    }
}

/// The Thermal page's sensor groups, each with five minutes of history.
@MainActor
struct ThermalGroupHistoryTests {
    @Test func eachReadableGroupRecordsItsTemperature() async {
        let thermal = FakeThermalSampler()
        let model = VitalsModel(sampler: FakeVitalsSampler(), thermalSampler: thermal)
        thermal.next = ThermalReading(cpuDieMax: 50, cpuDieAverage: 44, boardMax: nil, ssd: 38, battery: 31)
        await model.refreshThermalOnce()
        thermal.next = ThermalReading(cpuDieMax: 51, cpuDieAverage: 45, boardMax: nil, ssd: 39, battery: 31)
        await model.refreshThermalOnce()

        #expect(model.thermalGroupHistory[.cpuDieAverage]?.values == [44, 45])
        #expect(model.thermalGroupHistory[.ssd]?.values == [38, 39])
        #expect(model.thermalGroupHistory[.battery]?.values == [31, 31])
        #expect(model.thermalGroupHistory[.board] == nil)         // never readable: no card
        #expect(model.thermalGroupHistory[.ssd]?.capacity == VitalsModel.thermalHistoryCapacity)
    }

    @Test func groupsListInPageOrderWithTitles() {
        #expect(ThermalGroup.allCases.map(\.title) == ["CPU die, average", "Board, hottest", "SSD", "Battery"])
        let reading = ThermalReading(cpuDieMax: 50, cpuDieAverage: 44, boardMax: 40, ssd: 38, battery: 31)
        #expect(ThermalGroup.allCases.map { $0.celsius(in: reading) } == [44, 40, 38, 31])
    }
}
