import Foundation

/// System Info as plain text: one item for Copy, every item for Export Report…. Identifying
/// values (serials, hardware IDs, addresses, user name) are left out unless asked for, so a
/// report is safe to paste into a forum post or a support ticket.
enum SystemInfoReport {
    /// The item's title, underlined, then its tree as an outline: "Label: value" leaves,
    /// groups indented two spaces under their titles.
    nonisolated static func text(for item: SystemInfoItem, nodes: [ProfilerNode], includesIdentifying: Bool) -> String {
        var lines = [item.title, String(repeating: "=", count: item.title.count), ""]
        for node in nodes { lines += outline(node, depth: 0, includesIdentifying: includesIdentifying) }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Every item with something to show, under its category, in the column's order. Items
    /// that couldn't be read say so; empty ones are left out.
    nonisolated static func report(states: [String: SystemInfoState], includesIdentifying: Bool, generated: Date) -> String {
        var sections = ["System Report from macOSmonitor",
                        generated.formatted(date: .long, time: .shortened),
                        includesIdentifying
                            ? "This report includes identifying details (serial numbers, hardware IDs, addresses, user name)."
                            : "Identifying details (serial numbers, hardware IDs, addresses, user name) are left out.",
                        ""]
        for category in SystemInfoCategory.allCases {
            var items: [String] = []
            for item in SystemInfoItem.catalog where item.category == category {
                switch states[item.id] {
                case .loaded(let nodes) where !nodes.isEmpty:
                    items.append(text(for: item, nodes: nodes, includesIdentifying: includesIdentifying))
                case .failed:
                    items.append(text(for: item, nodes: [], includesIdentifying: false) + "(couldn’t be read)\n")
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

    /// A node's lines; nothing for an identifying value left out, or a group left empty.
    private nonisolated static func outline(_ node: ProfilerNode, depth: Int, includesIdentifying: Bool) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        if node.children.isEmpty {
            guard includesIdentifying || !node.isSensitive else { return [] }
            return [indent + node.title + ": " + (node.value ?? "")]
        }
        let children = node.children.flatMap { outline($0, depth: depth + 1, includesIdentifying: includesIdentifying) }
        return children.isEmpty ? [] : [indent + node.title] + children
    }
}

/// How far Export Report… has got reading the types.
struct SystemInfoLoadAllProgress: Equatable, Sendable {
    let done: Int
    let total: Int
    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
}
