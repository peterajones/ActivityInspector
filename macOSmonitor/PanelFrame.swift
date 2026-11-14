import SwiftUI

/// One labelled figure on a Performance page.
struct Figure: Equatable, Identifiable, Sendable {
    let label: String
    let value: String
    /// An SF Symbol; figures with one are drawn as tiles.
    var systemImage: String? = nil
    var id: String { label }
}

/// How full a Performance page's header meter is, by the same rule the rest of the app uses
/// for that metric: shares for CPU, GPU, Memory and Battery; the Summary tiles' busiest-second
/// rule for Network and Disk; the panels' own scales for Thermal and Energy.
enum PerformanceMeter {
    nonisolated static func fraction(_ surface: Surface, vitals: SystemVitals?, thermal: ThermalReading?,
                                     power: PowerReading?, history: VitalsHistory,
                                     powerHistory: MetricHistory) -> Double {
        guard let vitals else { return 0 }
        switch surface {
        case .cpu: return vitals.cpuUsagePercent / 100
        case .gpu: return (vitals.gpu?.utilizationPercent ?? 0) / 100
        case .memory: return vitals.memoryUsedFraction
        case .network:
            return SummaryTile.network(vitals, inHistory: history.networkIn, outHistory: history.networkOut).fraction
        case .disk:
            return SummaryTile.disk(vitals, readHistory: history.diskRead, writeHistory: history.diskWrite).fraction
        case .thermal: return ThermalPanel.meterFraction(thermal?.headline)
        case .energy: return EnergyPanel.meterFraction(power?.systemWatts, history: powerHistory)
        case .battery: return Double(vitals.battery?.chargePercent ?? 0) / 100
        case .summary, .processes, .ports, .systemInfo, .startupApps, .services: return 0
        }
    }

    /// The value beside a page's meter: the column's value, except Network and Disk, whose
    /// in/out split is too long there; the header shows their total and the figures the split.
    nonisolated static func headerValue(_ surface: Surface, row: PerformanceRow, vitals: SystemVitals?) -> String {
        guard let vitals else { return row.value }
        switch surface {
        case .network: return SystemVitals.rate(vitals.networkInBytesPerSec + vitals.networkOutBytesPerSec)
        case .disk: return SystemVitals.rate(vitals.diskReadBytesPerSec + vitals.diskWriteBytesPerSec)
        default: return row.value
        }
    }
}

/// The frame every Performance page shares: a large title and subtitle, a wide glowing meter
/// in the metric's colour with the value beside it, then the page's sections, scrolling when
/// the window is short.
struct PanelPage<Content: View>: View {
    let title: String
    let subtitle: String
    let metric: Metric
    let fraction: Double
    let value: String
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme

    var body: some View {
        let color = theme.color(for: metric)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(theme.primaryText)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                    HStack(spacing: 14) {
                        MeterBar(fraction: fraction, orientation: .horizontal,
                                 onColor: color, offColor: color.opacity(0.15), glows: true)
                            .frame(height: 14)
                        Text(value)
                            .font(.title2)
                            .monospacedDigit()
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(theme.panelBackground)
    }
}

/// A graph with a small label above it and an optional note at the right.
struct GraphSection<Graph: View>: View {
    let label: String
    var note: String? = nil
    var height: CGFloat = 200
    @ViewBuilder let graph: () -> Graph

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                if let note { Text(note).monospacedDigit() }
            }
            .font(.caption)
            .foregroundStyle(theme.secondaryText)
            graph()
                .frame(height: height)
        }
    }
}

/// Figures as a grid: a small grey label over a bold value, as many columns as fit. Figures
/// with an icon are drawn as tiles, the icon in `tint`.
struct FigureGrid: View {
    let figures: [Figure]
    var tint: Color? = nil

    @Environment(\.theme) private var theme

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: figures.contains { $0.systemImage != nil } ? 180 : 140),
                  alignment: .topLeading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(figures) { figure in
                if let icon = figure.systemImage {
                    tile(figure, icon: icon)
                } else {
                    plain(figure)
                }
            }
        }
    }

    private func tile(_ figure: Figure, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint ?? theme.primaryText)
                .frame(width: 26)
            plain(figure)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(theme.secondaryText.opacity(0.08)))
    }

    private func plain(_ figure: Figure) -> some View {
                VStack(alignment: .leading, spacing: 2) {
                    Text(figure.label)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Text(figure.value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
    }
}

extension PanelPage {
    /// A metric page's frame, with the subtitle and value the Performance column shows for it,
    /// so the two always agree.
    init(_ surface: Surface, model: VitalsModel, @ViewBuilder content: @escaping () -> Content) {
        let row = PerformanceRow(surface, vitals: model.vitals, thermal: model.thermal, power: model.power)
        self.init(title: surface.title, subtitle: row.detail, metric: surface.metric ?? .cpu,
                  fraction: PerformanceMeter.fraction(surface, vitals: model.vitals, thermal: model.thermal,
                                                      power: model.power, history: model.history,
                                                      powerHistory: model.powerHistory),
                  value: PerformanceMeter.headerValue(surface, row: row, vitals: model.vitals), content: content)
    }
}
