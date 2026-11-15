import SwiftUI
import AppKit

/// Installed Apps: every app in an Applications folder (or every app, when asked), sortable
/// and filterable, with a detail pane below. Sizes fill in as they're measured.
struct InstalledAppsView: View {
    @Bindable var model: InstalledAppsModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            Rectangle().fill(theme.secondaryText.opacity(0.25)).frame(height: 1)
            detail
                .frame(height: 190)
        }
        .background(theme.panelBackground)
        .task { await model.loadIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Installed Apps")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.primaryText)
            if model.status == .loaded {
                Text("\(model.visibleRows.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Toggle("Show system and developer apps", isOn: $model.showsAllApps)
                .toggleStyle(.checkbox)
            Button {
                Task { await model.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
            .disabled(model.status == .loading)
            TextField("Filter apps", text: $model.filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .idle, .loading:
            ProgressView("Reading the list of apps…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Text("macOSmonitor couldn’t read the list of apps.")
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            table
        }
    }

    private var table: some View {
        Table(model.visibleRows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    Image(nsImage: ProcessIconCache.shared.icon(forBundle: row.app.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(row.name)
                }
            }
            .width(min: 160, ideal: 220)
            TableColumn("Version", value: \.version)
                .width(min: 60, ideal: 80)
            TableColumn("Kind", value: \.kindText) { row in
                Text(row.kindText)
                    .foregroundStyle(row.app.kind.needsRosetta ? .orange : theme.primaryText)
                    .help(row.app.kind.needsRosetta ? "Runs under Rosetta, which Apple is phasing out." : "")
            }
            .width(min: 80, ideal: 100)
            TableColumn("Origin", value: \.originText) { row in
                Text(row.originText)
                    .foregroundStyle(row.app.origin.isFlagged ? .orange : theme.primaryText)
            }
            .width(min: 80, ideal: 130)
            TableColumn("Publisher", value: \.publisher) { row in
                Text(row.publisher)
                    .foregroundStyle(CodePublisher.isUnverified(row.publisher) ? .orange : theme.primaryText)
            }
            .width(min: 90, ideal: 140)
            TableColumn("Size", value: \.sizeSort) { row in
                Text(row.size.map(Self.bytes) ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(row.size == nil ? theme.secondaryText : theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Modified", value: \.modifiedSort) { row in
                Text(row.app.modified.map(Self.date) ?? "—")
            }
            .width(min: 90, ideal: 110)
        }
    }

    @ViewBuilder private var detail: some View {
        if let row = model.selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(nsImage: ProcessIconCache.shared.icon(forBundle: row.app.path))
                            .resizable()
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.headline).foregroundStyle(theme.primaryText)
                            Text(row.app.path).font(.caption).foregroundStyle(theme.secondaryText)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.app.path)])
                        }
                    }
                    HStack(alignment: .top, spacing: 40) {
                        facts([
                            ("Version", row.app.version ?? "—"),
                            ("Kind", row.kindText),
                            ("Size", row.size.map(Self.bytes) ?? "—"),
                            ("Modified", row.app.modified.map(Self.date) ?? "—"),
                        ])
                        facts([
                            ("Bundle ID", Bundle(path: row.app.path)?.bundleIdentifier ?? "—"),
                            ("Origin", row.originText),
                            ("Publisher", row.publisher),
                            ("Signed by", row.app.signedBy.isEmpty ? "Not signed" : row.app.signedBy.joined(separator: " → ")),
                        ])
                    }
                    if let info = row.app.info {
                        Text(info).font(.caption).foregroundStyle(theme.secondaryText).textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Select an app for its details.")
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func facts(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
            ForEach(rows, id: \.0) { label, value in
                GridRow {
                    Text(label).foregroundStyle(theme.secondaryText)
                    Text(value).foregroundStyle(theme.primaryText).textSelection(.enabled)
                }
            }
        }
        .font(.callout)
    }

    private static func bytes(_ size: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
