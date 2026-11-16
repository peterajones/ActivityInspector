import Testing
import Foundation
@testable import ActivityInspector

final class FakeLaunchFiles: LaunchFilesProviding, @unchecked Sendable {
    /// directory → (file path → plist)
    var directories: [String: [String: [String: Any]]] = [:]
    func plists(in directory: String) -> [String] { directories[directory].map { Array($0.keys).sorted() } ?? [] }
    func contents(of path: String) -> [String: Any]? {
        directories.values.lazy.compactMap { $0[path] }.first
    }
    func facts(of path: String) -> FileFacts? { nil }
}

final class FakeLaunchctl: LaunchctlRunning, @unchecked Sendable {
    private let lock = NSLock()
    var outputs: [String: String] = [:]
    /// Exit status per command (by its first argument); 0 otherwise.
    var failures: [String: Int32] = [:]
    private var _commands: [[String]] = []
    var commands: [[String]] { lock.withLock { _commands } }

    func output(_ arguments: [String]) async -> String? { outputs[arguments.joined(separator: " ")] }
    func run(_ arguments: [String]) async -> Int32 {
        lock.withLock { _commands.append(arguments) }
        return failures[arguments[0]] ?? 0
    }
}

@MainActor
struct LaunchItemsModelTests {
    private let home = "/Users/u/Library/LaunchAgents"

    private func startup() -> (LaunchItemsModel, FakeLaunchFiles, FakeLaunchctl) {
        let files = FakeLaunchFiles()
        files.directories[home] = [
            "\(home)/com.dropbox.agent.plist": ["Label": "com.dropbox.agent", "Program": "/Apps/Dropbox", "RunAtLoad": true],
            "\(home)/homebrew.caddy.plist": ["Label": "homebrew.caddy", "Program": "/opt/caddy", "Disabled": true],
        ]
        files.directories["/Library/LaunchAgents"] = [
            "/Library/LaunchAgents/us.zoom.updater.plist": ["Label": "us.zoom.updater", "Program": "/Apps/zoom"],
        ]
        let launchctl = FakeLaunchctl()
        launchctl.outputs["print gui/501"] = "\tservices = {\n\t\t 5409 - \tcom.dropbox.agent\n\t\t 0 - \tus.zoom.updater\n\t}\n"
        // The override says enabled, beating the file's Disabled key.
        launchctl.outputs["print-disabled gui/501"] = "\t\t\"homebrew.caddy\" => enabled\n"
        let model = LaunchItemsModel(kind: .startup, files: files, launchctl: launchctl, uid: 501,
                                     userAgentsDirectory: home, publisher: { "Publisher of \($0)" })
        return (model, files, launchctl)
    }

    @Test func startupListsBothAgentFoldersWithState() async throws {
        let (model, _, launchctl) = startup()
        await model.refresh()
        #expect(model.rows.map(\.item.label) == ["com.dropbox.agent", "homebrew.caddy", "us.zoom.updater"])
        let dropbox = try #require(model.rows.first { $0.item.label == "com.dropbox.agent" })
        #expect(dropbox.pid == 5409)
        #expect(dropbox.enabled)
        #expect(dropbox.publisher == "Publisher of /Apps/Dropbox")
        #expect(dropbox.item.scope == .userAgent)
        #expect(model.rows.first { $0.item.label == "homebrew.caddy" }?.enabled == true)
        #expect(model.rows.first { $0.item.label == "us.zoom.updater" }?.pid == nil)
        #expect(model.rows.first { $0.item.label == "us.zoom.updater" }?.item.scope == .allUsersAgent)
        #expect(launchctl.commands.isEmpty)                      // reading runs nothing that changes state
    }

    @Test func disablingStopsTheAgentAfterDisablingIt() async throws {
        let (model, _, launchctl) = startup()
        await model.refresh()
        let row = try #require(model.rows.first { $0.item.label == "com.dropbox.agent" })
        let error = await model.setEnabled(row, false)
        #expect(error == nil)
        #expect(launchctl.commands == [["disable", "gui/501/com.dropbox.agent"],
                                       ["bootout", "gui/501/com.dropbox.agent"]])
    }

    @Test func enablingLoadsTheAgentAfterEnablingIt() async throws {
        let (model, _, launchctl) = startup()
        await model.refresh()
        let row = try #require(model.rows.first { $0.item.label == "homebrew.caddy" })
        _ = await model.setEnabled(row, true)
        #expect(launchctl.commands == [["enable", "gui/501/homebrew.caddy"],
                                       ["bootstrap", "gui/501", "\(home)/homebrew.caddy.plist"]])
    }

    @Test func aFailedChangeSaysSoAndGoesNoFurther() async throws {
        let (model, _, launchctl) = startup()
        launchctl.failures["disable"] = 1
        await model.refresh()
        let row = try #require(model.rows.first)
        let error = await model.setEnabled(row, false)
        #expect(error != nil)
        #expect(launchctl.commands.map(\.first) == ["disable"])
    }

    @Test func theStateIsReadAgainAfterAChange() async throws {
        let (model, _, launchctl) = startup()
        await model.refresh()
        launchctl.outputs["print-disabled gui/501"] = "\t\t\"com.dropbox.agent\" => disabled\n"
        let row = try #require(model.rows.first { $0.item.label == "com.dropbox.agent" })
        _ = await model.setEnabled(row, false)
        #expect(model.rows.first { $0.item.label == "com.dropbox.agent" }?.enabled == false)
    }

    @Test func servicesHideAppleDaemonsUntilAskedAndCantBeChanged() async throws {
        let files = FakeLaunchFiles()
        files.directories["/Library/LaunchDaemons"] = ["/Library/LaunchDaemons/com.docker.vmnetd.plist":
                                                        ["Label": "com.docker.vmnetd", "Program": "/x"]]
        files.directories["/System/Library/LaunchDaemons"] = ["/System/Library/LaunchDaemons/com.apple.bootpd.plist":
                                                               ["Label": "com.apple.bootpd", "Program": "/usr/libexec/bootpd"]]
        let launchctl = FakeLaunchctl()
        launchctl.outputs["print system"] = "\tservices = {\n\t\t 857 - \tcom.docker.vmnetd\n\t}\n"
        let model = LaunchItemsModel(kind: .services, files: files, launchctl: launchctl, uid: 501,
                                     publisher: { _ in "P" })
        await model.refresh()
        #expect(model.visibleRows.map(\.item.label) == ["com.docker.vmnetd"])
        #expect(model.visibleRows.first?.pid == 857)
        model.showsAppleServices = true
        #expect(model.visibleRows.map(\.item.label) == ["com.docker.vmnetd", "com.apple.bootpd"])
        #expect(model.rows.first { $0.item.label == "com.apple.bootpd" }?.publisher == "Apple")

        let error = await model.setEnabled(model.rows[0], false)
        #expect(error != nil)                                 // daemons need an administrator
        #expect(launchctl.commands.isEmpty)
    }

    /// Leftover files with no Label (old Google and Dropbox updaters) are listed, so they can be
    /// found and removed, but launchd ignores them, so they can't be switched.
    @Test func aFileThatIsntAJobIsListedAsIgnored() async throws {
        let (model, files, launchctl) = startup()
        files.directories[home]?["\(home)/com.google.keystone.agent.plist"] = [:]
        await model.refresh()
        let leftover = try #require(model.rows.first { $0.item.label == "com.google.keystone.agent" })
        #expect(leftover.item.problem != nil)
        #expect(leftover.item.schedule == "Ignored")
        #expect(leftover.publisher == "—")
        #expect(await model.setEnabled(leftover, false) != nil)
        #expect(launchctl.commands.isEmpty)
    }

    @Test func filterMatchesLabelCommandOrPublisher() async {
        let (model, _, _) = startup()
        await model.refresh()
        model.filter = "zoom"
        #expect(model.visibleRows.map(\.item.label) == ["us.zoom.updater"])
        model.filter = "PUBLISHER OF /opt"
        #expect(model.visibleRows.map(\.item.label) == ["homebrew.caddy"])
    }

    // MARK: Confirmation

    @Test func clickingTheCheckboxOnlyAsksFirst() async throws {
        let (model, _, launchctl) = startup()
        await model.refresh()
        let row = try #require(model.rows.first { $0.item.label == "com.dropbox.agent" })
        model.requestChange(row, enable: false)
        #expect(model.pendingChange == LaunchItemsModel.PendingChange(row: row, enable: false))
        #expect(launchctl.commands.isEmpty)
    }

    @Test func decliningTheConfirmationRunsNothing() async throws {
        let (model, _, launchctl) = startup()
        await model.refresh()
        let row = try #require(model.rows.first { $0.item.label == "com.dropbox.agent" })
        model.requestChange(row, enable: false)
        model.cancelChange()
        #expect(model.pendingChange == nil)
        #expect(launchctl.commands.isEmpty)
    }

    @Test func confirmingRunsTheChangeAndClearsTheRequest() async throws {
        let (model, _, launchctl) = startup()
        await model.refresh()
        let row = try #require(model.rows.first { $0.item.label == "homebrew.caddy" })
        model.requestChange(row, enable: true)
        let change = try #require(model.pendingChange)
        let error = await model.confirm(change)
        #expect(error == nil)
        #expect(model.pendingChange == nil)
        #expect(launchctl.commands == [["enable", "gui/501/homebrew.caddy"],
                                       ["bootstrap", "gui/501", "\(home)/homebrew.caddy.plist"]])
    }

    /// Agents in /Library/LaunchAgents run in each user's own session, not the system domain.
    @Test func anAllUsersAgentChangesInThisUsersSession() async throws {
        let (model, _, launchctl) = startup()
        await model.refresh()
        let row = try #require(model.rows.first { $0.item.label == "us.zoom.updater" })
        #expect(row.item.scope == .allUsersAgent)
        _ = await model.setEnabled(row, false)
        #expect(launchctl.commands == [["disable", "gui/501/us.zoom.updater"],
                                       ["bootout", "gui/501/us.zoom.updater"]])
    }
}
