import Testing
import Foundation
@testable import ActivityInspector

/// In the App Sandbox, NSHomeDirectory() is the app's container
/// (~/Library/Containers/<id>/Data; probed 2026-11-15), so anything that means the user's own
/// folders (their LaunchAgents and Applications, the "~" in reports) reads the real home from
/// the user database instead.
struct UserHomeTests {
    @Test func theUserDatabaseWinsOverTheContainer() {
        #expect(UserHome.resolve(databaseHome: "/Users/pat",
                                 processHome: "/Users/pat/Library/Containers/ca.example/Data") == "/Users/pat")
    }

    @Test func withoutADatabaseEntryTheProcessHomeIsUsed() {
        #expect(UserHome.resolve(databaseHome: nil, processHome: "/Users/pat") == "/Users/pat")
        #expect(UserHome.resolve(databaseHome: "", processHome: "/Users/pat") == "/Users/pat")
    }

    @Test func thisMacsHomeIsTheUserDatabasesEntry() throws {
        let entry = try #require(getpwuid(getuid()))
        #expect(UserHome.path == String(cString: entry.pointee.pw_dir))
    }

    @Test func reportsReplaceTheRealHome() {
        #expect(IdentifyingNames.thisMac().home == UserHome.path)
    }

    /// Only UserHome asks the process for its home: anywhere else would get the container in the
    /// App Store edition.
    @Test func nothingElseAsksTheProcessForItsHome() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("ActivityInspector")
        var offenders: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path)
        where name.hasSuffix(".swift") && name != "UserHome.swift" {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                if line.contains("NSHomeDirectory()") || line.contains("homeDirectoryForCurrentUser") {
                    offenders.append("\(name): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
