import SwiftUI

/// The Disk Performance page: read and write throughput sharing one autoscaled axis.
struct DiskPanel: View {
    let model: VitalsModel
    @Environment(\.theme) private var theme

    private var range: ClosedRange<Double> {
        MetricScale.autoscaled([model.history.diskRead, model.history.diskWrite])
    }

    var body: some View {
        PanelPage(.disk, model: model) {
            GraphSection(label: "Transfer rate · last 60 s", note: "scale \(scaleLabel)") {
                ZStack {
                    MetricGraph(values: model.history.diskRead.values, range: range,
                                lineColor: theme.color(for: .disk), fillColor: theme.fillColor(for: .disk),
                                gridColor: theme.gridLine,
                                timeAxis: CompressedTimeAxis(history: model.history.diskRead, lastSample: model.lastSampleDate))
                    MetricGraph(values: model.history.diskWrite.values, range: range,
                                lineColor: theme.secondaryText, fillColor: .clear,
                                gridColor: .clear,
                                timeAxis: CompressedTimeAxis(history: model.history.diskWrite, lastSample: model.lastSampleDate),
                                showsBorder: false)
                }
            }
            HStack(spacing: 14) {
                Label("Read", systemImage: "arrow.down").foregroundStyle(theme.color(for: .disk))
                Label("Write", systemImage: "arrow.up").foregroundStyle(theme.secondaryText)
            }
            .font(.caption)
            FigureGrid(figures: [
                Figure(label: "Read", value: SystemVitals.rate(model.vitals?.diskReadBytesPerSec ?? 0)),
                Figure(label: "Write", value: SystemVitals.rate(model.vitals?.diskWriteBytesPerSec ?? 0)),
            ])
        }
    }

    private var scaleLabel: String {
        SystemVitals.rate(range.upperBound)
    }
}
