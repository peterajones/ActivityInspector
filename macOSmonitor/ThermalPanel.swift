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
            let groups = ThermalGroup.allCases.filter { model.thermalGroupHistory[$0] != nil }
            if !groups.isEmpty {
                Text("Sensor groups")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(groups, id: \.self) { group in
                        groupCard(group)
                    }
                }
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

    /// One sensor group: its name and temperature over a small, still graph of 5 minutes.
    private func groupCard(_ group: ThermalGroup) -> some View {
        let history = model.thermalGroupHistory[group] ?? MetricHistory()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.title).font(.callout).foregroundStyle(theme.primaryText)
                Spacer()
                Text(ThermalReading.text(model.thermal.flatMap { group.celsius(in: $0) }))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.color(for: .thermal))
            }
            MetricGraph(values: history.values,
                        capacity: history.capacity,
                        range: MetricScale.fixed(Self.scaleMax),
                        lineColor: theme.color(for: .thermal),
                        fillColor: theme.fillColor(for: .thermal),
                        gridColor: .clear,
                        timeAxis: CompressedTimeAxis(history: history, lastSample: nil, sampleInterval: 2))
                .environment(\.graphsAnimate, false)
                .frame(height: 50)
        }
        .dashboardCard(theme.color(for: .thermal))
    }
}
