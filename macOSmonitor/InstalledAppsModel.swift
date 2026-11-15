import Foundation
import Observation

/// One row of the Installed Apps table: an app and, once measured, its size. The sort keys
/// are plain values so the table can sort by them.
struct InstalledAppRow: Identifiable, Equatable, Sendable {
    let app: InstalledApp
    let size: UInt64?

    var id: String { app.id }
    var name: String { app.name }
    var version: String { app.version ?? "" }
    var kindText: String { app.kind.text }
    var originText: String { app.origin.text }
    var publisher: String { app.publisher }
    /// Unmeasured apps sort as smallest.
    var sizeSort: UInt64 { size ?? 0 }
    var modifiedSort: Date { app.modified ?? .distantPast }
}

/// Installed Apps: system_profiler's Applications data, read the first time the page shows,
/// then each bundle's size measured in the background, installed apps first.
@MainActor
@Observable
final class InstalledAppsModel {
    enum Status: Equatable, Sendable { case idle, loading, loaded, failed }

    private(set) var apps: [InstalledApp] = []
    private(set) var status: Status = .idle
    private(set) var sizes: [String: UInt64] = [:]
    /// The background measuring; tests await it.
    private(set) var sizingTask: Task<Void, Never>?
    var filter = ""
    /// Off: only apps in an Applications folder. On: system helpers and build products too.
    var showsAllApps = false
    var selection: InstalledApp.ID?
    var sortOrder = [KeyPathComparator(\InstalledAppRow.name)]

    private let runner: any SystemProfilerRunning
    private let sizer: any AppSizing
    private let home: String

    private let linkedApps: @Sendable (String) -> [InstalledApp]

    init(runner: any SystemProfilerRunning = SystemProfilerRunner(), sizer: any AppSizing = AppSizer(),
         home: String = UserHome.path,
         linkedApps: @escaping @Sendable (String) -> [InstalledApp] = InstalledAppLinks.find(home:)) {
        self.linkedApps = linkedApps
        self.runner = runner
        self.sizer = sizer
        self.home = home
    }

    /// Which apps show (installed ones unless all are asked for), then the filter (name,
    /// publisher or path, ignoring case), sorted by the table's columns.
    var visibleRows: [InstalledAppRow] {
        let rows = apps
            .filter { showsAllApps || InstalledApp.isInstalled(path: $0.path, home: home) }
            .filter { app in
                filter.isEmpty || [app.name, app.publisher, app.path].contains { $0.localizedCaseInsensitiveContains(filter) }
            }
            .map { InstalledAppRow(app: $0, size: sizes[$0.id]) }
        return rows.sorted(using: sortOrder)
    }

    var selectedRow: InstalledAppRow? {
        apps.first { $0.id == selection }.map { InstalledAppRow(app: $0, size: sizes[$0.id]) }
    }

    func loadIfNeeded() async {
        guard status == .idle else { return }
        await reload()
    }

    /// Reads the list again and measures it afresh.
    func reload() async {
        sizingTask?.cancel()
        status = .loading
        guard let data = await runner.run("SPApplicationsDataType"),
              let parsed = InstalledAppsParser.parse(data) else {
            status = .failed
            return
        }
        let home = home, linkedApps = linkedApps
        let linked = await Task.detached { linkedApps(home) }.value
        let listed = Set(parsed.map(\.id))
        apps = parsed + linked.filter { !listed.contains($0.id) }
        sizes = [:]
        status = .loaded
        startSizing()
    }

    /// One bundle at a time on a GCD thread (walking a bundle blocks), installed apps first,
    /// publishing every few results so the column fills in without a redraw per app.
    private func startSizing() {
        let home = home
        let order = apps.filter { InstalledApp.isInstalled(path: $0.path, home: home) }
            + apps.filter { !InstalledApp.isInstalled(path: $0.path, home: home) }
        let paths = order.map(\.id), sizer = sizer
        sizingTask = Task { [weak self] in
            var batch: [String: UInt64] = [:]
            for (index, path) in paths.enumerated() {
                if Task.isCancelled { return }
                let size = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async { continuation.resume(returning: sizer.size(ofAppAt: path)) }
                }
                if let size { batch[path] = size }
                if batch.count >= 8 || index == paths.count - 1, !Task.isCancelled {
                    self?.sizes.merge(batch) { _, new in new }
                    batch = [:]
                }
            }
        }
    }
}
