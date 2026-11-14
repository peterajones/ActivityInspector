import Foundation
import Security

/// Where a launchd job comes from, which decides its domain and who may change it.
enum LaunchScope: Hashable, Sendable {
    /// ~/Library/LaunchAgents: this user's.
    case userAgent
    /// /Library/LaunchAgents: loaded for every user who logs in.
    case allUsersAgent
    /// /Library/LaunchDaemons: system-wide, started at boot, run as root.
    case daemon
    /// /System/Library/LaunchDaemons: macOS's own.
    case appleDaemon

    var isAgent: Bool { self == .userAgent || self == .allUsersAgent }

    var locationText: String {
        switch self {
        case .userAgent: "Just me"
        case .allUsersAgent: "All users"
        case .daemon: "/Library/LaunchDaemons"
        case .appleDaemon: "/System/Library/LaunchDaemons"
        }
    }

    /// The launchd domain its jobs live in.
    nonisolated func domain(uid: uid_t) -> String {
        isAgent ? "gui/\(uid)" : "system"
    }
}

/// When a job runs, in plain words, from its property list.
enum LaunchSchedule {
    nonisolated static func describe(_ plist: [String: Any], scope: LaunchScope) -> String {
        if let keepAlive = plist["KeepAlive"], (keepAlive as? Bool) ?? true { return "Kept running" }
        if plist["RunAtLoad"] as? Bool == true { return scope.isAgent ? "At login" : "At startup" }
        if let seconds = plist["StartInterval"] as? Int, seconds > 0 { return "Every " + interval(seconds) }
        if plist["StartCalendarInterval"] != nil { return "On a schedule" }
        if plist["WatchPaths"] != nil || plist["QueueDirectories"] != nil { return "When files change" }
        return "On demand"
    }

    private nonisolated static func interval(_ seconds: Int) -> String {
        func unit(_ count: Int, _ name: String) -> String { count == 1 ? name : "\(count) \(name)s" }
        if seconds % 3_600 == 0 { return unit(seconds / 3_600, "hour") }
        if seconds % 60 == 0 { return unit(seconds / 60, "minute") }
        return unit(seconds, "second")
    }
}

/// A file's size, dates, owner and permissions, for the detail pane.
struct FileFacts: Equatable, Sendable {
    let size: UInt64
    let modified: Date?
    let created: Date?
    let owner: String
    let permissions: Int

    /// "-rw-r--r-- (644)", as `ls -l` shows it.
    nonisolated static func permissionsText(_ mode: Int) -> String {
        let letters = Array("rwxrwxrwx")
        let bits = (0..<9).map { mode & (1 << (8 - $0)) != 0 ? letters[$0] : "-" }
        return "-" + String(bits) + " (" + String(mode & 0o777, radix: 8) + ")"
    }
}

/// One launchd property list.
struct LaunchItem: Identifiable, Equatable, Sendable {
    /// The property list's path.
    let id: String
    let label: String
    let scope: LaunchScope
    let program: String?
    let arguments: [String]
    let schedule: String
    let disabledInFile: Bool
    var facts: FileFacts? = nil
    /// Why launchd ignores this file (no Label, unreadable); nil for a real job.
    var problem: String? = nil

    var plistPath: String { id }

    /// The program and its arguments (the first argument is the program's own name, so the
    /// program stands in for it).
    var commandLine: String {
        guard let program else { return arguments.joined(separator: " ") }
        return ([program] + arguments.dropFirst()).joined(separator: " ")
    }

    /// A file in a launchd folder that launchd ignores: listed under its file name, so leftovers
    /// from removed apps can be found.
    nonisolated static func ignored(path: String, scope: LaunchScope, readable: Bool) -> LaunchItem {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return LaunchItem(id: path, label: name, scope: scope, program: nil, arguments: [], schedule: "Ignored",
                          disabledInFile: false,
                          problem: readable ? "Not a valid launchd job (it has no Label), so macOS ignores it."
                                            : "macOSmonitor couldn’t read this file.")
    }

    /// Nil for a file that isn't a launchd job (no Label).
    nonisolated static func parse(_ plist: [String: Any], path: String, scope: LaunchScope) -> LaunchItem? {
        guard let label = plist["Label"] as? String else { return nil }
        let arguments = plist["ProgramArguments"] as? [String] ?? []
        return LaunchItem(id: path, label: label, scope: scope,
                          program: plist["Program"] as? String ?? arguments.first,
                          arguments: arguments,
                          schedule: LaunchSchedule.describe(plist, scope: scope),
                          disabledInFile: plist["Disabled"] as? Bool ?? false)
    }
}

/// Reads `launchctl`'s text output.
enum LaunchctlOutput {
    struct Service: Equatable, Sendable {
        /// Nil when it isn't running.
        let pid: Int?
        /// Its last exit status, when it exited with one.
        let lastExit: Int?
    }

    /// The `services = { … }` block of `launchctl print <domain>`: "pid  last-exit  label" per line.
    nonisolated static func services(_ text: String) -> [String: Service] {
        var services: [String: Service] = [:]
        var inBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("services = {"), !trimmed.hasPrefix("disabled") { inBlock = true; continue }
            guard inBlock else { continue }
            if trimmed == "}" { inBlock = false; continue }
            let fields = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 3, let pid = Int(fields[0]) else { continue }
            services[fields[2...].joined(separator: " ")] = Service(pid: pid > 0 ? pid : nil, lastExit: Int(fields[1]))
        }
        return services
    }

    /// `launchctl print-disabled <domain>`: label → enabled.
    nonisolated static func overrides(_ text: String) -> [String: Bool] {
        var overrides: [String: Bool] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.components(separatedBy: "\" => ")
            guard parts.count == 2, let label = parts[0].split(separator: "\"").last else { continue }
            overrides[String(label)] = parts[1].trimmingCharacters(in: .whitespaces) == "enabled"
        }
        return overrides
    }
}

/// Who signed a program, from its code signature.
enum CodePublisher {
    /// "Developer ID Application: Google LLC (EQHXZ8M8AV)" → "Google LLC"; Apple's own
    /// "Software Signing" → "Apple"; anything else as it is.
    nonisolated static func name(fromCertificateSummary summary: String) -> String {
        if summary == "Software Signing" || summary.hasPrefix("Apple ") && !summary.contains(": ") { return "Apple" }
        guard let colon = summary.range(of: ": ") else { return summary }
        var name = String(summary[colon.upperBound...])
        if let team = name.range(of: " (", options: .backwards), name.hasSuffix(")") {
            name = String(name[..<team.lowerBound])
        }
        return name
    }

    static let unsigned = "Unsigned"
    static let missing = "Program missing"
    static let uncheckable = "Can’t be checked"

    /// Results that mean the signature wasn't verified: the table flags them.
    nonisolated static func isUnverified(_ publisher: String) -> Bool {
        [unsigned, missing, uncheckable].contains(publisher)
    }

    /// "Apple", a developer's name, "Unsigned", "Can’t be checked" (not readable), or "Program missing".
    nonisolated static func publisher(ofProgramAt path: String) -> String {
        guard FileManager.default.fileExists(atPath: path) else { return missing }
        // Privileged helpers are often execute-only: unreadable isn't the same as unsigned.
        guard FileManager.default.isReadableFile(atPath: path) else { return uncheckable }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return unsigned }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return unsigned }
        if dictionary[kSecCodeInfoPlatformIdentifier as String] != nil { return "Apple" }
        guard let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String?
        else { return unsigned }
        return name(fromCertificateSummary: summary)
    }
}

/// launchd's property lists on disk; behind a protocol so the model is testable.
protocol LaunchFilesProviding: Sendable {
    func plists(in directory: String) -> [String]
    func contents(of path: String) -> [String: Any]?
    func facts(of path: String) -> FileFacts?
}

struct LaunchFiles: LaunchFilesProviding {
    func plists(in directory: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.filter { $0.hasSuffix(".plist") }.sorted().map { directory + "/" + $0 }
    }

    func contents(of path: String) -> [String: Any]? {
        NSDictionary(contentsOfFile: path) as? [String: Any]
    }

    func facts(of path: String) -> FileFacts? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let owner = [attributes[.ownerAccountName], attributes[.groupOwnerAccountName]]
            .compactMap { $0 as? String }.joined(separator: ":")
        return FileFacts(size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                         modified: attributes[.modificationDate] as? Date,
                         created: attributes[.creationDate] as? Date,
                         owner: owner,
                         permissions: (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0)
    }
}

/// Runs `launchctl`; behind a protocol so tests never touch the real launchd.
protocol LaunchctlRunning: Sendable {
    /// The command's standard output, or nil when it couldn't run.
    func output(_ arguments: [String]) async -> String?
    /// The command's exit status (-1 when it couldn't run).
    func run(_ arguments: [String]) async -> Int32
}

struct Launchctl: LaunchctlRunning {
    private static let path = "/bin/launchctl"

    func output(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            // Read to end of file on a GCD thread; no waitUntilExit() (see CLAUDE.md).
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: Self.path)
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }

    func run(_ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.path)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            // The termination handler, not waitUntilExit(): it can't miss the exit.
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
