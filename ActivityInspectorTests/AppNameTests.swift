import Testing
import Foundation
@testable import ActivityInspector

/// The app was called macOSmonitor until 2026-11-16. "Mac" and "macOS" are Apple trademarks, so
/// it became Activity Inspector everywhere: the name users read, the bundle ID, the helper's
/// identifiers, and the code.
///
/// The test host is the Debug app, which since 2026-11-16 is a separate app to macOS:
/// `ca.peter-jones.ActivityInspector.dev`, "Activity Inspector Dev", its own helper label. Release
/// keeps the plain names; `scripts/helper-launchd-plist.sh` refuses a Release build that doesn't.
struct AppNameTests {
    static let oldName = "macOS" + "monitor"

    @Test func thePublicNameIsActivityInspector() {
        #expect(AppName.display == "Activity Inspector")
    }

    /// The display name ("About/Hide/Quit Activity Inspector Dev") says Dev. CFBundleName, the bold
    /// menu-bar title, always comes from PRODUCT_NAME in a generated Info.plist (Xcode overrides an
    /// INFOPLIST_FILE value, checked 2026-11-16), and PRODUCT_NAME is the same in both
    /// configurations, so the title, the .app and the process keep the plain name.
    @Test func theBuiltAppCarriesTheDevName() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == AppName.display)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Activity Inspector Dev")
        #expect(Bundle.main.bundleURL.lastPathComponent == "\(AppName.display).app")
    }

    @Test func theBundleIDIsTheDevOne() {
        #expect(Bundle.main.bundleIdentifier == "ca.peter-jones.ActivityInspector.dev")
        #expect(HelperConstants.isDebugBuild)
    }

    /// The bundle ID comes from a build setting and the helper's names from `#if DEBUG`; this ties
    /// the two together so they can't drift apart.
    @Test func machServiceIsTheBundleIDPlusHelper() {
        #expect(Bundle.main.bundleIdentifier.map { $0 + ".helper" } == HelperConstants.machServiceName)
    }

    /// The launchd property list is generated at build time from the bundle ID; it must name the
    /// same service the app connects to and the helper listens on.
    @Test func theBundledPlistMatchesHelperConstants() throws {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let helper = contents.appendingPathComponent("MacOS/ActivityInspectorHelper")
        #expect(FileManager.default.isExecutableFile(atPath: helper.path))
        let url = contents.appendingPathComponent("Library/LaunchDaemons/\(HelperConstants.plistName)")
        let plist = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        #expect(plist["Label"] as? String == HelperConstants.machServiceName)
        #expect((plist["MachServices"] as? [String: Bool]).map { Array($0.keys) } == [HelperConstants.machServiceName])
        #expect(plist["BundleProgram"] as? String == "Contents/MacOS/ActivityInspectorHelper")
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == [try #require(Bundle.main.bundleIdentifier)])
    }

    /// A plist left behind by an earlier build (another configuration, or the hand-written file
    /// used before 2026-11-16) would register a second, stale helper.
    @Test func exactlyOneLaunchdPlistIsBundled() throws {
        let folder = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [HelperConstants.plistName])
    }

    /// Nothing in the app's or the helper's code still says the old name.
    @Test func noSourceFileSaysTheOldName() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []
        for folder in ["ActivityInspector", "ActivityInspectorHelper"] {
            let dir = root.appendingPathComponent(folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path)
            where name.hasSuffix(".swift") || name.hasSuffix(".plist") {
                let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
                if name.contains(Self.oldName) || text.contains(Self.oldName) { offenders.append("\(folder)/\(name)") }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
