import Testing
import Foundation
@testable import ActivityInspector

/// The Settings window offers settings that menus and popovers also offer; each must store
/// under the same key, or changing one wouldn't move the other.
@MainActor
struct SettingsViewTests {
    /// The five settings and their shared keys.
    private static let keys = [Theme.storageKey, SaturationLevel.storageKey, Bloom.storageKey,
                               MenuBarSettings.key, CPUTimeFormat.storageKey]

    /// The UserDefaults keys of a view's @AppStorage properties, read by reflection.
    private func appStorageKeys(of value: Any) -> Set<String> {
        var keys = Set<String>()
        for child in Mirror(reflecting: value).children
        where String(describing: type(of: child.value)).hasPrefix("AppStorage<") {
            if let key = firstKey(in: child.value) { keys.insert(key) }
        }
        return keys
    }

    private func firstKey(in value: Any, depth: Int = 0) -> String? {
        guard depth < 6 else { return nil }
        for child in Mirror(reflecting: value).children {
            if child.label == "key", let key = child.value as? String { return key }
            if let key = firstKey(in: child.value, depth: depth + 1) { return key }
        }
        return nil
    }

    @Test func settingsStoresEachSettingUnderItsSharedKey() {
        #expect(appStorageKeys(of: SettingsView()) == Set(Self.keys))
    }

    /// Every other place that stores one of these settings names it by the same constant, never
    /// a literal of its own; and each counterpart named in the Settings window really exists.
    @Test func everyOtherDeclarationUsesTheSameConstant() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("ActivityInspector")
        var declarations: [(file: String, key: String)] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            for line in text.split(separator: "\n")
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {   // not doc comments
                guard let open = line.range(of: "@AppStorage("),
                      let close = line[open.upperBound...].firstIndex(of: ")") else { continue }
                declarations.append((name, String(line[open.upperBound..<close])))
            }
        }
        let constants = ["Theme.storageKey": Theme.storageKey, "SaturationLevel.storageKey": SaturationLevel.storageKey,
                         "Bloom.storageKey": Bloom.storageKey, "MenuBarSettings.key": MenuBarSettings.key,
                         "CPUTimeFormat.storageKey": CPUTimeFormat.storageKey]
        // No literal spelling of a shared key anywhere.
        let literals = declarations.filter { decl in Self.keys.contains { decl.key == "\"\($0)\"" } }
        #expect(literals.isEmpty, "\(literals)")
        func files(using constant: String) -> Set<String> {
            Set(declarations.filter { $0.key == constant }.map(\.file))
        }
        #expect(files(using: "Theme.storageKey").isSuperset(of: ["SettingsView.swift", "ContentView.swift"]))
        #expect(files(using: "SaturationLevel.storageKey").isSuperset(of: ["SettingsView.swift", "ContentView.swift", "MenuBarPanel.swift"]))
        #expect(files(using: "Bloom.storageKey").isSuperset(of: ["SettingsView.swift", "ContentView.swift", "MenuBarPanel.swift"]))
        #expect(files(using: "MenuBarSettings.key").isSuperset(of: ["SettingsView.swift", "ActivityInspectorApp.swift"]))
        #expect(files(using: "CPUTimeFormat.storageKey").isSuperset(of: ["SettingsView.swift", "ActivityInspectorApp.swift"]))
        #expect(constants.count == Set(constants.values).count)      // five distinct keys
    }

    /// Settings and the status bar describe the helper in the same words.
    @Test(arguments: [PrivilegedHelperModel.State.running(version: HelperConstants.protocolVersion),
                      .running(version: HelperConstants.protocolVersion - 1), .running(version: nil),
                      .needsApproval, .notInstalled, .notFound])
    func helperStatusMatchesTheStatusBar(state: PrivilegedHelperModel.State) {
        #expect(SettingsView.helperStatus(state) == HelperSummary(state).text)
    }

    @Test func helperStatusTellsTheStatesApart() {
        let texts = [PrivilegedHelperModel.State.running(version: HelperConstants.protocolVersion),
                     .needsApproval, .notInstalled].map(SettingsView.helperStatus)
        #expect(texts == ["Helper running", "Helper waiting for approval", "Helper not installed"])
    }
}
