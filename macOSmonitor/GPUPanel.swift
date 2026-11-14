import SwiftUI

/// The GPU Performance page: utilisation over the last minute, then the chip and its memory.
struct GPUPanel: View {
    let model: VitalsModel
    @Environment(\.theme) private var theme

    var body: some View {
        PanelPage(.gpu, model: model) {
            GraphSection(label: "Utilisation · last 60 s") {
                MetricGraph(values: model.history.gpu.values,
                            range: MetricScale.fixed(100),
                            lineColor: theme.color(for: .gpu),
                            fillColor: theme.fillColor(for: .gpu),
                            gridColor: theme.gridLine,
                            timeAxis: CompressedTimeAxis(history: model.history.gpu, lastSample: model.lastSampleDate))
            }
            FigureGrid(figures: [
                Figure(label: "Utilisation", value: model.vitals?.gpuText ?? "—"),
                Figure(label: "GPU", value: model.vitals?.gpu?.descriptionText ?? "—"),
                Figure(label: "Memory in use", value: model.vitals?.gpu?.memoryText ?? "—"),
            ])
            Text("GPU memory is shared with the CPU on Apple silicon; it’s part of Memory’s total, not extra.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }
}
