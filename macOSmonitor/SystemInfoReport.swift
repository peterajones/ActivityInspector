import Foundation
import SystemConfiguration

/// System Info as plain text: one item for Copy, every item for Export Report…. Identifying
/// values (serials, hardware IDs, addresses, user name) are left out unless asked for, so a
/// report is safe to paste into a forum post or a support ticket.
enum SystemInfoReport {
    /// The item's title, underlined, then its tree as an outline: "Label: value" leaves,
    /// groups indented two spaces under their titles.
    nonisolated static func text(for item: SystemInfoItem, nodes: [ProfilerNode], includesIdentifying: Bool,
                                 names: IdentifyingNames = .thisMac()) -> String {
        var lines = [item.title, String(repeating: "=", count: item.title.count), ""]
        for node in nodes { lines += outline(node, depth: 0, includesIdentifying: includesIdentifying, names: names) }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Every item with something to show, under its category, in the column's order. Items
    /// that couldn't be read say so; empty ones are left out.
    nonisolated static func report(states: [String: SystemInfoState], includesIdentifying: Bool, generated: Date,
                                   names: IdentifyingNames = .thisMac()) -> String {
        var sections = ["System Report from macOSmonitor",
                        generated.formatted(date: .long, time: .shortened),
                        includesIdentifying
                            ? "This report includes identifying details (serial numbers, hardware IDs, addresses, network names, user and computer names)."
                            : "Identifying details (serial numbers, hardware IDs, addresses, network names, user and computer names) are left out.",
                        ""]
        for category in SystemInfoCategory.allCases {
            var items: [String] = []
            for item in SystemInfoItem.catalog where item.category == category {
                switch states[item.id] {
                case .loaded(let nodes) where !nodes.isEmpty:
                    items.append(text(for: item, nodes: nodes, includesIdentifying: includesIdentifying, names: names))
                case .failed:
                    items.append(text(for: item, nodes: [], includesIdentifying: false, names: names) + "(couldn’t be read)\n")
                default:
                    continue
                }
            }
            guard !items.isEmpty else { continue }
            sections.append("")
            sections.append(category.title.uppercased())
            sections.append("")
            sections += items
        }
        return sections.joined(separator: "\n")
    }

    /// A node's lines; nothing for an identifying value left out, or a group left empty. With
    /// identifying details off, a nearby network's name becomes "Wi-Fi network" and names found
    /// in any title or value are replaced.
    private nonisolated static func outline(_ node: ProfilerNode, depth: Int, includesIdentifying: Bool,
                                            names: IdentifyingNames) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        let shown: (String) -> String = { includesIdentifying ? $0 : names.scrub($0) }
        let title = !includesIdentifying && node.titleIsSensitive ? "Wi-Fi network" : shown(node.title)
        if node.children.isEmpty {
            guard includesIdentifying || !node.isSensitive else { return [] }
            return [indent + title + ": " + shown(node.value ?? "")]
        }
        let children = node.children.flatMap {
            outline($0, depth: depth + 1, includesIdentifying: includesIdentifying, names: names)
        }
        return children.isEmpty ? [] : [indent + title] + children
    }
}

/// How far Export Report… has got reading the types.
struct SystemInfoLoadAllProgress: Equatable, Sendable {
    let done: Int
    let total: Int
    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

/// Names that identify this Mac and its user, found anywhere in the text (paths, log lines,
/// volume names), which a list of sensitive keys can't catch.
struct IdentifyingNames: Sendable {
    let home: String
    let userName: String
    let fullName: String
    /// The Mac's name and its local host name.
    let computerNames: [String]

    /// The home folder becomes "~", the Mac's names "<this Mac>", the user's names "<user>".
    /// Names shorter than three characters are left alone: they'd match too much.
    nonisolated func scrub(_ text: String) -> String {
        var text = text
        if home.count >= 3 { text = text.replacingOccurrences(of: home, with: "~") }
        for name in computerNames.filter({ $0.count >= 3 }).sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: name, with: "<this Mac>")
        }
        if fullName.count >= 3 { text = text.replacingOccurrences(of: fullName, with: "<user>") }
        // The short name only as a whole word: "pat" mustn't turn "compatible" into nonsense.
        if userName.count >= 3 {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: userName) + "\\b"
            text = text.replacingOccurrences(of: pattern, with: "<user>", options: .regularExpression)
        }
        return text
    }

    nonisolated static func thisMac() -> IdentifyingNames {
        let computerNames = [SCDynamicStoreCopyComputerName(nil, nil) as String?,
                             SCDynamicStoreCopyLocalHostName(nil) as String?].compactMap { $0 }
        return IdentifyingNames(home: UserHome.path, userName: NSUserName(), fullName: NSFullUserName(),
                                computerNames: computerNames)
    }
}
