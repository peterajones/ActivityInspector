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
    /// Copy and Export Report… leave identifying values out unless this is on.
    var includesIdentifying = false

    private let runner: any SystemProfilerRunning
    private var labels: ProfilerLabels?
    private var preloaded = false

    init(runner: any SystemProfilerRunning = SystemProfilerRunner(), labels: ProfilerLabels? = nil) {
        self.runner = runner
        self.labels = labels
    }

    func state(of id: String) -> SystemInfoState? { states[id] }

    /// Set while Export Report… reads every type; nil otherwise.
    private(set) var loadAllProgress: SystemInfoLoadAllProgress?

    /// Reads every type not yet read, slow ones included, four at a time, counting as it goes.
    func loadAll() async {
        let ids = SystemInfoItem.catalog.map(\.id)
        loadAllProgress = SystemInfoLoadAllProgress(done: 0, total: ids.count)
        var done = 0
        var queue = ids.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                if let id = queue.next() { group.addTask { await self.load(id) } }
            }
            while await group.next() != nil {
                done += 1
                loadAllProgress = SystemInfoLoadAllProgress(done: done, total: ids.count)
                if let id = queue.next() { group.addTask { await self.load(id) } }
            }
        }
        loadAllProgress = nil
    }

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

    /// Reads under way, so asking again waits for the same read instead of skipping it.
    private var reads: [String: Task<Void, Never>] = [:]

    /// Reads `id` unless it's already read; if it's being read, waits for that. `force` reads
    /// it again.
    func load(_ id: String, force: Bool = false) async {
        if !force, let reading = reads[id] {
            await reading.value
            return
        }
        if !force, states[id] != nil { return }
        let read = Task { await self.read(id) }
        reads[id] = read
        await read.value
        if reads[id] == read { reads[id] = nil }
    }

    private func read(_ id: String) async {
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
