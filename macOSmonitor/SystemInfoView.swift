import SwiftUI

/// System Info: a column of `system_profiler`'s data types under Hardware, Network and
/// Software, and the chosen one as a tree of Apple's labels and values. No graphs.
struct SystemInfoView: View {
    let model: SystemInfoModel
    @Environment(\.theme) private var theme

    static var columnWidth: CGFloat { 250 }

    var body: some View {
        HStack(spacing: 0) {
            column
                .frame(width: Self.columnWidth)
                .background(theme.panelBackground)
            Rectangle().fill(theme.secondaryText.opacity(0.25)).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.panelBackground)
        }
        .task { await model.preload() }
        .task(id: model.selection) { await model.load(model.selection) }
    }

    private var column: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SystemInfoCategory.allCases, id: \.self) { category in
                    Text(category.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.top, category == .hardware ? 0 : 12)
                        .padding(.horizontal, 8)
                    ForEach(model.visibleItems(in: category)) { item in row(item) }
                }
            }
            .padding(8)
        }
    }

    private func row(_ item: SystemInfoItem) -> some View {
        let selected = model.selection == item.id
        return Button { model.selection = item.id } label: {
            Label(item.title, systemImage: item.systemImage)
                .foregroundStyle(selected ? Color.white : theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        let item = SystemInfoItem.catalog.first { $0.id == model.selection } ?? SystemInfoItem.catalog[0]
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage).font(.title2)
                Text(item.title).font(.title2.weight(.semibold))
                Spacer()
                Button {
                    Task { await model.load(item.id, force: true) }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(model.state(of: item.id) == .loading)
            }
            .foregroundStyle(theme.primaryText)
            .padding(20)
            Rectangle().fill(theme.secondaryText.opacity(0.25)).frame(height: 1)

            switch model.state(of: item.id) {
            case .loaded(let nodes) where !nodes.isEmpty:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                            ProfilerNodeRow(node: node, depth: 0, startsExpanded: index == 0)
                        }
                    }
                    .padding(20)
                }
                .id(item.id)   // a fresh tree (and fresh disclosure state) per item
            case .loaded:
                message("Nothing to show on this Mac.")
            case .failed:
                message("Couldn’t read this from system_profiler. Try Reload.")
            case .loading, nil:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Reading \(item.title)…").foregroundStyle(theme.secondaryText)
                    if let seconds = item.expectedSeconds {
                        Text("This usually takes about \(seconds) seconds.")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One node of a System Info tree: a label and value, or a group that folds open.
private struct ProfilerNodeRow: View {
    let node: ProfilerNode
    let depth: Int
    @State private var expanded: Bool
    @Environment(\.theme) private var theme

    init(node: ProfilerNode, depth: Int, startsExpanded: Bool) {
        self.node = node
        self.depth = depth
        _expanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        if node.children.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(node.title)
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 240, alignment: .leading)
                if node.isSensitive {
                    MaskedValue(text: node.value ?? "")
                } else {
                    Text(node.value ?? "")
                        .foregroundStyle(theme.secondaryText)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.secondaryText.opacity(0.15)).frame(height: 1)
            }
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                        // A group that holds a single group opens it too.
                        ProfilerNodeRow(node: child, depth: depth + 1,
                                        startsExpanded: node.children.count == 1 && index == 0)
                    }
                }
                .padding(.leading, 12)
            } label: {
                Text(node.title)
                    .font(depth == 0 ? .headline : .body)
                    .foregroundStyle(theme.primaryText)
            }
            .padding(.vertical, 3)
        }
    }
}

/// A value that identifies this Mac or a device: dots until clicked, so a screenshot of the app
/// doesn't give away a serial number or address.
private struct MaskedValue: View {
    let text: String
    @State private var revealed = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button { revealed.toggle() } label: {
            HStack(spacing: 6) {
                Text(revealed ? text : "••••••••")
                    .foregroundStyle(theme.secondaryText)
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .help(revealed ? "Hide" : "Show")
        .textSelection(.enabled)
    }
}
