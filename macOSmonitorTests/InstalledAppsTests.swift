import Testing
import Foundation
import Synchronization
@testable import macOSmonitor

/// Installed Apps: system_profiler's Applications data as rows, how each is described, and
/// which are listed.
struct InstalledAppsParserTests {
    static let json = """
        {"SPApplicationsDataType":[
          {"_name":"Safari","arch_kind":"arch_arm_i64","lastModified":"2026-11-06T05:22:11Z","obtained_from":"apple",
           "path":"/Applications/Safari.app","signed_by":["Software Signing","Apple Code Signing Certification Authority","Apple Root CA"],
           "version":"26.2","info":"26.2, Copyright © 2003-2026 Apple Inc."},
          {"_name":"Google Chrome","arch_kind":"arch_arm","lastModified":"2026-11-10T18:00:00Z","obtained_from":"identified_developer",
           "path":"/Applications/Google Chrome.app","signed_by":["Developer ID Application: Google LLC (EQHXZ8M8AV)","Developer ID Certification Authority","Apple Root CA"],
           "version":"142.0.1"},
          {"_name":"Kindle","arch_kind":"arch_arm","lastModified":"2026-01-02T03:04:05Z","obtained_from":"mac_app_store",
           "path":"/Applications/Kindle.app","signed_by":["Apple Mac OS Application Signing","Apple Worldwide Developer Relations Certification Authority","Apple Root CA"],
           "version":"7.4"},
          {"_name":"Old Game","arch_kind":"arch_i64","lastModified":"2019-05-05T05:05:05Z","obtained_from":"unknown",
           "path":"/Users/u/Applications/Old Game.app"},
          {"_name":"Ticket Viewer","arch_kind":"arch_arm","lastModified":"2026-11-06T05:22:11Z","obtained_from":"apple",
           "path":"/System/Library/CoreServices/Ticket Viewer.app","version":"4.2"}
        ]}
        """

    private func apps() throws -> [InstalledApp] {
        try #require(InstalledAppsParser.parse(Data(Self.json.utf8)))
    }

    @Test func everyAppBecomesARowInTheToolsOrder() throws {
        let apps = try apps()
        #expect(apps.map(\.name) == ["Safari", "Google Chrome", "Kindle", "Old Game", "Ticket Viewer"])
        let safari = apps[0]
        #expect(safari.id == "/Applications/Safari.app")
        #expect(safari.version == "26.2")
        #expect(safari.info == "26.2, Copyright © 2003-2026 Apple Inc.")
        #expect(safari.signedBy.count == 3)
        #expect(safari.modified == ISO8601DateFormatter().date(from: "2026-11-06T05:22:11Z"))
        #expect(apps[3].version == nil)
        #expect(apps[3].signedBy.isEmpty)
    }

    @Test func unreadableOutputIsNil() {
        #expect(InstalledAppsParser.parse(Data("nope".utf8)) == nil)
        #expect(InstalledAppsParser.parse(Data(#"{"SPAudioDataType":[]}"#.utf8)) == nil)
        #expect(InstalledAppsParser.parse(Data(#"{"SPApplicationsDataType":[]}"#.utf8)) == [])
    }

    @Test func kindsInPlainWords() {
        #expect(AppKind(profilerValue: "arch_arm") == .appleSilicon)
        #expect(AppKind(profilerValue: "arch_arm_i64") == .universal)
        #expect(AppKind(profilerValue: "arch_i64") == .intel)
        #expect(AppKind(profilerValue: "arch_i32") == .intel32)
        #expect(AppKind(profilerValue: "arch_ios") == .iOS)
        #expect(AppKind(profilerValue: "arch_something_new") == .other)
        #expect([AppKind.appleSilicon, .universal, .intel, .intel32, .iOS, .other].map(\.text)
                == ["Apple silicon", "Universal", "Intel", "Intel (32-bit)", "iPhone/iPad", "Other"])
    }

    /// Intel-only apps run under Rosetta, which Apple is phasing out: the table flags them.
    @Test func onlyIntelOnlyAppsNeedRosetta() {
        #expect(AppKind.intel.needsRosetta && AppKind.intel32.needsRosetta)
        #expect(![AppKind.appleSilicon, .universal, .iOS, .other].contains { $0.needsRosetta })
    }

    @Test func originsInPlainWords() {
        #expect(AppOrigin(profilerValue: "apple") == .apple)
        #expect(AppOrigin(profilerValue: "mac_app_store") == .appStore)
        #expect(AppOrigin(profilerValue: "identified_developer") == .identifiedDeveloper)
        #expect(AppOrigin(profilerValue: "unknown") == .unknown)
        #expect(AppOrigin(profilerValue: "something_new") == .unknown)
        #expect([AppOrigin.apple, .appStore, .identifiedDeveloper, .unknown].map(\.text)
                == ["Apple", "App Store", "Identified developer", "Unknown"])
        #expect(AppOrigin.unknown.isFlagged && ![AppOrigin.apple, .appStore, .identifiedDeveloper].contains { $0.isFlagged })
    }

    /// App Store apps are all signed by Apple's App Store certificate, which doesn't name the
    /// developer: saying "Apple" would be wrong.
    @Test func publisherComesFromTheSignatureButNotForAppStoreApps() throws {
        let apps = try apps()
        #expect(apps.map(\.publisher) == ["Apple", "Google LLC", "—", CodePublisher.unsigned, "Apple"])
    }

    @Test func aDevelopmentSignatureNamesItsDeveloper() {
        let app = InstalledApp(id: "/Applications/Mine.app", name: "Mine", version: nil, kind: .appleSilicon,
                               origin: .unknown, signedBy: ["Apple Development: Pat Example (ABCDE12345)"],
                               modified: nil, info: nil)
        #expect(app.publisher == "Pat Example")
    }

    /// Listed by default: the Applications folders, and apps that ship inside another app's
    /// Contents/Applications (Xcode's Instruments); not system helpers, build products or helpers
    /// tucked inside other apps.
    @Test(arguments: [
        ("/Applications/Safari.app", true),
        ("/System/Applications/Mail.app", true),
        ("/Users/u/Applications/Old Game.app", true),
        ("/Applications/Utilities/Terminal.app", true),
        ("/Applications/Xcode.app/Contents/Applications/Instruments.app", true),
        ("/Applications/Foo.app/Contents/Library/LoginItems/FooHelper.app", false),
        ("/System/Library/CoreServices/Ticket Viewer.app", false),
        ("/Users/u/Library/Developer/Xcode/DerivedData/X/Build/Products/Debug/X.app", false),
        ("/Users/other/Applications/Theirs.app", false),
        ("/ApplicationsExtra/Thing.app", false),
    ])
    func installedMeansInAnApplicationsFolder(path: String, installed: Bool) {
        #expect(InstalledApp.isInstalled(path: path, home: "/Users/u") == installed)
    }
}

final class FakeAppSizer: AppSizing, @unchecked Sendable {
    private let lock = NSLock()
    var sizes: [String: UInt64] = [:]
    /// When set, every size waits for a signal, so a test can see the list before sizes arrive.
    var gate: DispatchSemaphore?
    private var _asked: [String] = []
    var asked: [String] { lock.withLock { _asked } }

    func size(ofAppAt path: String) -> UInt64? {
        lock.withLock { _asked.append(path) }
        _ = gate?.wait(timeout: .now() + 5)
        return sizes[path]
    }
}

@MainActor
struct InstalledAppsModelTests {
    private func model(sizer: FakeAppSizer = FakeAppSizer()) -> (InstalledAppsModel, FakeProfilerRunner) {
        let runner = FakeProfilerRunner()
        runner.outputs["SPApplicationsDataType"] = Data(InstalledAppsParserTests.json.replacingOccurrences(
            of: "/Users/u/", with: "/Users/me/").utf8)
        return (InstalledAppsModel(runner: runner, sizer: sizer, home: "/Users/me", linkedApps: { _ in [] }), runner)
    }

    @Test func readsOnceWhenFirstShown() async {
        let (model, runner) = model()
        #expect(model.status == .idle)
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        #expect(runner.calls == ["SPApplicationsDataType"])
        #expect(model.status == .loaded)
        #expect(model.apps.count == 5)
    }

    @Test func reloadReadsAgain() async {
        let (model, runner) = model()
        await model.loadIfNeeded()
        await model.reload()
        #expect(runner.calls.count == 2)
    }

    @Test func aFailedReadSaysSo() async {
        let runner = FakeProfilerRunner()
        let model = InstalledAppsModel(runner: runner, sizer: FakeAppSizer(), home: "/Users/me", linkedApps: { _ in [] })
        await model.loadIfNeeded()
        #expect(model.status == .failed)
        #expect(model.visibleRows.isEmpty)
    }

    @Test func installedAppsOnlyUntilAskedForAll() async {
        let (model, _) = model()
        await model.loadIfNeeded()
        #expect(Set(model.visibleRows.map(\.name)) == ["Safari", "Google Chrome", "Kindle", "Old Game"])
        model.showsAllApps = true
        #expect(model.visibleRows.count == 5)
    }

    @Test func sortedByNameUntilAnotherColumnIsChosen() async {
        let (model, _) = model()
        await model.loadIfNeeded()
        #expect(model.visibleRows.map(\.name) == ["Google Chrome", "Kindle", "Old Game", "Safari"])
        model.sortOrder = [KeyPathComparator(\InstalledAppRow.modifiedSort, order: .reverse)]
        #expect(model.visibleRows.map(\.name) == ["Google Chrome", "Safari", "Kindle", "Old Game"])
        model.sortOrder = [KeyPathComparator(\InstalledAppRow.kindText)]
        #expect(model.visibleRows.map(\.kindText) == ["Apple silicon", "Apple silicon", "Intel", "Universal"])
    }

    @Test func filterMatchesNamePublisherOrPath() async {
        let (model, _) = model()
        await model.loadIfNeeded()
        model.filter = "google llc"
        #expect(model.visibleRows.map(\.name) == ["Google Chrome"])
        model.filter = "/users/me"
        #expect(model.visibleRows.map(\.name) == ["Old Game"])
        model.filter = "kind"
        #expect(model.visibleRows.map(\.name) == ["Kindle"])
    }

    /// The list shows straight away; sizes fill in afterwards, installed apps first.
    @Test func sizesFillInAfterTheListWithoutHoldingItUp() async throws {
        let sizer = FakeAppSizer()
        sizer.sizes = ["/Applications/Safari.app": 15_000_000, "/Applications/Kindle.app": 300_000_000]
        let gate = DispatchSemaphore(value: 0)
        sizer.gate = gate
        let (model, _) = model(sizer: sizer)
        await model.loadIfNeeded()
        #expect(model.apps.count == 5)                         // listed while sizing waits
        #expect(model.sizes.isEmpty)
        #expect(model.visibleRows.allSatisfy { $0.size == nil && $0.sizeSort == 0 })
        for _ in 0..<5 { gate.signal() }
        await model.sizingTask?.value
        #expect(model.sizes == ["/Applications/Safari.app": 15_000_000, "/Applications/Kindle.app": 300_000_000])
        #expect(model.visibleRows.first { $0.name == "Kindle" }?.size == 300_000_000)
        #expect(Set(sizer.asked.prefix(4)) == Set(model.apps.filter { $0.name != "Ticket Viewer" }.map(\.id)))
        model.sortOrder = [KeyPathComparator(\InstalledAppRow.sizeSort, order: .reverse)]
        #expect(model.visibleRows.prefix(2).map(\.name) == ["Kindle", "Safari"])
    }

    /// system_profiler skips links, and Safari in /Applications is a link into the system's
    /// Cryptex volume: such apps are added from their bundles, once each.
    @Test func linkedAppsTheToolSkipsAreAddedOnce() async {
        let runner = FakeProfilerRunner()
        runner.outputs["SPApplicationsDataType"] = Data(InstalledAppsParserTests.json.utf8)
        let linkedSafari = InstalledApp(id: "/Applications/Safari.app", name: "Safari", version: "26.2", kind: .universal,
                                        origin: .apple, signedBy: [], modified: nil, info: nil)
        let notes = InstalledApp(id: "/Applications/Notes Link.app", name: "Notes Link", version: "5", kind: .appleSilicon,
                                 origin: .apple, signedBy: [], modified: nil, info: nil)
        let askedHome = Mutex<String?>(nil)
        let model = InstalledAppsModel(runner: runner, sizer: FakeAppSizer(), home: "/Users/u",
                                       linkedApps: { home in askedHome.withLock { $0 = home }; return [linkedSafari, notes] })
        await model.loadIfNeeded()
        #expect(askedHome.withLock { $0 } == "/Users/u")
        #expect(model.apps.filter { $0.name == "Safari" }.count == 1)    // already listed: not twice
        #expect(model.apps.last?.name == "Notes Link")
    }

    @Test func theSelectedRowFollowsTheSelection() async {
        let (model, _) = model()
        await model.loadIfNeeded()
        model.selection = "/Applications/Kindle.app"
        #expect(model.selectedRow?.name == "Kindle")
        model.selection = nil
        #expect(model.selectedRow == nil)
    }
}

/// Against this Mac: a real bundle's size is its files' total.
struct AppSizerTests {
    @Test func aBundlesSizeIsItsFilesTotal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sizer-\(UUID().uuidString).app")
        let contents = root.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(count: 100_000).write(to: contents.appendingPathComponent("Tool"))
        try Data(count: 50_000).write(to: root.appendingPathComponent("Contents/Info.plist"))
        let size = try #require(AppSizer().size(ofAppAt: root.path))
        #expect(size >= 150_000)
        #expect(size < 200_000)
    }

    @Test func aMissingAppHasNoSize() {
        #expect(AppSizer().size(ofAppAt: "/nonexistent-\(UUID().uuidString).app") == nil)
    }
}

struct InstalledAppsNavigationTests {
    @Test func theSidebarListsInstalledAppsAfterSystemInfo() {
        #expect(SidebarItem.allCases == [.summary, .performance, .processes, .ports, .systemInfo, .installedApps,
                                         .startupApps, .services])
        #expect(SidebarItem.installedApps.title == "Installed Apps")
        #expect(SidebarItem.installedApps.surface(lastMetric: .cpu, available: [.cpu]) == .installedApps)
        #expect(Surface.installedApps.sidebarItem == .installedApps)
        #expect(Surface.installedApps.metric == nil)
    }
}

/// Against this Mac's own list: the real tool's output parses, and Mail is installed.
struct InstalledAppsSystemTests {
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/sbin/system_profiler")))
    func thisMacsAppsParse() async throws {
        let data = try #require(await SystemProfilerRunner().run("SPApplicationsDataType"))
        let apps = try #require(InstalledAppsParser.parse(data))
        let installed = apps.filter { InstalledApp.isInstalled(path: $0.path, home: NSHomeDirectory()) }
        #expect(apps.count > installed.count)                   // some aren't in an Applications folder
        let mail = try #require(installed.first { $0.path == "/System/Applications/Mail.app" })
        #expect(mail.origin == .apple)
        #expect(mail.publisher == "Apple")
        #expect(mail.kind != .other)
        #expect(mail.version != nil && mail.modified != nil)
    }
}

/// Against this Mac: Safari is a link into the Cryptex volume, found and read from its bundle.
struct InstalledAppLinksTests {
    @Test(.enabled(if: (try? FileManager.default.destinationOfSymbolicLink(atPath: "/Applications/Safari.app")) != nil))
    func safariIsFoundThroughItsLink() throws {
        let safari = try #require(InstalledAppLinks.find(home: NSHomeDirectory()).first { $0.name == "Safari" })
        #expect(safari.path == "/Applications/Safari.app")
        #expect(safari.origin == .apple)
        #expect(safari.publisher == "Apple")
        #expect(safari.kind == .appleSilicon || safari.kind == .universal)
        #expect(safari.version != nil)
        #expect(safari.modified != nil)
    }

    @Test func plainBundlesAndOutsideLinksArentAdded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("links-\(UUID().uuidString)")
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("Plain.app"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: apps.appendingPathComponent("Elsewhere.app").path,
                                                   withDestinationPath: apps.appendingPathComponent("Plain.app").path)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(InstalledAppLinks.find(home: root.path).filter { $0.path.hasPrefix(root.path) }.isEmpty)
    }

    @Test(arguments: [
        ([0x0100000c], AppKind.appleSilicon),
        ([0x0100000c, 0x01000007], .universal),
        ([0x01000007], .intel),
        ([], .other),
    ])
    func kindFromTheExecutablesArchitectures(architectures: [Int], kind: AppKind) {
        #expect(InstalledAppLinks.kind(architectures: architectures) == kind)
    }
}
