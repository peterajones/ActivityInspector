import Testing
import Foundation
@testable import ActivityInspector

/// The app was called macOSmonitor until 2026-11-16. "Mac" and "macOS" are Apple trademarks, so
/// it became Activity Inspector everywhere: the name users read, the bundle ID, the helper's
/// identifiers, and the code.
struct AppNameTests {
    static let oldName = "macOS" + "monitor"

    @Test func thePublicNameIsActivityInspector() {
        #expect(AppName.display == "Activity Inspector")
    }

    /// The bundle's own name is what the app menu, Dock, Finder and Login Items show; it comes
    /// from the target's PRODUCT_NAME. The test host is the app, so Bundle.main is its bundle.
    @Test func theBuiltAppCarriesThePublicName() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == AppName.display)
        #expect(Bundle.main.bundleURL.lastPathComponent == "\(AppName.display).app")
    }

    @Test func theBundleIDIsActivityInspectors() {
        #expect(Bundle.main.bundleIdentifier == "ca.peter-jones.ActivityInspector")
    }

    /// The app embeds the helper and its launchd property list under the new names.
    @Test func theBundledHelperCarriesTheNewNames() {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let helper = contents.appendingPathComponent("MacOS/ActivityInspectorHelper")
        let plist = contents.appendingPathComponent("Library/LaunchDaemons/\(HelperConstants.machServiceName).plist")
        #expect(FileManager.default.isExecutableFile(atPath: helper.path))
        #expect(FileManager.default.fileExists(atPath: plist.path))
        #expect(HelperConstants.machServiceName == "ca.peter-jones.ActivityInspector.helper")
    }

    /// Nothing in the app's or the helper's code still says the old name.
    @Test func noSourceFileSaysTheOldName() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []
        for folder in ["ActivityInspector", "ActivityInspectorHelper", "LaunchDaemons"] {
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
