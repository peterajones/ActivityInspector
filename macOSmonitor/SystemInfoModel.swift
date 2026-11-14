import Foundation
import Observation

enum SystemInfoState: Equatable, Sendable {
    case loading
    case loaded([ProfilerNode])
    case failed
}

/// What System Info has read so far. Each type is read once and kept (Reload reads it again).
/// Opening the page preloads the fast types in the background, so types that are empty on this
/// Mac can drop out of the list; slow ones (Wi-Fi takes ~20 s) wait until they're chosen.
@MainActor
@Observable
final class SystemInfoModel {
    private(set) var states: [String: SystemInfoState] = [:]
    var selection = "SPHardwareDataType"

    private let runner: any SystemProfilerRunning
    private var labels: ProfilerLabels?
    private var preloaded = false

    init(runner: any SystemProfilerRunning = SystemProfilerRunner(), labels: ProfilerLabels? = nil) {
        self.runner = runner
        self.labels = labels
    }

    func state(of id: String) -> SystemInfoState? { states[id] }

    /// The category's items, less any this Mac has nothing for.
    func visibleItems(in category: SystemInfoCategory) -> [SystemInfoItem] {
        SystemInfoItem.catalog.filter { $0.category == category && states[$0.id] != .loaded([]) }
    }

    /// Reads every fast type, four at a time. Once per model.
    func preload() async {
        guard !preloaded else { return }
        preloaded = true
        var queue = SystemInfoItem.catalog.filter { !$0.isSlow }.map(\.id).makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                if let id = queue.next() { group.addTask { await self.load(id) } }
            }
            while await group.next() != nil {
                if let id = queue.next() { group.addTask { await self.load(id) } }
            }
        }
    }

    /// Reads `id` unless it's already read or being read; `force` reads it again.
    func load(_ id: String, force: Bool = false) async {
        if !force, states[id] != nil { return }
        states[id] = .loading
        let labels = await currentLabels()
        guard let data = await runner.run(id) else {
            states[id] = .failed
            return
        }
        // Parsing a big type (Fonts) takes a moment: off the main actor.
        let nodes = await Task.detached { ProfilerParser.parse(data, type: id, labels: labels) }.value
        states[id] = nodes.map { .loaded($0) } ?? .failed
    }

    private func currentLabels() async -> ProfilerLabels {
        if let labels { return labels }
        let loaded = await Task.detached { ProfilerLabels.system(languages: Locale.preferredLanguages) }.value
        labels = loaded
        return loaded
    }
}
