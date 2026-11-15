import Foundation
import Observation

/// One row of Startup Apps or Services: a launchd job and its live state.
struct LaunchRow: Identifiable, Equatable, Sendable {
    let item: LaunchItem
    let enabled: Bool
    /// Nil when it isn't running.
    let pid: Int?
    let lastExit: Int?
    let publisher: String

    var id: String { item.id }
}

/// Startup Apps (this user's and all users' launch agents) or Services (launch daemons):
/// what's there, whether it's enabled and running, who made it, and, for agents, switching
/// them on and off.
@MainActor
@Observable
final class LaunchItemsModel {
    enum Kind: Sendable { case startup, services }

    let kind: Kind
    private(set) var rows: [LaunchRow] = []
    var filter = ""
    /// Services only: macOS's own ~425 daemons are hidden unless asked for.
    var showsAppleServices = false
    var selection: LaunchRow.ID?

    private let files: any LaunchFilesProviding
    private let launchctl: any LaunchctlRunning
    private let uid: uid_t
    private let directories: [(path: String, scope: LaunchScope)]
    private let publisher: @Sendable (String) -> String

    init(kind: Kind,
         files: any LaunchFilesProviding = LaunchFiles(),
         launchctl: any LaunchctlRunning = Launchctl(),
         uid: uid_t = getuid(),
         userAgentsDirectory: String = UserHome.path + "/Library/LaunchAgents",
         publisher: @escaping @Sendable (String) -> String = CodePublisher.publisher(ofProgramAt:)) {
        self.kind = kind
        self.files = files
        self.launchctl = launchctl
        self.uid = uid
        self.publisher = publisher
        directories = kind == .startup
            ? [(userAgentsDirectory, .userAgent), ("/Library/LaunchAgents", .allUsersAgent)]
            : [("/Library/LaunchDaemons", .daemon), ("/System/Library/LaunchDaemons", .appleDaemon)]
    }

    private var domain: String { kind == .startup ? "gui/\(uid)" : "system" }

    /// The rows the table shows: Apple's daemons only when asked, then the filter (label,
    /// command or publisher, ignoring case).
    var visibleRows: [LaunchRow] {
        rows.filter { row in
            (showsAppleServices || row.item.scope != .appleDaemon)
                && (filter.isEmpty || [row.item.label, row.item.commandLine, row.publisher]
                    .contains { $0.localizedCaseInsensitiveContains(filter) })
        }
    }

    var selectedRow: LaunchRow? { rows.first { $0.id == selection } }

    /// A checkbox click waiting for the user to confirm it.
    struct PendingChange: Equatable, Sendable {
        let row: LaunchRow
        let enable: Bool
    }

    private(set) var pendingChange: PendingChange?

    /// Asks first: nothing changes until `confirm`.
    func requestChange(_ row: LaunchRow, enable: Bool) {
        pendingChange = PendingChange(row: row, enable: enable)
    }

    func cancelChange() {
        pendingChange = nil
    }

    /// Runs a confirmed change; nil on success, else what went wrong.
    func confirm(_ change: PendingChange) async -> String? {
        pendingChange = nil
        return await setEnabled(change.row, change.enable)
    }

    /// Reads the files, then launchd's running and enabled state.
    func refresh() async {
        let files = files, directories = directories, publisher = publisher
        // File reads and signature checks off the main actor.
        let read: [(LaunchItem, String)] = await Task.detached {
            directories.flatMap { directory in
                directory.path.isEmpty ? [] : files.plists(in: directory.path).compactMap { path -> (LaunchItem, String)? in
                    let plist = files.contents(of: path)
                    var item = plist.flatMap { LaunchItem.parse($0, path: path, scope: directory.scope) }
                        ?? LaunchItem.ignored(path: path, scope: directory.scope, readable: plist != nil)
                    item.facts = files.facts(of: path)
                    let made = item.problem != nil ? "—"
                        : item.scope == .appleDaemon ? "Apple" : item.program.map(publisher) ?? "Unknown"
                    return (item, made)
                }
                .sorted { $0.0.label.localizedCaseInsensitiveCompare($1.0.label) == .orderedAscending }
            }
        }.value
        async let printed = launchctl.output(["print", domain])
        async let disabled = launchctl.output(["print-disabled", domain])
        let services = LaunchctlOutput.services(await printed ?? "")
        let overrides = LaunchctlOutput.overrides(await disabled ?? "")
        rows = read.map { item, made in
            let service = services[item.label]
            return LaunchRow(item: item, enabled: overrides[item.label] ?? !item.disabledInFile,
                             pid: service?.pid, lastExit: service?.lastExit, publisher: made)
        }
    }

    /// Switches an agent on (enable, then load it) or off (disable, then stop it), then reads
    /// the state again. Nil on success, else what went wrong. Daemons need an administrator.
    func setEnabled(_ row: LaunchRow, _ enabled: Bool) async -> String? {
        guard row.item.scope.isAgent else {
            return "Changing a system service needs an administrator."
        }
        if let problem = row.item.problem { return problem }
        let target = "\(domain)/\(row.item.label)"
        if enabled {
            guard await launchctl.run(["enable", target]) == 0 else { return "macOS didn’t enable \(row.item.label)." }
            // Loading may fail harmlessly when it's already loaded.
            _ = await launchctl.run(["bootstrap", domain, row.item.plistPath])
        } else {
            guard await launchctl.run(["disable", target]) == 0 else { return "macOS didn’t disable \(row.item.label)." }
            // Stopping fails harmlessly when it isn't loaded.
            _ = await launchctl.run(["bootout", target])
        }
        await refresh()
        return nil
    }
}
