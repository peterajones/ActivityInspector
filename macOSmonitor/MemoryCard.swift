import SwiftUI

/// The Summary's full-width memory band: a meter, used memory over the last minute on a
/// zoomed scale, and what is available, cached and swapped.
struct MemoryCard: View {
    let model: VitalsModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text(model.vitals?.memoryText ?? "—")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(theme.color(for: .memory))
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(spacing: 6) {
                    MeterBar(fraction: model.vitals?.memoryUsedFraction ?? 0,
                             orientation: .vertical,
                             onColor: theme.color(for: .memory),
                             offColor: theme.color(for: .memory).opacity(0.15),
                             glows: true)
                        .frame(width: 14)
                    Text(model.vitals?.memoryPercentText ?? "—")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(theme.color(for: .memory))
                        .fixedSize()
                }
                MetricGraph(values: model.history.memoryUsed.values,
                        range: graphRange,
                        lineColor: theme.color(for: .memory),
                        fillColor: theme.fillColor(for: .memory),
                        gridColor: theme.gridLine,
                        timeAxis: CompressedTimeAxis(history: model.history.memoryUsed, lastSample: model.lastSampleDate))
                .frame(minHeight: 60, maxHeight: .infinity)
                .overlay(alignment: .topLeading) { rangeLabel(graphRange.upperBound) }
                .overlay(alignment: .bottomLeading) { rangeLabel(graphRange.lowerBound) }
            }

            HStack {
                let footer = Self.footer(model.vitals)
                ForEach(Array(footer.enumerated()), id: \.offset) { index, text in
                    if index > 0 { Spacer() }
                    Text(text)
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(theme.color(for: .memory))
    }

    /// Zoomed to the last minute's band, at least 1 GB tall, like the Memory panel, so a
    /// change of a few hundred megabytes shows instead of a flat line near the top.
    private var graphRange: ClosedRange<Double> {
        Self.graphRange(model.history, totalBytes: model.vitals?.totalMemoryBytes)
    }

    nonisolated static func graphRange(_ history: VitalsHistory, totalBytes: UInt64?) -> ClosedRange<Double> {
        MetricScale.zoomed(history.memoryUsed.values, ceiling: Double(totalBytes ?? 1), minimumSpan: 1_073_741_824)
    }

    /// "Available 16.0 GB", "Cached 3.5 GB", "Swap 0.5 / 2.0 GB", with dashes until read.
    nonisolated static func footer(_ vitals: SystemVitals?) -> [String] {
        ["Available \(vitals?.availableMemoryText ?? "—")",
         "Cached \(vitals?.cachedMemoryText ?? "—")",
         "Swap \(vitals?.swapText ?? "—")"]
    }

    private func rangeLabel(_ bytes: Double) -> some View {
        Text(SystemVitals.gigabytes(bytes))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(theme.color(for: .memory))
            .padding(6)
    }
}
