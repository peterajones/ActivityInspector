import Testing
import Foundation
@testable import ActivityInspector

/// System Info as text: one item for Copy, every item for Export Report…, identifying values
/// left out unless asked for.
struct SystemInfoReportTests {
    private func leaf(_ title: String, _ value: String, sensitive: Bool = false) -> ProfilerNode {
        ProfilerNode(id: title, title: title, value: value, children: [], isSensitive: sensitive)
    }

    private func group(_ title: String, _ children: [ProfilerNode]) -> ProfilerNode {
        ProfilerNode(id: title, title: title, value: nil, children: children)
    }

    private var hardware: [ProfilerNode] {
        [group("Hardware Overview", [
            leaf("Chip", "Apple M3 Pro"),
            leaf("Memory", "36 GB"),
            leaf("Serial number", "C02XK1ABJG5J", sensitive: true),
            group("Battery", [leaf("Serial", "F5D", sensitive: true)]),
        ])]
    }

    private let item = SystemInfoItem.catalog[0]   // Hardware Overview

    @Test func anItemReadsAsAnIndentedOutlineUnderItsTitle() {
        let text = SystemInfoReport.text(for: item, nodes: [group("Devices", [
            group("Studio Display Speakers", [leaf("Manufacturer", "Apple Inc."), leaf("Transport", "USB")]),
        ])], includesIdentifying: false)
        #expect(text == """
            Hardware Overview
            =================

            Devices
              Studio Display Speakers
                Manufacturer: Apple Inc.
                Transport: USB

            """)
    }

    /// Safe to paste into a forum post: serials and the like are left out, and a group left
    /// with nothing in it goes too.
    @Test func identifyingValuesAreLeftOutByDefault() {
        let text = SystemInfoReport.text(for: item, nodes: hardware, includesIdentifying: false)
        #expect(text.contains("  Chip: Apple M3 Pro\n"))
        #expect(!text.contains("C02XK1ABJG5J"))
        #expect(!text.contains("Serial"))
        #expect(!text.contains("F5D"))
        #expect(!text.contains("Battery"))
    }

    @Test func identifyingValuesAreIncludedWhenAskedFor() {
        let text = SystemInfoReport.text(for: item, nodes: hardware, includesIdentifying: true)
        #expect(text.contains("  Serial number: C02XK1ABJG5J\n"))
        #expect(text.contains("  Battery\n    Serial: F5D\n"))
    }

    @Test func theReportListsEveryItemWithSomethingToShowByCategory() throws {
        let memory = try #require(SystemInfoItem.catalog.first { $0.id == "SPMemoryDataType" })
        let network = try #require(SystemInfoItem.catalog.first { $0.category == .network })
        let software = try #require(SystemInfoItem.catalog.first { $0.category == .software })
        let fibre = try #require(SystemInfoItem.catalog.first { $0.id == "SPFibreChannelDataType" })
        let states: [String: SystemInfoState] = [
            item.id: .loaded(hardware),
            memory.id: .failed,
            fibre.id: .loaded([]),
            network.id: .loaded([leaf("Name", "Wi-Fi")]),
            software.id: .loaded([leaf("System Version", "macOS 27.2")]),
        ]
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-15T17:30:00Z"))
        let report = SystemInfoReport.report(states: states, includesIdentifying: false, generated: date)
        #expect(report.hasPrefix("System Report from Activity Inspector\n"))
        #expect(report.contains(date.formatted(date: .long, time: .shortened)))
        let order = ["HARDWARE", "Hardware Overview", "Memory", "NETWORK", network.title, "SOFTWARE", software.title]
            .map { try? #require(report.range(of: "\n\($0)\n")?.lowerBound) }
        #expect(order.allSatisfy { $0 != nil })
        #expect(order.compactMap { $0 } == order.compactMap { $0 }.sorted())
        #expect(report.contains("Memory\n======\n\n(couldn’t be read)\n"))
        #expect(!report.contains(fibre.title))                    // nothing to show: left out
        #expect(!report.contains("C02XK1ABJG5J"))
    }

    /// Copy is offered only when there's something to copy.
    @Test func copyNeedsSomethingToCopy() {
        #expect(SystemInfoView.hasContent(.loaded(hardware)))
        #expect(!SystemInfoView.hasContent(.loaded([])))
        #expect(!SystemInfoView.hasContent(.failed))
        #expect(!SystemInfoView.hasContent(.loading))
        #expect(!SystemInfoView.hasContent(nil))
    }

    @Test func aReportWithIdentifyingDetailsSaysSo() {
        let withDetails = SystemInfoReport.report(states: [item.id: .loaded(hardware)], includesIdentifying: true,
                                                  generated: Date(timeIntervalSince1970: 0))
        let without = SystemInfoReport.report(states: [item.id: .loaded(hardware)], includesIdentifying: false,
                                              generated: Date(timeIntervalSince1970: 0))
        #expect(withDetails.contains("C02XK1ABJG5J"))
        #expect(withDetails.contains("includes identifying details"))
        #expect(without.contains("Identifying details (serial numbers, hardware IDs, addresses, network names, user and computer names) are left out."))
    }

    // MARK: Names that turn up anywhere (security review, 2026-11-15)

    private let names = IdentifyingNames(home: "/Users/pat", userName: "pat", fullName: "Pat Example",
                                         computerNames: ["Pat’s MacBook Pro", "Pats-MacBook-Pro"])

    @Test func namesAreReplacedWhereverTheyAppear() {
        #expect(names.scrub("/Users/pat/Applications/Game.app") == "~/Applications/Game.app")
        #expect(names.scrub("Pat’s MacBook Pro") == "<this Mac>")
        #expect(names.scrub("kernel on Pats-MacBook-Pro.local: user pat logged in") == "kernel on <this Mac>.local: user <user> logged in")
        #expect(names.scrub("Owner: Pat Example") == "Owner: <user>")
        #expect(names.scrub("Patterns.app") == "Patterns.app")          // "pat" only as a whole word
        #expect(names.scrub("compatible") == "compatible")
    }

    @Test func aShortOrMissingUserNameIsntReplaced() {
        let short = IdentifyingNames(home: "/Users/al", userName: "al", fullName: "", computerNames: [""])
        #expect(short.scrub("/Users/al/x and also al") == "~/x and also al")
    }

    @Test func theReportScrubsTitlesAndValuesUnlessAskedNotTo() {
        let nodes = [group("Pat’s MacBook Pro", [leaf("Mount Point", "/Volumes/Pat’s MacBook Pro"),
                                                 leaf("Location", "/Users/pat/Applications/Game.app")])]
        let off = SystemInfoReport.text(for: item, nodes: nodes, includesIdentifying: false, names: names)
        #expect(off.contains("<this Mac>\n  Mount Point: /Volumes/<this Mac>\n  Location: ~/Applications/Game.app\n"))
        #expect(!off.contains("pat") && !off.contains("Pat"))
        let on = SystemInfoReport.text(for: item, nodes: nodes, includesIdentifying: true, names: names)
        #expect(on.contains("Pat’s MacBook Pro\n  Mount Point: /Volumes/Pat’s MacBook Pro\n"))
    }

    /// Wi-Fi network names (yours and the neighbours') are group titles, not values.
    @Test func wiFiNetworkNamesAreLeftOutAsTitles() {
        let network = ProfilerNode(id: "n", title: "HomeNet-5G", value: nil,
                                   children: [leaf("Channel", "36")], isSensitive: false, titleIsSensitive: true)
        let off = SystemInfoReport.text(for: item, nodes: [network], includesIdentifying: false, names: names)
        #expect(off.contains("Wi-Fi network\n  Channel: 36\n"))
        #expect(!off.contains("HomeNet"))
        let on = SystemInfoReport.text(for: item, nodes: [network], includesIdentifying: true, names: names)
        #expect(on.contains("HomeNet-5G\n"))
    }
}

@MainActor
struct SystemInfoLoadAllTests {
    private func model() -> (SystemInfoModel, FakeProfilerRunner) {
        let runner = FakeProfilerRunner()
        for item in SystemInfoItem.catalog {
            runner.outputs[item.id] = Data(#"{"\#(item.id)":[{"_name":"x","a":"1"}]}"#.utf8)
        }
        return (SystemInfoModel(runner: runner, labels: ProfilerLabels(table: [:])), runner)
    }

    /// Export reads the slow types too, each once, counting as it goes.
    @Test func loadAllReadsEveryTypeOnceIncludingTheSlowOnes() async {
        let (model, runner) = model()
        await model.load("SPHardwareDataType")
        #expect(model.loadAllProgress == nil)
        await model.loadAll()
        #expect(Set(runner.calls) == Set(SystemInfoItem.catalog.map(\.id)))
        #expect(runner.calls.count == SystemInfoItem.catalog.count)        // Hardware not read twice
        #expect(model.loadAllProgress == nil)                              // finished
        #expect(SystemInfoItem.catalog.allSatisfy {
            if case .loaded = model.state(of: $0.id) { true } else { false }
        })
    }

    /// A type already being read when Export starts (the one just chosen) is waited for, not
    /// skipped.
    @Test func loadAllWaitsForAReadAlreadyUnderway() async {
        let runner = GatedRunner()
        let model = SystemInfoModel(runner: runner, labels: ProfilerLabels(table: [:]))
        let underway = Task { await model.load("SPAirPortDataType") }
        while model.state(of: "SPAirPortDataType") != .loading { await Task.yield() }
        let gate = runner.gate
        let release = Task.detached { try? await Task.sleep(for: .milliseconds(300)); gate.signal() }
        await model.loadAll()
        // Checked the moment Export finishes: Wi-Fi must be in, not still being read.
        if case .loaded = model.state(of: "SPAirPortDataType") {} else { Issue.record("Wi-Fi not read") }
        await release.value
        await underway.value
    }

    /// Each read starts with the count so far showing, out of every type.
    @Test func progressCountsTheTypesRead() async {
        let runner = ProgressRecordingRunner()
        let model = SystemInfoModel(runner: runner, labels: ProfilerLabels(table: [:]))
        runner.progress = { await MainActor.run { model.loadAllProgress } }
        await model.loadAll()
        let seen = runner.seen
        #expect(seen.count == SystemInfoItem.catalog.count)
        #expect(seen.allSatisfy { $0?.total == SystemInfoItem.catalog.count })
        let done = seen.compactMap { $0?.done }
        #expect(done.count == seen.count)
        #expect(done == done.sorted() && done.first == 0 && done.last! < SystemInfoItem.catalog.count)
        #expect(done.last! >= SystemInfoItem.catalog.count - 4)     // four at a time: the last starts near the end
        #expect(SystemInfoLoadAllProgress(done: 3, total: 40).fraction == 0.075)
    }

}

final class ProgressRecordingRunner: SystemProfilerRunning, @unchecked Sendable {
    private let lock = NSLock()
    var progress: (@Sendable () async -> SystemInfoLoadAllProgress?)?
    private var _seen: [SystemInfoLoadAllProgress?] = []
    var seen: [SystemInfoLoadAllProgress?] { lock.withLock { _seen } }

    func run(_ type: String) async -> Data? {
        let now = await progress?() ?? nil
        lock.withLock { _seen.append(now) }
        return Data(#"{"\#(type)":[{"_name":"x","a":"1"}]}"#.utf8)
    }
}

/// Wi-Fi waits for a signal; everything else answers at once.
final class GatedRunner: SystemProfilerRunning, @unchecked Sendable {
    let gate = DispatchSemaphore(value: 0)

    func run(_ type: String) async -> Data? {
        if type == "SPAirPortDataType" {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async { _ = self.gate.wait(timeout: .now() + 5); continuation.resume() }
            }
        }
        return Data(#"{"\#(type)":[{"_name":"x","a":"1"}]}"#.utf8)
    }
}

/// Against this Mac: with identifying details off, the items where names turned up give none away.
struct SystemInfoReportSystemTests {
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/sbin/system_profiler")))
    func thisMacsReportGivesAwayNoNames() async throws {
        let labels = ProfilerLabels.system(languages: ["en"])
        var states: [String: SystemInfoState] = [:]
        for id in ["SPSoftwareDataType", "SPApplicationsDataType", "SPStorageDataType", "SPNetworkDataType", "SPLogsDataType"] {
            let data = try #require(await SystemProfilerRunner().run(id))
            states[id] = .loaded(try #require(ProfilerParser.parse(data, type: id, labels: labels)))
        }
        let names = IdentifyingNames.thisMac()
        let report = SystemInfoReport.report(states: states, includesIdentifying: false, generated: .now, names: names)
        #expect(report.count > 1_000)
        // The Mac's names found independently, not from the code under test.
        let computerName = Host.current().localizedName ?? ""
        let hostName = ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
        #expect(computerName.count >= 3 && hostName.count >= 3)
        for secret in [NSHomeDirectory(), NSUserName(), computerName, hostName] where secret.count >= 3 {
            #expect(!report.contains(secret), "report contains \(secret.count)-character identifying text")
        }
        #expect(report.contains("~/") || report.contains("<this Mac>"))   // something was replaced
    }
}
