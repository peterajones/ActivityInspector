import SwiftUI

/// The Disk Performance page: active time, read and write throughput on one autoscaled axis,
/// response time, totals since boot and the startup disk's size.
struct DiskPanel: View {
    let model: VitalsModel
    @Environment(\.theme) private var theme

    private var range: ClosedRange<Double> {
        MetricScale.autoscaled([model.history.diskRead, model.history.diskWrite])
    }

    var body: some View {
        PanelPage(.disk, model: model) {
            GraphSection(label: "Active time · last 60 s", note: "0–100%", height: 140) {
                MetricGraph(values: model.history.diskActive.values,
                            range: MetricScale.fixed(100),
                            lineColor: theme.color(for: .disk),
                            fillColor: theme.fillColor(for: .disk),
                            gridColor: theme.gridLine,
                            timeAxis: CompressedTimeAxis(history: model.history.diskActive, lastSample: model.lastSampleDate))
            }
            GraphSection(label: "Transfer rate · last 60 s", note: "scale \(scaleLabel)", height: 140) {
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
            if let vitals = model.vitals {
                FigureGrid(figures: Self.figures(vitals))
            }
        }
    }

    /// The page's figures: rates, active and response time, totals since boot, and the
    /// startup volume's size where it can be read.
    nonisolated static func figures(_ vitals: SystemVitals) -> [Figure] {
        var figures = [
            Figure(label: "Read", value: SystemVitals.rate(vitals.diskReadBytesPerSec)),
            Figure(label: "Write", value: SystemVitals.rate(vitals.diskWriteBytesPerSec)),
            Figure(label: "Active time", value: "\(Int(vitals.diskActivePercent.rounded()))%"),
            Figure(label: "Response time", value: vitals.diskResponseMillis.map { String(format: "%.1f ms", $0) } ?? "—"),
            Figure(label: "Read since boot", value: VolumeCapacity.decimal(vitals.diskTotalReadBytes)),
            Figure(label: "Written since boot", value: VolumeCapacity.decimal(vitals.diskTotalWrittenBytes)),
        ]
        if let volume = vitals.startupVolume {
            figures.append(Figure(label: "Startup disk", value: volume.totalText))
            figures.append(Figure(label: "Available", value: volume.availableText))
        }
        return figures
    }

    private var scaleLabel: String {
        SystemVitals.rate(range.upperBound)
    }
}
