import SwiftUI
import AppKit

/// Startup Apps or Services: a filterable table of launchd jobs with a detail pane below.
/// Startup Apps' checkbox switches an agent on or off after a confirmation; Services is
/// read-only (changing a system daemon needs an administrator).
struct LaunchItemsView: View {
    @Bindable var model: LaunchItemsModel
    @Environment(\.theme) private var theme

    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            header
            table
            Rectangle().fill(theme.secondaryText.opacity(0.25)).frame(height: 1)
            detail
                .frame(height: 210)
        }
        .background(theme.panelBackground)
        // Running state changes as jobs start and stop; read it again every 5 s while shown.
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { model.pendingChange != nil },
                                                                     set: { if !$0 { model.cancelChange() } })) {
            // The change is captured here: dismissing the dialog clears the model's copy.
            if let change = model.pendingChange {
                Button(change.enable ? "Enable" : "Disable", role: change.enable ? nil : .destructive) {
                    apply(change)
                }
            }
            Button("Cancel", role: .cancel) { model.cancelChange() }
        } message: {
            Text(model.pendingChange?.enable == true
                 ? "It starts now and every time you log in."
                 : "It stops now and won’t start when you log in. You can turn it back on here.")
        }
        .alert("Couldn’t change it", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var confirmationTitle: String {
        guard let change = model.pendingChange else { return "" }
        return "\(change.enable ? "Enable" : "Disable") “\(change.row.item.label)”?"
    }

    private func apply(_ change: LaunchItemsModel.PendingChange) {
        busy = true
        Task {
            error = await model.confirm(change)
            busy = false
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.kind == .startup ? "Startup Apps" : "Services")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.primaryText)
            Text("\(model.visibleRows.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
            Spacer()
            if model.kind == .services {
                Toggle("Show Apple services", isOn: $model.showsAppleServices)
                    .toggleStyle(.checkbox)
            }
            TextField(model.kind == .startup ? "Filter startup apps" : "Filter services", text: $model.filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var table: some View {
        if model.kind == .startup {
            Table(model.visibleRows, selection: $model.selection) {
                TableColumn("Enabled") { row in
                    if let problem = row.item.problem {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help(problem)
                    } else {
                        Toggle("", isOn: Binding(get: { row.enabled }, set: { model.requestChange(row, enable: $0) }))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(busy)
                    }
                }
                .width(60)
                TableColumn("Name") { row in Text(row.item.label) }
                    .width(min: 160, ideal: 260)
                TableColumn("Publisher") { row in publisherText(row) }
                    .width(min: 90, ideal: 130)
                TableColumn("When") { row in Text(row.item.schedule) }
                    .width(min: 80, ideal: 110)
                TableColumn("Running") { row in runningText(row) }
                    .width(70)
                TableColumn("Command") { row in Text(row.item.commandLine).help(row.item.commandLine) }
            }
        } else {
            Table(model.visibleRows, selection: $model.selection) {
                TableColumn("Running") { row in runningText(row) }
                    .width(70)
                TableColumn("Name") { row in Text(row.item.label) }
                    .width(min: 160, ideal: 260)
                TableColumn("Publisher") { row in publisherText(row) }
                    .width(min: 90, ideal: 130)
                TableColumn("When") { row in Text(row.item.schedule) }
                    .width(min: 80, ideal: 110)
                TableColumn("Program") { row in Text(row.item.commandLine).help(row.item.commandLine) }
            }
        }
    }

    /// "● 857" while running, else a dash (with the last exit status when it failed).
    private func runningText(_ row: LaunchRow) -> some View {
        Group {
            if let pid = row.pid {
                Label { Text(verbatim: String(pid)) } icon: { Image(systemName: "circle.fill") }
                    .labelStyle(DotLabelStyle(color: .green))
            } else if let exit = row.lastExit, exit != 0 {
                Text("exit \(exit)").foregroundStyle(.orange)
            } else {
                Text("—").foregroundStyle(theme.secondaryText)
            }
        }
        .monospacedDigit()
    }

    /// Anything whose signature wasn't verified stands out.
    private func publisherText(_ row: LaunchRow) -> some View {
        Text(row.publisher)
            .foregroundStyle(CodePublisher.isUnverified(row.publisher) ? .orange : theme.primaryText)
    }

    @ViewBuilder private var detail: some View {
        if let row = model.selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.item.label).font(.headline).foregroundStyle(theme.primaryText)
                            Text(row.item.plistPath).font(.caption).foregroundStyle(theme.secondaryText)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.item.plistPath)])
                        }
                        Button("Open File") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: row.item.plistPath))
                        }
                    }
                    if let problem = row.item.problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    HStack(alignment: .top, spacing: 40) {
                        facts("Job", [
                            ("Status", row.enabled ? "Enabled" : "Disabled"),
                            ("Running", row.pid.map { "Yes (PID \($0))" } ?? "No"),
                            ("When", row.item.schedule),
                            ("Publisher", row.publisher),
                            ("For", row.item.scope.locationText),
                            ("Last exit", row.lastExit.map(String.init) ?? "—"),
                        ])
                        facts("File", [
                            ("Size", row.item.facts.map { ByteCountFormatter.string(fromByteCount: Int64($0.size), countStyle: .file) } ?? "—"),
                            ("Modified", row.item.facts?.modified.map(Self.date) ?? "—"),
                            ("Created", row.item.facts?.created.map(Self.date) ?? "—"),
                            ("Owner", row.item.facts?.owner ?? "—"),
                            ("Permissions", row.item.facts.map { FileFacts.permissionsText($0.permissions) } ?? "—"),
                        ])
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Command").font(.caption).foregroundStyle(theme.secondaryText)
                        Text(row.item.commandLine).font(.callout.monospaced()).foregroundStyle(theme.primaryText)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Select an item for its details.")
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func facts(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(theme.secondaryText)
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
    }

    private static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A small coloured dot before the label.
private struct DotLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(color)
            configuration.title
        }
    }
}
