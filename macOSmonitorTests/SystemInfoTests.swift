import Testing
import Foundation
@testable import macOSmonitor

/// System Info is built on `system_profiler -json`: a catalog of its data types, a parser that
/// turns each into a tree with Apple's own labels, and a model that loads them on demand.
struct SystemInfoCatalogTests {
    @Test func threeCategoriesInOrder() {
        #expect(SystemInfoCategory.allCases.map(\.title) == ["Hardware", "Network", "Software"])
    }

    @Test func everyItemIsADistinctDataTypeInSomeCategory() {
        let ids = SystemInfoItem.catalog.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.hasPrefix("SP") && $0.hasSuffix("DataType") })
        for category in SystemInfoCategory.allCases {
            #expect(!SystemInfoItem.catalog.filter { $0.category == category }.isEmpty, "\(category)")
        }
        #expect(SystemInfoItem.catalog.first?.id == "SPHardwareDataType")
    }

    @Test func theSlowTypesAreMarkedSoTheyAreLoadedOnlyWhenAsked() {
        let slow = Set(SystemInfoItem.catalog.filter(\.isSlow).map(\.id))
        #expect(slow == ["SPAirPortDataType", "SPFontsDataType", "SPLogsDataType",
                         "SPApplicationsDataType", "SPFrameworksDataType"])
        #expect(SystemInfoItem.catalog.first { $0.id == "SPAirPortDataType" }?.expectedSeconds == 20)
    }
}

struct ProfilerParserTests {
    private let labels = ProfilerLabels(table: [
        "coreaudio_device": "Devices",
        "coreaudio_device_manufacturer": "Manufacturer",
        "coreaudio_device_srate": "Current SampleRate",
        "coreaudio_device_transport": "Transport",
        "coreaudio_device_type_usb": "USB",
    ])

    private func parse(_ json: String) -> [ProfilerNode]? {
        ProfilerParser.parse(Data(json.utf8), type: "SPAudioDataType", labels: labels)
    }

    @Test func keysAndValuesUseApplesLabels() throws {
        let nodes = try #require(parse("""
            {"SPAudioDataType":[{"_name":"coreaudio_device","_items":[{"_name":"Studio Display Speakers",
              "coreaudio_device_manufacturer":"Apple Inc.","coreaudio_device_srate":48000,
              "coreaudio_device_transport":"coreaudio_device_type_usb"}]}]}
            """))
        #expect(nodes.map(\.title) == ["Devices"])
        let speakers = try #require(nodes.first?.children.first)
        #expect(speakers.title == "Studio Display Speakers")
        // Leaves alphabetically by label; the transport's value is itself translated.
        #expect(speakers.children.map(\.title) == ["Current SampleRate", "Manufacturer", "Transport"])
        #expect(speakers.children.map(\.value) == ["48000", "Apple Inc.", "USB"])
    }

    @Test func internalKeysAreSkipped() throws {
        let nodes = try #require(parse("""
            {"SPAudioDataType":[{"_name":"Thing","_properties":{"x":1},"_order":"1","coreaudio_device_manufacturer":"A"}]}
            """))
        #expect(nodes.first?.children.map(\.title) == ["Manufacturer"])
    }

    @Test func nestedDictionariesBecomeGroupsAndListsJoin() throws {
        let nodes = try #require(parse("""
            {"SPAudioDataType":[{"_name":"Thing","ipv4":{"addresses":["10.0.0.2","10.0.0.3"]},"name":"x"}]}
            """))
        let thing = try #require(nodes.first)
        // Plain values before groups.
        #expect(thing.children.map(\.title) == ["Name", "Ipv4"])
        let group = thing.children[1]
        #expect(group.value == nil)
        #expect(group.children.first?.title == "Addresses")
        #expect(group.children.first?.value == "10.0.0.2, 10.0.0.3")
    }

    @Test func aNamelessTopItemTakesThePagesName() throws {
        let nodes = try #require(ProfilerParser.parse(Data(#"{"SPBluetoothDataType":[{"x":"1"}]}"#.utf8),
                                                       type: "SPBluetoothDataType", labels: labels))
        #expect(nodes.first?.title == "Bluetooth")
    }

    @Test func theCoreCountReadsAsAppleWritesIt() {
        #expect(ProfilerParser.coreCountText("proc 12:0:6:6") == "12 (6 Performance and 6 Efficiency)")
        #expect(ProfilerParser.coreCountText("proc 16:0:12:4") == "16 (12 Performance and 4 Efficiency)")
        #expect(ProfilerParser.coreCountText("8") == nil)
        #expect(ProfilerParser.coreCountText("proc 12:0:6") == nil)
    }

    @Test func unknownKeysAreTidiedNotShownRaw() {
        #expect(labels.label("some_unknown_key") == "Some unknown key")
        #expect(labels.label("Already Nice") == "Already Nice")
        #expect(labels.label("platform_UUID") == "Platform UUID")
    }

    @Test func anEmptyTypeHasNoNodes() {
        #expect(parse(#"{"SPAudioDataType":[]}"#) == [])
    }

    @Test func unreadableOutputIsNil() {
        #expect(parse("not json") == nil)
        #expect(parse(#"{"SomethingElse":[]}"#) == nil)
    }

    @Test func identifyingValuesAreMarkedSensitive() throws {
        for key in ["serial_number", "platform_UUID", "provisioning_UDID", "spethernet_mac_address",
                    "MAC Address", "hardware_address", "controller_address", "device_address",
                    "sppower_battery_serial_number", "USBDeviceKeySerialNumber", "user_name"] {
            #expect(ProfilerNode.isSensitive(key: key), "\(key)")
        }
        for key in ["spext_load_address", "coreaudio_device_srate", "machine_model", "DestinationAddress"] {
            #expect(!ProfilerNode.isSensitive(key: key), "\(key)")
        }
        let nodes = try #require(parse(#"{"SPAudioDataType":[{"_name":"Mac","serial_number":"ABC","chip":"M3"}]}"#))
        #expect(nodes.first?.children.first { $0.title == "Serial number" }?.isSensitive == true)
        #expect(nodes.first?.children.first { $0.title == "Chip" }?.isSensitive == false)
    }
}

/// Runs against this Mac's own label tables.
struct ProfilerLabelsSystemTests {
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/System/Library/SystemProfiler")))
    func appleLabelTablesLoad() {
        let labels = ProfilerLabels.system(languages: ["en"])
        #expect(labels.label("coreaudio_device_manufacturer") == "Manufacturer")
        #expect(labels.label("coreaudio_device_output") == "Output Channels")
    }
}

final class FakeProfilerRunner: SystemProfilerRunning, @unchecked Sendable {
    private let lock = NSLock()
    var outputs: [String: Data] = [:]
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }
    func run(_ type: String) async -> Data? {
        lock.withLock { _calls.append(type) }
        return outputs[type]
    }
}

@MainActor
struct SystemInfoModelTests {
    private func json(_ type: String, items: String) -> Data { Data(#"{"\#(type)":[\#(items)]}"#.utf8) }

    private func model() -> (SystemInfoModel, FakeProfilerRunner) {
        let runner = FakeProfilerRunner()
        for item in SystemInfoItem.catalog {
            runner.outputs[item.id] = json(item.id, items: #"{"_name":"x","a":"1"}"#)
        }
        runner.outputs["SPFibreChannelDataType"] = json("SPFibreChannelDataType", items: "")
        return (SystemInfoModel(runner: runner, labels: ProfilerLabels(table: [:])), runner)
    }

    @Test func preloadReadsTheFastTypesOnlyAndHidesEmptyOnes() async {
        let (model, runner) = model()
        await model.preload()
        let slow = Set(SystemInfoItem.catalog.filter(\.isSlow).map(\.id))
        #expect(Set(runner.calls).isDisjoint(with: slow))
        #expect(runner.calls.count == SystemInfoItem.catalog.count - slow.count)
        let visible = SystemInfoCategory.allCases.flatMap { model.visibleItems(in: $0) }.map(\.id)
        #expect(!visible.contains("SPFibreChannelDataType"))      // empty on this Mac
        #expect(visible.contains("SPAirPortDataType"))            // slow: listed, not yet read
    }

    @Test func anItemIsReadOnceThenReloadReadsAgain() async {
        let (model, runner) = model()
        await model.load("SPAirPortDataType")
        await model.load("SPAirPortDataType")
        #expect(runner.calls.filter { $0 == "SPAirPortDataType" }.count == 1)
        guard case .loaded(let nodes) = model.state(of: "SPAirPortDataType") else {
            Issue.record("not loaded"); return
        }
        #expect(nodes.first?.title == "x")
        await model.load("SPAirPortDataType", force: true)
        #expect(runner.calls.filter { $0 == "SPAirPortDataType" }.count == 2)
    }

    @Test func aFailedReadSaysSoAndStaysListed() async {
        let (model, runner) = model()
        runner.outputs["SPAudioDataType"] = nil
        await model.load("SPAudioDataType")
        #expect(model.state(of: "SPAudioDataType") == .failed)
        #expect(model.visibleItems(in: .hardware).contains { $0.id == "SPAudioDataType" })
    }
}
