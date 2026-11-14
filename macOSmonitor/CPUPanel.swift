import SwiftUI

/// The CPU Performance page: utilisation over the last minute, or — via right-click — a
/// per-core grid, mirroring Task Manager's "Logical processors" toggle; then the figures.
struct CPUPanel: View {
    let model: VitalsModel
    @Environment(\.theme) private var theme
    @State private var showsCores = false

    var body: some View {
        PanelPage(.cpu, model: model) {
            if showsCores {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Utilisation per core · last 60 s · right-click for overall")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    CoreGrid(histories: model.history.perCore,
                             labels: CoreLayout.labels(for: model.coreLayout,
                                                       coreCount: model.history.perCore.count)
                                .map { label in
                                    model.vitals?.coreFrequencies[label].map { "\(label) · \($0.text)" } ?? label
                                },
                             lineColor: theme.color(for: .cpu),
                             fillColor: theme.fillColor(for: .cpu),
                             backgroundColor: theme.meterOff,
                             lastSample: model.lastSampleDate)
                }
            } else {
                GraphSection(label: "Utilisation · last 60 s", note: "right-click for per core") {
                    MetricGraph(values: model.history.cpu.values,
                                range: MetricScale.fixed(100),
                                lineColor: theme.color(for: .cpu),
                                fillColor: theme.fillColor(for: .cpu),
                                gridColor: theme.gridLine,
                                timeAxis: CompressedTimeAxis(history: model.history.cpu, lastSample: model.lastSampleDate))
                }
            }
            if let vitals = model.vitals {
                FigureGrid(figures: Self.figures(vitals, layout: model.coreLayout))
            }
        }
        .contextMenu {
            Button(showsCores ? "Overall Utilisation" : "Logical Processors") {
                showsCores.toggle()
            }
        }
    }

    /// The page's figures in reading order: core kinds only with a known layout, clocks only
    /// where this Mac reports them.
    nonisolated static func figures(_ vitals: SystemVitals, layout: CoreLayout?) -> [Figure] {
        var figures = [Figure(label: "Utilisation", value: vitals.cpuText),
                       Figure(label: "Kernel", value: percent(vitals.cpuSystemPercent)),
                       Figure(label: "Cores", value: layout?.coreCountText ?? "\(vitals.coreCount)")]
        if let layout {
            if let load = layout.averageLoad(of: .performance, perCore: vitals.perCoreUsagePercent) {
                figures.append(Figure(label: "P cores", value: percent(load)))
            }
            if let load = layout.averageLoad(of: .efficiency, perCore: vitals.perCoreUsagePercent) {
                figures.append(Figure(label: "E cores", value: percent(load)))
            }
        }
        if !vitals.coreFrequencies.isEmpty {
            figures.append(Figure(label: "P clock", value: clusterClock(vitals.coreFrequencies, prefix: "P")))
            figures.append(Figure(label: "E clock", value: clusterClock(vitals.coreFrequencies, prefix: "E")))
        }
        figures.append(Figure(label: "Active", value: "\(vitals.activeCoreCount)"))
        figures.append(Figure(label: "Up time", value: vitals.uptimeText))
        return figures
    }

    private nonisolated static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    /// "~3.1 GHz" across one kind of core, weighted by activity; "idle" when none ran.
    nonisolated static func clusterClock(_ frequencies: [String: CoreFrequency], prefix: String) -> String {
        let cores = frequencies.filter { $0.key.hasPrefix(prefix) }.map(\.value)
        guard !cores.isEmpty else { return "—" }
        return CPUFrequencyMath.groupAverageMHz(cores).map { "~" + CoreFrequency.text(mhz: $0) } ?? "idle"
    }
}
