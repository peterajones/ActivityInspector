import Foundation

/// The user's real home folder. In the App Sandbox, `NSHomeDirectory()` is the app's container
/// (~/Library/Containers/<id>/Data, probed 2026-11-15), so the user's own LaunchAgents and
/// Applications folders, and the "~" in reports, come from the user database instead.
/// The only place in the app that asks the process for its home.
enum UserHome {
    nonisolated static var path: String {
        resolve(databaseHome: getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) },
                processHome: NSHomeDirectory())
    }

    /// The user database's entry, else the process's own idea.
    nonisolated static func resolve(databaseHome: String?, processHome: String) -> String {
        guard let databaseHome, !databaseHome.isEmpty else { return processHome }
        return databaseHome
    }
}
