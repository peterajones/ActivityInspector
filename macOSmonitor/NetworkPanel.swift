import SwiftUI

/// The Network Performance page: received and sent, sharing one autoscaled axis, then each
/// interface.
struct NetworkPanel: View {
    let model: VitalsModel
    @Environment(\.theme) private var theme

    private var range: ClosedRange<Double> {
        MetricScale.autoscaled([model.history.networkIn, model.history.networkOut])
    }

    var body: some View {
        PanelPage(.network, model: model) {
            GraphSection(label: "Throughput · last 60 s", note: "scale \(scaleLabel)") {
                ZStack {
                    MetricGraph(values: model.history.networkIn.values,
                                range: range,
                                lineColor: theme.color(for: .network),
                                fillColor: theme.fillColor(for: .network),
                                gridColor: theme.gridLine,
                                timeAxis: CompressedTimeAxis(history: model.history.networkIn, lastSample: model.lastSampleDate))
                    MetricGraph(values: model.history.networkOut.values,
                                range: range,
                                lineColor: theme.secondaryText,
                                fillColor: .clear,
                                gridColor: .clear,
                                timeAxis: CompressedTimeAxis(history: model.history.networkOut, lastSample: model.lastSampleDate),
                                showsBorder: false)
                }
            }
            HStack(spacing: 14) {
                Label("Received", systemImage: "arrow.down").foregroundStyle(theme.color(for: .network))
                Label("Sent", systemImage: "arrow.up").foregroundStyle(theme.secondaryText)
            }
            .font(.caption)
            if let vitals = model.vitals {
                FigureGrid(figures: Self.figures(vitals))
            }
            if let interfaces = model.vitals?.networkInterfaces, !interfaces.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        Text("Interface")
                        Label("Received", systemImage: "arrow.down")
                            .gridColumnAlignment(.trailing)
                        Label("Sent", systemImage: "arrow.up")
                            .gridColumnAlignment(.trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(interfaces, id: \.name) { row in
                        GridRow {
                            Text(row.name).foregroundStyle(theme.primaryText)
                            Text(row.inText).foregroundStyle(theme.color(for: .network))
                            Text(row.outText).foregroundStyle(theme.secondaryText)
                        }
                        .monospacedDigit()
                    }
                }
            }
        }
    }

    /// Current rates, then totals since boot.
    nonisolated static func figures(_ vitals: SystemVitals) -> [Figure] {
        [Figure(label: "Received", value: SystemVitals.rate(vitals.networkInBytesPerSec)),
         Figure(label: "Sent", value: SystemVitals.rate(vitals.networkOutBytesPerSec)),
         Figure(label: "Received since boot", value: VolumeCapacity.decimal(vitals.networkTotalReceivedBytes)),
         Figure(label: "Sent since boot", value: VolumeCapacity.decimal(vitals.networkTotalSentBytes))]
    }

    private var scaleLabel: String {
        SystemVitals.rate(range.upperBound)
    }
}
