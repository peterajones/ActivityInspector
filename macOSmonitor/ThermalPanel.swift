import SwiftUI

/// The Thermal Performance page: the hottest CPU die sensor over five minutes, then each
/// sensor group and macOS's own thermal state.
struct ThermalPanel: View {
    let model: VitalsModel
    @Environment(\.theme) private var theme

    /// Meters and the graph share a 0–100 °C scale: Apple silicon throttles in the high 90s.
    nonisolated static let scaleMax = 100.0

    /// nonisolated: pure maths, called from tests off the main actor (see SystemVitalsView).
    nonisolated static func meterFraction(_ celsius: Double?) -> Double {
        min(max((celsius ?? 0) / scaleMax, 0), 1)
    }

    var body: some View {
        PanelPage(.thermal, model: model) {
            GraphSection(label: "Hottest CPU die sensor · last 5 min", note: "scale 0–100 °C") {
                MetricGraph(values: model.thermalHistory.values,
                            capacity: model.thermalHistory.capacity,
                            range: MetricScale.fixed(Self.scaleMax),
                            lineColor: theme.color(for: .thermal),
                            fillColor: theme.fillColor(for: .thermal),
                            gridColor: theme.gridLine,
                            timeAxis: CompressedTimeAxis(history: model.thermalHistory, lastSample: model.lastThermalSampleDate,
                                                         sampleInterval: 2, gridInterval: 15))
            }
            FigureGrid(figures: [
                Figure(label: "Thermal pressure", value: model.vitals?.thermalState ?? "—"),
                Figure(label: "CPU die, hottest", value: ThermalReading.text(model.thermal?.cpuDieMax)),
                Figure(label: "CPU die, average", value: ThermalReading.text(model.thermal?.cpuDieAverage)),
                Figure(label: "Board, hottest", value: ThermalReading.text(model.thermal?.boardMax)),
                Figure(label: "SSD", value: ThermalReading.text(model.thermal?.ssd)),
                Figure(label: "Battery", value: ThermalReading.text(model.thermal?.battery)),
            ])
            Text("Read from the SMC's sensors every 2 s. Apple doesn’t document which die sensor sits over which core, so CPU readings are summarised rather than shown per core.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }
}
