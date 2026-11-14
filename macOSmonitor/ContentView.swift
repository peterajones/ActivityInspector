//
//  ContentView.swift
//  macOSmonitor
//

import SwiftUI

struct ContentView: View {
    @State private var model = ProcessListModel(privileged: PrivilegedHelperClient.shared)
    /// Owned by the app, shared with the menu bar and other windows; its loop runs there.
    let vitalsModel: VitalsModel
    @State private var batteryModel = BatteryModel()
    /// Sampled only while the Ports surface shows (its view runs the loop); held here so the
    /// last sample is on screen at once when you come back.
    @State private var portsModel = PortsModel(sampler: PortsSampler(privileged: PrivilegedHelperClient.shared))
    @State private var surface: Surface? = .summary
    /// The metric page Performance reopens: the last one viewed, CPU at first.
    @State private var lastMetric: Surface = .cpu
    @AppStorage("themeID") private var themeID: String = Theme.system.id
    @AppStorage(Bloom.storageKey) private var bloomLevel = Bloom.defaultLevel
    @AppStorage(SaturationLevel.storageKey) private var saturationLevel = SaturationLevel.defaultLevel
    @State private var showsColours = false
    /// Whether this window can be seen; its graphs stop animating while it can't.
    @State private var windowVisible = true

    // Owned here, not in ProcessesView: that view lives in one branch of the detail
    // `switch` below, so it is destroyed and recreated on every surface change and
    // any @State it declared would reset. Held here, these survive navigation.
    @State private var sortOrder = [KeyPathComparator(\ProcessInfoRow.cpuSortKey, order: .reverse)]
    @State private var showInspector = true
    @State private var searchText = ""
    @State private var searchPresented = false
    @State private var pendingTermination: PendingTermination?
    @State private var errorMessage: String?
    // The Ports surface's view state, held here for the same reason as the Processes state.
    @State private var portsSearchText = ""
    @State private var portsFilter: PortFilter = .all
    @State private var portsSortOrder: [KeyPathComparator<PortRow>] = []
    // Remembered across launches, like Activity Monitor's View menu choice. Search text
    // itself is not: a filter you forgot about would hide processes on the next launch.
    @AppStorage("processFilterPreset") private var filterPreset: ProcessFilter.Preset = .all
    @AppStorage("hideSystemProcesses") private var hidesSystemProcesses = false
    @AppStorage("savedSearches") private var savedSearches = SavedSearches()

    private var theme: Theme { Theme.named(themeID) }

    /// The bottom of the sidebar: Settings (the ⌘, window) and the Colours popover (theme,
    /// saturation, bloom).
    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            Button { showsColours.toggle() } label: {
                Label("Colours", systemImage: "paintpalette")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showsColours, arrowEdge: .top) {
                ColoursPopover(themeID: $themeID, bloomLevel: $bloomLevel, saturationLevel: $saturationLevel)
            }
            Spacer(minLength: 0)
        }
        // One line each: at the sidebar's narrowest the two labels only just fit.
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            Group {
                switch surface ?? .summary {
                case .summary:
                    SummaryView(model: model, vitalsModel: vitalsModel, surface: $surface)
                case .processes:
                    ProcessesView(model: model,
                                  vitalsModel: vitalsModel,
                                  sections: sections,
                                  sortOrder: $sortOrder,
                                  showInspector: $showInspector,
                                  searchText: $searchText,
                                  searchPresented: $searchPresented,
                                  filterPreset: $filterPreset,
                                  hidesSystemProcesses: $hidesSystemProcesses,
                                  savedSearches: $savedSearches,
                                  pendingTermination: $pendingTermination,
                                  errorMessage: $errorMessage)
                case .ports:
                    PortsView(model: portsModel,
                              searchText: $portsSearchText,
                              filter: $portsFilter,
                              sortOrder: $portsSortOrder)
                // One branch for every metric page, so the Performance column keeps its
                // identity (and scroll position) while the page beside it changes.
                case .cpu, .gpu, .memory, .network, .disk, .thermal, .energy, .battery:
                    PerformanceView(selection: $surface, items: performanceItems, vitalsModel: vitalsModel) {
                        performancePage
                    }
                }
            }
            .saturation(SaturationLevel.amount(saturationLevel))
            // Outside the switch, so it isn't rebuilt (and its loop restarted) on every
            // surface change.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBarView(processCount: model.rows.count, uptime: vitalsModel.vitals?.uptimeText)
            }
        }
        // 1,000 wide: sidebar, the Performance column and a page with room for two graphs.
        .frame(minWidth: 1000, minHeight: 500)
        .onChange(of: surface) { _, page in
            if let page, page.sidebarItem == .performance { lastMetric = page }
        }
        .navigationTitle("macOSmonitor")
        .environment(\.theme, theme)
        .environment(\.bloom, Bloom(level: bloomLevel))
        .environment(\.graphsAnimate, windowVisible)
        .background(WindowVisibilityReader { windowVisible = $0 })
        // One customizable toolbar for the whole window (right-click → Customize Toolbar…),
        // declared here so it survives surface changes. Item IDs are what macOS stores the
        // user's arrangement under: don't rename them. The process buttons stay visible but
        // disabled off the Processes surface; hiding them would rebuild the toolbar.
        .toolbar(id: "main") {
            ToolbarItem(id: "quit") {
                Button("Quit") { pendingTermination = processRequest(.terminate) }
                    .disabled(!canTerminateSelection)
            }
            ToolbarItem(id: "forceQuit") {
                Button("Force Quit") { pendingTermination = processRequest(.kill) }
                    .disabled(!canTerminateSelection)
            }
            ToolbarItem(id: "inspector") {
                Button { showInspector.toggle() } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.trailing")
                }
                .disabled(surface != .processes)
            }
        }
        // The window's loops live here, on the always-alive split view: the process loop
        // moved up in M11 so the Summary's top-processes card has data on every surface.
        // A loop owned by a view inside the detail `switch` would be cancelled on every
        // navigation. The vitals loop moved further up, to the app, so the menu bar shares
        // it (see macOSmonitorApp).
        .task { await model.run() }
        // Battery history records every minute whichever surface is showing.
        .task { await batteryModel.run() }
        .environment(\.graphFrameRate, vitalsModel.graphFrameRate)
    }

    /// The process table's rows as filtered and sorted now. Built here so the toolbar acts
    /// on exactly the rows `ProcessesView` shows.
    private var sections: [ProcessTableSection] {
        ProcessTableSection.make(rows: model.rows,
                                 searchText: searchText,
                                 filter: ProcessFilter(preset: filterPreset, hidesSystem: hidesSystemProcesses),
                                 sortOrder: sortOrder)
    }

    /// The selection as Quit / Force Quit would act on it: visible rows only.
    private var selectionBatch: ProcessBatch {
        ProcessBatch.make(pids: model.selectedPIDs, visibleRows: sections.flatMap(\.rows))
    }

    /// Quit / Force Quit act only on the Processes surface, where the selection is visible.
    private var canTerminateSelection: Bool {
        surface == .processes && !selectionBatch.targets.isEmpty
    }

    /// Quit and Force Quit both confirm, so the toolbar only ever stages a request.
    private func processRequest(_ signal: ProcessSignal) -> PendingTermination? {
        guard surface == .processes else { return nil }
        return PendingTermination.request(for: selectionBatch, signal: signal)
    }

    /// The metric pages this Mac has, in Performance-column order.
    private var performanceItems: [Surface] {
        Surface.performance(hasGPU: vitalsModel.vitals?.gpu != nil,
                            hasThermal: vitalsModel.thermal != nil,
                            hasEnergy: vitalsModel.power != nil,
                            hasBattery: vitalsModel.vitals?.battery != nil)
    }

    /// The sidebar's selection: Performance for any metric page, and choosing it reopens the
    /// metric last viewed.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(get: { (surface ?? .summary).sidebarItem },
                set: { item in
                    guard let item else { return }
                    surface = item.surface(lastMetric: lastMetric, available: performanceItems)
                })
    }

    @ViewBuilder private var performancePage: some View {
        switch surface ?? .summary {
        case .gpu: GPUPanel(model: vitalsModel)
        case .memory: MemoryPanel(model: vitalsModel)
        case .network: NetworkPanel(model: vitalsModel)
        case .disk: DiskPanel(model: vitalsModel)
        case .thermal: ThermalPanel(model: vitalsModel)
        case .energy: EnergyPanel(model: vitalsModel, processes: model)
        case .battery: BatteryPanel(model: batteryModel)
        default: CPUPanel(model: vitalsModel)
        }
    }
}

#Preview {
    ContentView(vitalsModel: VitalsModel())
}
