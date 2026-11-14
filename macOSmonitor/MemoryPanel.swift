import SwiftUI

/// The Memory Performance page: use over the last five minutes, and the breakdown behind it.
struct MemoryPanel: View {
    let model: VitalsModel
    @Environment(\.theme) private var theme

    var body: some View {
        PanelPage(.memory, model: model) {
            GraphSection(label: "Memory used · last 5 min") {
                MetricGraph(values: model.history.memoryUsedLong.values,
                            capacity: VitalsHistory.longMemoryCapacity,
                            range: graphRange,
                            lineColor: theme.color(for: .memory),
                            fillColor: theme.fillColor(for: .memory),
                            gridColor: theme.gridLine,
                            timeAxis: CompressedTimeAxis(samplesSeen: model.history.memoryUsedLong.totalAppended,
                                                         gridInterval: 30,
                                                         lastSample: model.lastSampleDate,
                                                         sampleInterval: 1))
                    .overlay(alignment: .topLeading) { rangeLabel(graphRange.upperBound) }
                    .overlay(alignment: .bottomLeading) { rangeLabel(graphRange.lowerBound) }
            }
            FigureGrid(figures: [
                Figure(label: "In use", value: model.vitals?.usedMemoryText ?? "—"),
                Figure(label: "Available", value: model.vitals?.availableMemoryText ?? "—"),
                Figure(label: "Cached", value: model.vitals?.cachedMemoryText ?? "—"),
                Figure(label: "Pressure", value: model.vitals?.memoryPressureText ?? "—"),
                Figure(label: "App memory", value: model.vitals?.appMemoryText ?? "—"),
                Figure(label: "Wired", value: model.vitals?.wiredMemoryText ?? "—"),
                Figure(label: "Compressed", value: model.vitals?.compressedMemoryText ?? "—"),
                Figure(label: "Swap", value: model.vitals?.swapText ?? "—"),
                Figure(label: "Page ins", value: model.vitals?.pageInsText ?? "—"),
                Figure(label: "Page outs", value: model.vitals?.pageOutsText ?? "—"),
            ])
        }
    }

    /// Zoomed to the recent window so ordinary movement is visible; a 1 GB minimum span
    /// keeps an idle machine's trace flat.
    private var graphRange: ClosedRange<Double> {
        MetricScale.zoomed(model.history.memoryUsedLong.values,
                           ceiling: Double(model.vitals?.totalMemoryBytes ?? 1),
                           minimumSpan: 1_073_741_824)
    }

    private func rangeLabel(_ bytes: Double) -> some View {
        Text(SystemVitals.gigabytes(bytes))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(theme.color(for: .memory))
            .padding(6)
    }
}
