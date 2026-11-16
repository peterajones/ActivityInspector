import Foundation

/// The System Info page is built on `system_profiler -json`, the tool behind Apple's System
/// Information app: public, no root needed, and (probed 2026-11-14) usable from the App
/// Sandbox, with some types reduced or empty there (see CLAUDE.md "Distribution").

enum SystemInfoCategory: CaseIterable, Hashable, Sendable {
    case hardware, network, software

    var title: String {
        switch self {
        case .hardware: "Hardware"
        case .network: "Network"
        case .software: "Software"
        }
    }
}

/// One `system_profiler` data type, as the System Info column lists it.
struct SystemInfoItem: Identifiable, Hashable, Sendable {
    /// The data type's name, e.g. "SPHardwareDataType".
    let id: String
    let title: String
    let systemImage: String
    let category: SystemInfoCategory
    /// Roughly how long it takes to read, for types that take seconds (measured on an M3 Pro).
    var expectedSeconds: Int? = nil

    /// Slow types are read only when chosen, never in the background preload.
    var isSlow: Bool { expectedSeconds != nil }

    /// Apple's System Information order, within each category.
    static let catalog: [SystemInfoItem] = [
        SystemInfoItem(id: "SPHardwareDataType", title: "Hardware Overview", systemImage: "desktopcomputer", category: .hardware),
        SystemInfoItem(id: "SPMemoryDataType", title: "Memory", systemImage: "memorychip", category: .hardware),
        SystemInfoItem(id: "SPAudioDataType", title: "Audio", systemImage: "speaker.wave.2", category: .hardware),
        SystemInfoItem(id: "SPBluetoothDataType", title: "Bluetooth", systemImage: "antenna.radiowaves.left.and.right", category: .hardware),
        SystemInfoItem(id: "SPCameraDataType", title: "Camera", systemImage: "camera", category: .hardware),
        SystemInfoItem(id: "SPCardReaderDataType", title: "Card Reader", systemImage: "sdcard", category: .hardware),
        SystemInfoItem(id: "SPiBridgeDataType", title: "Controller", systemImage: "cpu", category: .hardware),
        SystemInfoItem(id: "SPDiagnosticsDataType", title: "Diagnostics", systemImage: "stethoscope", category: .hardware),
        SystemInfoItem(id: "SPDiscBurningDataType", title: "Disc Burning", systemImage: "opticaldisc", category: .hardware),
        SystemInfoItem(id: "SPFibreChannelDataType", title: "Fibre Channel", systemImage: "cable.connector", category: .hardware),
        SystemInfoItem(id: "SPDisplaysDataType", title: "Graphics/Displays", systemImage: "display", category: .hardware),
        SystemInfoItem(id: "SPNVMeDataType", title: "NVMExpress", systemImage: "internaldrive", category: .hardware),
        SystemInfoItem(id: "SPParallelATADataType", title: "Parallel ATA", systemImage: "internaldrive", category: .hardware),
        SystemInfoItem(id: "SPParallelSCSIDataType", title: "Parallel SCSI", systemImage: "internaldrive", category: .hardware),
        SystemInfoItem(id: "SPPCIDataType", title: "PCI", systemImage: "rectangle.connected.to.line.below", category: .hardware),
        SystemInfoItem(id: "SPPowerDataType", title: "Power", systemImage: "bolt.circle", category: .hardware),
        SystemInfoItem(id: "SPPrintersDataType", title: "Printers", systemImage: "printer", category: .hardware),
        SystemInfoItem(id: "SPSASDataType", title: "SAS", systemImage: "internaldrive", category: .hardware),
        SystemInfoItem(id: "SPSerialATADataType", title: "SATA", systemImage: "internaldrive", category: .hardware),
        SystemInfoItem(id: "SPSPIDataType", title: "SPI", systemImage: "cpu", category: .hardware),
        SystemInfoItem(id: "SPSecureElementDataType", title: "Secure Element", systemImage: "lock.shield", category: .hardware),
        SystemInfoItem(id: "SPSmartCardsDataType", title: "Smart Cards", systemImage: "creditcard", category: .hardware),
        SystemInfoItem(id: "SPStorageDataType", title: "Storage", systemImage: "externaldrive", category: .hardware),
        SystemInfoItem(id: "SPThunderboltDataType", title: "Thunderbolt/USB4", systemImage: "bolt", category: .hardware),
        SystemInfoItem(id: "SPUSBHostDataType", title: "USB", systemImage: "cable.connector.horizontal", category: .hardware),
        SystemInfoItem(id: "SPAppleVirtualPlatformDataType", title: "Virtual Platform", systemImage: "square.stack.3d.up", category: .hardware),

        SystemInfoItem(id: "SPFirewallDataType", title: "Firewall", systemImage: "shield", category: .network),
        SystemInfoItem(id: "SPNetworkLocationDataType", title: "Locations", systemImage: "location", category: .network),
        SystemInfoItem(id: "SPNetworkDataType", title: "Network", systemImage: "globe", category: .network),
        SystemInfoItem(id: "SPEthernetDataType", title: "Ethernet Cards", systemImage: "network", category: .network),
        SystemInfoItem(id: "SPNetworkVolumeDataType", title: "Volumes", systemImage: "externaldrive.connected.to.line.below", category: .network),
        SystemInfoItem(id: "SPAirPortDataType", title: "Wi-Fi", systemImage: "wifi", category: .network, expectedSeconds: 20),

        SystemInfoItem(id: "SPSoftwareDataType", title: "Software Overview", systemImage: "apple.logo", category: .software),
        SystemInfoItem(id: "SPUniversalAccessDataType", title: "Accessibility", systemImage: "accessibility", category: .software),
        SystemInfoItem(id: "SPApplicationsDataType", title: "Applications", systemImage: "app", category: .software, expectedSeconds: 4),
        SystemInfoItem(id: "SPDeveloperToolsDataType", title: "Developer Tools", systemImage: "hammer", category: .software),
        SystemInfoItem(id: "SPDisabledSoftwareDataType", title: "Disabled Software", systemImage: "nosign", category: .software),
        SystemInfoItem(id: "SPExtensionsDataType", title: "Extensions", systemImage: "puzzlepiece.extension", category: .software),
        SystemInfoItem(id: "SPFontsDataType", title: "Fonts", systemImage: "textformat", category: .software, expectedSeconds: 12),
        SystemInfoItem(id: "SPFrameworksDataType", title: "Frameworks", systemImage: "shippingbox", category: .software, expectedSeconds: 3),
        SystemInfoItem(id: "SPInstallHistoryDataType", title: "Installations", systemImage: "clock.arrow.circlepath", category: .software),
        SystemInfoItem(id: "SPInternationalDataType", title: "Language & Region", systemImage: "character.bubble", category: .software),
        SystemInfoItem(id: "SPLegacySoftwareDataType", title: "Legacy Software", systemImage: "hourglass", category: .software),
        SystemInfoItem(id: "SPLogsDataType", title: "Logs", systemImage: "doc.text", category: .software, expectedSeconds: 5),
        SystemInfoItem(id: "SPManagedClientDataType", title: "Managed Client", systemImage: "building.2", category: .software),
        SystemInfoItem(id: "SPPrefPaneDataType", title: "Preference Panes", systemImage: "gearshape", category: .software),
        SystemInfoItem(id: "SPPrintersSoftwareDataType", title: "Printer Software", systemImage: "printer.dotmatrix", category: .software),
        SystemInfoItem(id: "SPConfigurationProfileDataType", title: "Profiles", systemImage: "person.text.rectangle", category: .software),
        SystemInfoItem(id: "SPRawCameraDataType", title: "Raw Support", systemImage: "camera.aperture", category: .software),
        SystemInfoItem(id: "SPStartupItemDataType", title: "Startup Items", systemImage: "power", category: .software),
        SystemInfoItem(id: "SPSyncServicesDataType", title: "Sync Services", systemImage: "arrow.triangle.2.circlepath", category: .software),
    ]
}

/// Runs `system_profiler` for one data type; behind a protocol so the model is testable.
protocol SystemProfilerRunning: Sendable {
    /// The tool's JSON for `type`, or nil when it couldn't run.
    func run(_ type: String) async -> Data?
}

struct SystemProfilerRunner: SystemProfilerRunning {
    func run(_ type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            // On a plain GCD thread: reading to end of file blocks, and the child closing its
            // output is what we wait for, so there's no `waitUntilExit()` (see CLAUDE.md).
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                process.arguments = ["-json", "-detailLevel", "full", type]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data.isEmpty ? nil : data)
            }
        }
    }
}

/// Apple's display names for `system_profiler`'s keys and values, from each reporter's
/// `Localizable.loctable` (the same text System Information shows).
struct ProfilerLabels: Sendable {
    let table: [String: String]

    /// A key's display name: Apple's, else the key tidied ("some_key" → "Some key",
    /// "platform_UUID" → "Platform UUID"; "MAC Address" stays as it is).
    nonisolated func label(_ key: String) -> String {
        if let label = table[key] { return label }
        let words = key.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// A value's display text: Apple's for values that are keys themselves ("spaudio_default").
    nonisolated func value(_ raw: String) -> String { table[raw] ?? raw }

    /// Every reporter's table, merged, in the first of `languages` it has (English otherwise).
    nonisolated static func system(languages: [String]) -> ProfilerLabels {
        load(root: URL(fileURLWithPath: "/System/Library/SystemProfiler"), languages: languages)
    }

    /// Every `.spreporter` bundle's table under `root`, merged.
    nonisolated static func load(root: URL, languages: [String]) -> ProfilerLabels {
        let reporters = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var merged: [String: String] = [:]
        for reporter in reporters where reporter.pathExtension == "spreporter" {
            let file = reporter.appendingPathComponent("Contents/Resources/Localizable.loctable")
            // One table per language, beside bookkeeping entries such as "LocProvenance".
            guard let tables = NSDictionary(contentsOf: file) as? [String: Any] else { continue }
            let candidates = languages.flatMap { [$0, String($0.prefix { $0 != "-" && $0 != "_" })] } + ["en"]
            guard let table = candidates.lazy.compactMap({ tables[$0] as? [String: String] }).first else { continue }
            merged.merge(table) { first, _ in first }
        }
        return ProfilerLabels(table: merged)
    }
}

/// One row of a System Info tree: a value, or a group of rows.
struct ProfilerNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let value: String?
    let children: [ProfilerNode]
    /// Identifies this Mac or a device (serials, hardware IDs, MAC addresses, user name): shown
    /// masked until clicked, so screenshots of the app are safe to share.
    var isSensitive = false
    /// The title itself identifies something (a nearby Wi-Fi network's name).
    var titleIsSensitive = false

    /// Lists whose items are named after something identifying: nearby Wi-Fi networks.
    nonisolated static func namesItsItemsSensitively(key: String) -> Bool {
        key == "spairport_airport_other_local_wireless_networks"
    }

    nonisolated static func isSensitive(key: String) -> Bool {
        let key = key.lowercased()
        return ["serial", "uuid", "udid", "mac_address", "mac address", "hardware_address", "hardwareaddress"]
            .contains { key.contains($0) }
            || ["controller_address", "device_address", "user_name",
                // The Mac's name and its network's addresses (security review, 2026-11-15).
                "local_host_name", "ip_address", "addresses", "router", "serveraddress", "serveraddresses",
                "arpresolvedipaddress", "dhcp_routers", "dhcp_domain_name_servers", "dhcp_server_identifier"].contains(key)
    }
}

/// Turns `system_profiler -json` output into display trees.
enum ProfilerParser {
    /// Nil when the data isn't the tool's JSON for `type`; empty when the type has no items.
    nonisolated static func parse(_ data: Data, type: String, labels: ProfilerLabels) -> [ProfilerNode]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = root[type] as? [Any]
        else { return nil }
        // A top item without a name (Bluetooth's) takes the page's name.
        let pageTitle = SystemInfoItem.catalog.first { $0.id == type }?.title
        return items.enumerated().compactMap { index, item in
            (item as? [String: Any]).map {
                node(named: $0, fallback: pageTitle ?? "Item \(index + 1)", id: "\(type)/\(index)", labels: labels)
            }
        }
    }

    /// A dictionary with a `_name` (an item): its name as the title, its contents as rows.
    private nonisolated static func node(named dictionary: [String: Any], fallback: String, id: String,
                                         labels: ProfilerLabels) -> ProfilerNode {
        let title = (dictionary["_name"] as? String).map(labels.value) ?? fallback
        return ProfilerNode(id: id, title: title, value: nil, children: rows(dictionary, id: id, labels: labels))
    }

    /// A dictionary's rows: plain values first, then groups, each alphabetically by label.
    /// Keys starting with "_" are the tool's own bookkeeping, except `_items`, the children.
    private nonisolated static func rows(_ dictionary: [String: Any], id: String, labels: ProfilerLabels) -> [ProfilerNode] {
        var leaves: [ProfilerNode] = []
        var groups: [ProfilerNode] = []
        for (key, value) in dictionary where !key.hasPrefix("_") {
            let childID = "\(id)/\(key)"
            let title = labels.label(key)
            switch value {
            case let nested as [String: Any]:
                groups.append(ProfilerNode(id: childID, title: title, value: nil,
                                           children: rows(nested, id: childID, labels: labels)))
            case let list as [Any] where list.contains(where: { $0 is [String: Any] }):
                var items = children(list, id: childID, labels: labels)
                if ProfilerNode.namesItsItemsSensitively(key: key) {
                    items = items.map { var item = $0; item.titleIsSensitive = true; return item }
                }
                groups.append(ProfilerNode(id: childID, title: title, value: nil, children: items))
            case let list as [Any]:
                leaves.append(ProfilerNode(id: childID, title: title,
                                           value: list.map { text($0, labels: labels) }.joined(separator: ", "),
                                           children: [], isSensitive: ProfilerNode.isSensitive(key: key)))
            default:
                leaves.append(ProfilerNode(id: childID, title: title, value: text(value, labels: labels),
                                           children: [], isSensitive: ProfilerNode.isSensitive(key: key)))
            }
        }
        if let items = dictionary["_items"] as? [Any] {
            groups += children(items, id: "\(id)/_items", labels: labels)
        }
        let byTitle: (ProfilerNode, ProfilerNode) -> Bool = {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        // Items keep the tool's order (it lists devices and apps meaningfully); rows sort.
        return leaves.sorted(by: byTitle) + groups.filter { !$0.id.contains("/_items/") }.sorted(by: byTitle)
            + groups.filter { $0.id.contains("/_items/") }
    }

    private nonisolated static func children(_ list: [Any], id: String, labels: ProfilerLabels) -> [ProfilerNode] {
        list.enumerated().compactMap { index, element in
            (element as? [String: Any]).map {
                node(named: $0, fallback: "Item \(index + 1)", id: "\(id)/\(index)", labels: labels)
            }
        }
    }

    /// Hardware's core count arrives as "proc 12:0:6:6"; Apple's own text output writes it
    /// "12 (6 Performance and 6 Efficiency)". The third and fourth numbers are taken in that
    /// order: on the M3 Pro it was written against, both are 6, so the order is unverified for
    /// chips with unequal counts.
    nonisolated static func coreCountText(_ raw: String) -> String? {
        guard raw.hasPrefix("proc ") else { return nil }
        let parts = raw.dropFirst(5).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        return "\(parts[0]) (\(parts[2]) Performance and \(parts[3]) Efficiency)"
    }

    private nonisolated static func text(_ value: Any, labels: ProfilerLabels) -> String {
        switch value {
        case let string as String: coreCountText(string) ?? labels.value(string)
        case let number as NSNumber: number.stringValue
        default: String(describing: value)
        }
    }
}
