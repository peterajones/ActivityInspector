import SwiftUI

/// The Energy page's figures (the shared `Figure`).
typealias EnergyFact = Figure

/// The Energy Performance panel: whole-system power over the last 60 seconds, where it
/// comes from (adapter, battery), the GPU's share, and the processes drawing the most.
struct EnergyPanel: View {
    let model: VitalsModel
    /// The window's process list, for the top processes by power.
    let processes: ProcessListModel
    @Environment(\.theme) private var theme

    /// The graph's and meter's scale: at least 10 W so an idle Mac doesn't fill the graph,
    /// otherwise the last minute's peak. nonisolated: called from tests off the main actor.
    nonisolated static func range(_ history: MetricHistory) -> ClosedRange<Double> {
        MetricScale.autoscaled([history], floor: 10)
    }

    /// The panel's figures: System total always, the rest only where this Mac reports them
    /// (no Battery row on a desktop, no GPU row without the counter). Adapter power on battery
    /// is a real 0, so it stays.
    nonisolated static func facts(_ power: PowerReading?) -> [EnergyFact] {
        var facts = [EnergyFact(label: "System total", value: PowerReading.text(power?.systemWatts))]
        let optional: [(String, Double?)] = [("From power adapter", power?.adapterWatts),
                                              ("Battery, in or out", power?.batteryWatts),
                                              ("GPU", power?.gpuWatts)]
        for (label, watts) in optional where watts != nil {
            facts.append(EnergyFact(label: label, value: PowerReading.text(watts)))
        }
        return facts
    }

    /// The page's tiles: the power figures (as `facts`), then where the power comes from, Low
    /// Power Mode and, on a laptop, the battery's charge.
    nonisolated static func tiles(power: PowerReading?, vitals: SystemVitals?) -> [Figure] {
        let icons = ["System total": "bolt.fill", "From power adapter": "powerplug",
                     "Battery, in or out": "battery.50percent", "GPU": "display"]
        var tiles = facts(power).map { Figure(label: $0.label, value: $0.value, systemImage: icons[$0.label] ?? "bolt") }
        guard let vitals else { return tiles }
        let onBattery = vitals.battery?.state == .discharging
        tiles.append(Figure(label: "Power source", value: onBattery ? "Battery" : "Power adapter",
                            systemImage: onBattery ? "battery.75percent" : "powerplug.fill"))
        tiles.append(Figure(label: "Low Power Mode", value: vitals.lowPowerMode ? "On" : "Off", systemImage: "leaf"))
        if let battery = vitals.battery {
            tiles.append(Figure(label: "Battery", value: "\(battery.chargePercent)%", systemImage: "battery.100percent"))
        }
        return tiles
    }

    nonisolated static func meterFraction(_ watts: Double?, history: MetricHistory) -> Double {
        min(max((watts ?? 0) / range(history).upperBound, 0), 1)
    }

    var body: some View {
        PanelPage(.energy, model: model) {
            GraphSection(label: "System power · last 60 s",
                         note: "scale 0–\(Int(Self.range(model.powerHistory).upperBound.rounded(.up))) W") {
                MetricGraph(values: model.powerHistory.values,
                            capacity: model.powerHistory.capacity,
                            range: Self.range(model.powerHistory),
                            lineColor: theme.color(for: .energy),
                            fillColor: theme.fillColor(for: .energy),
                            gridColor: theme.gridLine,
                            timeAxis: CompressedTimeAxis(history: model.powerHistory, lastSample: model.lastSampleDate))
            }
            FigureGrid(figures: Self.tiles(power: model.power, vitals: model.vitals),
                       tint: theme.color(for: .energy))

            Text("Top processes by power")
                .font(.headline)
                .foregroundStyle(theme.primaryText)
                .padding(.top, 4)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                ForEach(ProcessInfoRow.topByPower(processes.rows, limit: 8)) { row in
                    GridRow {
                        Text(row.name).lineLimit(1).foregroundStyle(theme.primaryText)
                        Text(PowerReading.text(row.powerWatts))
                            .monospacedDigit()
                            .foregroundStyle(theme.color(for: .energy))
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            Text("System, adapter and battery power come from the SMC; GPU power from its energy counter. macOS 27 no longer updates the CPU, Neural Engine and memory energy counters, so they aren’t shown. Per-process power is the kernel’s estimate for each process; processes that aren’t yours need the privileged helper.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }
}
