import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// System Info: a column of `system_profiler`'s data types under Hardware, Network and
/// Software, and the chosen one as a tree of Apple's labels and values. No graphs.
struct SystemInfoView: View {
    @Bindable var model: SystemInfoModel
    @Environment(\.theme) private var theme
    /// Briefly true after Copy, to say it worked.
    @State private var copied = false
    @State private var exportError: String?

    static var columnWidth: CGFloat { 250 }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                column
                Rectangle().fill(theme.secondaryText.opacity(0.25)).frame(height: 1)
                exportFooter
            }
            .frame(width: Self.columnWidth)
            .background(theme.panelBackground)
            Rectangle().fill(theme.secondaryText.opacity(0.25)).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.panelBackground)
        }
        .task { await model.preload() }
        .task(id: model.selection) { await model.load(model.selection) }
        .alert("Couldn’t save the report", isPresented: Binding(get: { exportError != nil },
                                                                set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    /// Export Report…, or how far reading every type has got.
    @ViewBuilder private var exportFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = model.loadAllProgress {
                ProgressView(value: progress.fraction)
                Text("Reading \(progress.done) of \(progress.total)…")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            } else {
                Button {
                    Task { await exportReport() }
                } label: {
                    Label("Export Report…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .help("Save every item as a text file. Wi-Fi and Fonts take a few seconds to read.")
            }
        }
        .padding(12)
    }

    /// Reads every type, then asks where to save the text.
    private func exportReport() async {
        await model.loadAll()
        let report = SystemInfoReport.report(states: model.states, includesIdentifying: model.includesIdentifying,
                                             generated: .now)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "System Report.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Puts the item's text on the clipboard.
    private func copy(_ item: SystemInfoItem, _ nodes: [ProfilerNode]) {
        let text = SystemInfoReport.text(for: item, nodes: nodes, includesIdentifying: model.includesIdentifying)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
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
                Toggle("Include identifying details", isOn: $model.includesIdentifying)
                    .toggleStyle(.checkbox)
                    .help("Serial numbers, hardware IDs, addresses and your user name, in Copy and Export Report…")
                Button {
                    if case .loaded(let nodes) = model.state(of: item.id) { copy(item, nodes) }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(!Self.hasContent(model.state(of: item.id)))
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

    nonisolated static func hasContent(_ state: SystemInfoState?) -> Bool {
        if case .loaded(let nodes) = state { !nodes.isEmpty } else { false }
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
                if node.titleIsSensitive {
                    MaskedValue(text: node.title)      // a nearby network's name, as dots until clicked
                } else {
                    Text(node.title)
                        .font(depth == 0 ? .headline : .body)
                        .foregroundStyle(theme.primaryText)
                }
            }
            .padding(.vertical, 3)
        }
    }
}

/// A value that identifies this Mac or a device: dots until clicked, so a screenshot of the app
/// doesn't give away a serial number or address.
struct MaskedValue: View {
    let text: String
    @State private var revealed = false
    @Environment(\.theme) private var theme

    /// Always eight dots when hidden, so not even a value's length shows.
    nonisolated static func shown(_ text: String, revealed: Bool) -> String {
        revealed ? text : "••••••••"
    }

    var body: some View {
        Button { revealed.toggle() } label: {
            HStack(spacing: 6) {
                Text(Self.shown(text, revealed: revealed))
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
