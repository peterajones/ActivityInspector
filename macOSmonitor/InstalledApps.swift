import Foundation

/// What an app's code runs on, from system_profiler's `arch_kind`.
enum AppKind: Hashable, Sendable {
    case appleSilicon, universal, intel, intel32, iOS, other

    nonisolated init(profilerValue: String) {
        switch profilerValue {
        case "arch_arm": self = .appleSilicon
        case "arch_arm_i64": self = .universal
        case "arch_i64": self = .intel
        case "arch_i32": self = .intel32
        case "arch_ios": self = .iOS
        default: self = .other
        }
    }

    nonisolated var text: String {
        switch self {
        case .appleSilicon: "Apple silicon"
        case .universal: "Universal"
        case .intel: "Intel"
        case .intel32: "Intel (32-bit)"
        case .iOS: "iPhone/iPad"
        case .other: "Other"
        }
    }

    /// Intel-only code runs under Rosetta, which Apple is phasing out.
    nonisolated var needsRosetta: Bool { self == .intel || self == .intel32 }
}

/// Where an app came from, from system_profiler's `obtained_from`.
enum AppOrigin: Hashable, Sendable {
    case apple, appStore, identifiedDeveloper, unknown

    nonisolated init(profilerValue: String) {
        switch profilerValue {
        case "apple": self = .apple
        case "mac_app_store": self = .appStore
        case "identified_developer": self = .identifiedDeveloper
        default: self = .unknown
        }
    }

    nonisolated var text: String {
        switch self {
        case .apple: "Apple"
        case .appStore: "App Store"
        case .identifiedDeveloper: "Identified developer"
        case .unknown: "Unknown"
        }
    }

    /// Neither Apple's, the App Store's nor a Developer ID's: the table flags it.
    nonisolated var isFlagged: Bool { self == .unknown }
}

/// One app from system_profiler's Applications data.
struct InstalledApp: Identifiable, Equatable, Sendable {
    /// The bundle's path.
    let id: String
    let name: String
    let version: String?
    let kind: AppKind
    let origin: AppOrigin
    /// The signing certificate chain, leaf first; empty when unsigned.
    let signedBy: [String]
    let modified: Date?
    /// The bundle's "get info" line, usually a version and copyright.
    let info: String?

    var path: String { id }

    /// Who made it, from the signature. App Store apps all carry Apple's App Store certificate,
    /// which doesn't name the developer, so they get a dash rather than a wrong "Apple".
    nonisolated var publisher: String {
        switch origin {
        case .apple: return "Apple"
        case .appStore: return "—"
        case .identifiedDeveloper, .unknown:
            guard let leaf = signedBy.first else { return CodePublisher.unsigned }
            return CodePublisher.name(fromCertificateSummary: leaf)
        }
    }

    /// In an Applications folder (/Applications, /System/Applications, the user's own), either
    /// directly or in a subfolder, or shipped in another app's Contents/Applications (Xcode's
    /// Instruments); not a helper tucked elsewhere inside another app.
    nonisolated static func isInstalled(path: String, home: String) -> Bool {
        let roots = ["/Applications/", "/System/Applications/", home + "/Applications/"]
        guard let root = roots.first(where: { path.hasPrefix($0) }) else { return false }
        let inside = path.dropFirst(root.count)
        // Every ".app/" along the way must lead straight into Contents/Applications/.
        var rest = Substring(inside)
        while let bundle = rest.range(of: ".app/") {
            rest = rest[bundle.upperBound...]
            guard rest.hasPrefix("Contents/Applications/") else { return false }
            rest = rest.dropFirst("Contents/Applications/".count)
        }
        return true
    }
}

/// Turns `system_profiler -json SPApplicationsDataType` into apps.
enum InstalledAppsParser {
    nonisolated static func parse(_ data: Data) -> [InstalledApp]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPApplicationsDataType"] as? [[String: Any]] else { return nil }
        let dates = ISO8601DateFormatter()
        return items.compactMap { item in
            guard let path = item["path"] as? String else { return nil }
            return InstalledApp(id: path,
                                name: item["_name"] as? String ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                                version: item["version"] as? String,
                                kind: AppKind(profilerValue: item["arch_kind"] as? String ?? ""),
                                origin: AppOrigin(profilerValue: item["obtained_from"] as? String ?? ""),
                                signedBy: item["signed_by"] as? [String] ?? [],
                                modified: (item["lastModified"] as? String).flatMap(dates.date(from:)),
                                info: item["info"] as? String)
        }
    }
}

/// An app bundle's size on disk; behind a protocol so the model is testable.
protocol AppSizing: Sendable {
    /// Nil when the bundle can't be read.
    func size(ofAppAt path: String) -> UInt64?
}

struct AppSizer: AppSizing {
    /// The allocated size of every file in the bundle, as the Finder's Get Info counts it.
    func size(ofAppAt path: String) -> UInt64? {
        let url = URL(fileURLWithPath: path)
        guard (try? url.checkResourceIsReachable()) == true else { return nil }
        // Folders have no allocated size of their own, so every entry can simply be added up.
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return nil }
        var total: UInt64 = 0
        for case let file as URL in files {
            total += UInt64((try? file.resourceValues(forKeys: Set(keys)))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Apps that system_profiler leaves out because they're links: macOS keeps Safari on its
/// Cryptex volume and links it into /Applications. Only links into /System count, so these are
/// Apple's own.
enum InstalledAppLinks {
    nonisolated static func find(home: String) -> [InstalledApp] {
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", home + "/Applications"]
        let files = FileManager.default
        return folders.flatMap { folder -> [InstalledApp] in
            let names = ((try? files.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".app") }.sorted()
            return names.compactMap { name in
                let link = folder + "/" + name
                guard let destination = try? files.destinationOfSymbolicLink(atPath: link) else { return nil }
                let target = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: folder)).standardizedFileURL
                guard target.path.hasPrefix("/System/"), let bundle = Bundle(url: target) else { return nil }
                let info = bundle.infoDictionary ?? [:]
                return InstalledApp(id: link,
                                    name: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
                                        ?? (name as NSString).deletingPathExtension,
                                    version: info["CFBundleShortVersionString"] as? String,
                                    kind: kind(architectures: bundle.executableArchitectures?.map(\.intValue) ?? []),
                                    origin: .apple, signedBy: [],
                                    modified: (try? target.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                                    info: info["NSHumanReadableCopyright"] as? String)
            }
        }
    }

    /// From `Bundle.executableArchitectures` (NSBundleExecutableArchitecture… values).
    nonisolated static func kind(architectures: [Int]) -> AppKind {
        let arm = architectures.contains(NSBundleExecutableArchitectureARM64)
        let intel = architectures.contains(NSBundleExecutableArchitectureX86_64)
        switch (arm, intel) {
        case (true, true): return .universal
        case (true, false): return .appleSilicon
        case (false, true): return .intel
        case (false, false): return .other
        }
    }
}
