import Foundation

/// What the sidebar lists. Every metric page lives under Performance, which opens a column of
/// metrics beside the chosen one's page.
enum SidebarItem: String, CaseIterable, Hashable, Identifiable {
    case summary, performance, processes, ports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Summary"
        case .performance: "Performance"
        case .processes: "Processes"
        case .ports: "Ports"
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "square.grid.2x2"
        case .performance: "waveform.path.ecg"
        case .processes: "list.bullet"
        case .ports: "network"
        }
    }

    /// The page this item opens. Performance reopens the metric last viewed, or CPU when that
    /// metric isn't on this Mac any more (a remembered GPU page on a VM, say).
    nonisolated func surface(lastMetric: Surface, available: [Surface]) -> Surface {
        switch self {
        case .summary: .summary
        case .processes: .processes
        case .ports: .ports
        case .performance: available.contains(lastMetric) ? lastMetric : .cpu
        }
    }
}

extension Surface {
    /// The sidebar item highlighted while this page shows.
    nonisolated var sidebarItem: SidebarItem {
        switch self {
        case .summary: .summary
        case .processes: .processes
        case .ports: .ports
        case .cpu, .gpu, .memory, .network, .disk, .thermal, .energy, .battery: .performance
        }
    }
}

/// One row of the Performance column: a detail line under the title, and the value.
struct PerformanceRow: Equatable, Sendable {
    let detail: String
    let value: String

    nonisolated init(_ surface: Surface, vitals: SystemVitals?, thermal: ThermalReading?, power: PowerReading?) {
        guard let vitals else {
            (detail, value) = ("", "—")
            return
        }
        switch surface {
        case .cpu:
            (detail, value) = ("\(vitals.coreCount) logical processors", vitals.cpuText)
        case .gpu:
            let name = vitals.gpu?.name ?? "GPU"
            let cores = vitals.gpu?.coreCount.map { " · \($0) cores" } ?? ""
            (detail, value) = (name + cores, vitals.gpuText)
        case .memory:
            (detail, value) = (vitals.memoryText, vitals.memoryPercentText)
        case .network:
            (detail, value) = ("Received and sent", vitals.networkText)
        case .disk:
            (detail, value) = ("Read and written", vitals.diskText)
        case .thermal:
            (detail, value) = ("\(vitals.thermalState) pressure", ThermalReading.text(thermal?.headline))
        case .energy:
            (detail, value) = (vitals.battery?.state == .discharging ? "On battery" : "On power",
                               PowerReading.text(power?.systemWatts))
        case .battery:
            if let battery = vitals.battery {
                (detail, value) = (SummaryTile.battery(battery).detail, "\(battery.chargePercent)%")
            } else {
                (detail, value) = ("", "—")
            }
        case .summary, .processes, .ports:
            (detail, value) = ("", "")
        }
    }
}
