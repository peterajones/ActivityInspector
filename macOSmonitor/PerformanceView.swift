import SwiftUI

/// The Performance section: a column of every metric this Mac reports (title, a detail line,
/// the value and a small graph), with the chosen metric's page beside it.
///
/// The small graphs update once a second and don't glide: eight more gliding graphs would
/// roughly double the page's cost, for a difference nobody sees at this size.
struct PerformanceView<Page: View>: View {
    @Binding var selection: Surface?
    let items: [Surface]
    let vitalsModel: VitalsModel
    @ViewBuilder let page: () -> Page

    @Environment(\.theme) private var theme

    static var columnWidth: CGFloat { 250 }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(items) { item in row(item) }
                }
                .padding(8)
            }
            .frame(width: Self.columnWidth)
            .background(theme.panelBackground)

            Rectangle().fill(theme.secondaryText.opacity(0.25)).frame(width: 1)

            page()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ item: Surface) -> some View {
        let color = item.metric.map { theme.color(for: $0) } ?? theme.primaryText
        let text = PerformanceRow(item, vitals: vitalsModel.vitals, thermal: vitalsModel.thermal,
                                  power: vitalsModel.power)
        let selected = selection == item
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button { selection = item } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: Self.icon(item))
                    .foregroundStyle(color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(theme.primaryText)
                    Text(text.detail)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Text(text.value)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                thumbnail(item, color: color)
                    .frame(width: 50, height: 34)
            }
            .padding(8)
            .background(shape.fill(selected ? color.opacity(0.16) : .clear))
            .overlay(shape.strokeBorder(selected ? color.opacity(0.7) : .clear, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    static func icon(_ item: Surface) -> String {
        switch item {
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .thermal: "thermometer.medium"
        case .energy: "bolt"
        case .battery: "battery.75percent"
        case .summary, .processes, .ports: "questionmark"
        }
    }

    /// A small, still graph of the metric's history (Battery: its charge as a meter).
    @ViewBuilder private func thumbnail(_ item: Surface, color: Color) -> some View {
        let model = vitalsModel
        switch item {
        case .cpu: graph(model.history.cpu, range: MetricScale.fixed(100), color: color)
        case .gpu: graph(model.history.gpu, range: MetricScale.fixed(100), color: color)
        case .memory:
            graph(model.history.memoryUsed,
                  range: MetricScale.zoomed(model.history.memoryUsed.values,
                                            ceiling: Double(model.vitals?.totalMemoryBytes ?? 1),
                                            minimumSpan: 1_073_741_824),
                  color: color)
        case .network:
            pair(model.history.networkIn, model.history.networkOut, color: color)
        case .disk:
            pair(model.history.diskRead, model.history.diskWrite, color: color)
        case .thermal: graph(model.thermalHistory, range: MetricScale.fixed(ThermalPanel.scaleMax), color: color)
        case .energy: graph(model.powerHistory, range: EnergyPanel.range(model.powerHistory), color: color)
        case .battery:
            MeterBar(fraction: Double(model.vitals?.battery?.chargePercent ?? 0) / 100,
                     orientation: .horizontal, onColor: color, offColor: color.opacity(0.15), glows: true)
                .frame(height: 10)
                .frame(maxHeight: .infinity)
        case .summary, .processes, .ports: EmptyView()
        }
    }

    /// Compressed like the big graphs, but still: no sample time, so it rests at the edge,
    /// and paused, so it only redraws when a new sample arrives.
    private func graph(_ history: MetricHistory, range: ClosedRange<Double>, color: Color,
                       fill: Bool = true, border: Bool = true) -> some View {
        MetricGraph(values: history.values,
                    capacity: history.capacity,
                    range: range,
                    lineColor: color,
                    fillColor: fill ? color.opacity(0.18) : .clear,
                    gridColor: .clear,
                    timeAxis: CompressedTimeAxis(history: history, lastSample: nil),
                    showsBorder: border)
            .environment(\.graphsAnimate, false)
    }

    private func pair(_ first: MetricHistory, _ second: MetricHistory, color: Color) -> some View {
        let range = MetricScale.autoscaled([first, second])
        return ZStack {
            graph(first, range: range, color: color)
            graph(second, range: range, color: theme.secondaryText, fill: false, border: false)
        }
    }
}
