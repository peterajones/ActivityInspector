import Foundation
import IOKit
import IOKit.storage

/// Every disk's cumulative counters, summed: bytes moved, time spent on requests, and requests.
struct DiskCounters: Equatable, Sendable {
    var read: UInt64
    var written: UInt64
    /// Nanoseconds spent on reads and writes (the driver's "Total Time").
    var busyNanos: UInt64 = 0
    var operations: UInt64 = 0
}

/// The startup volume's size and free space, in bytes.
struct VolumeCapacity: Equatable, Sendable {
    let total: UInt64
    let available: UInt64

    var totalText: String { Self.decimal(total) }
    var availableText: String { Self.decimal(available) }

    /// Decimal units, as Finder shows disk sizes: "994.7 GB", "1.7 TB".
    nonisolated static func decimal(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1e12 { return String(format: "%.1f TB", value / 1e12) }
        return String(format: "%.1f GB", value / 1e9)
    }
}

/// Disk counters and capacity, isolated behind a protocol so the sampler can use a fake.
protocol DiskStatsProviding: Sendable {
    func counters() -> DiskCounters?
    func startupVolume() -> VolumeCapacity?
}

struct DiskStats: DiskStatsProviding {
    func counters() -> DiskCounters? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching(kIOBlockStorageDriverClass),
                                           &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var total = DiskCounters(read: 0, written: 0)
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }        // every matched service must be released
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties,
                                                    kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let statistics = dictionary[kIOBlockStorageDriverStatisticsKey]
                    as? [String: Any]
            else { continue }
            func value(_ key: String) -> UInt64 { (statistics[key] as? UInt64) ?? 0 }
            // 64-bit counters: a machine with any history reads well past 4 GB.
            total.read += value(kIOBlockStorageDriverStatisticsBytesReadKey)
            total.written += value(kIOBlockStorageDriverStatisticsBytesWrittenKey)
            total.busyNanos += value(kIOBlockStorageDriverStatisticsTotalReadTimeKey)
                + value(kIOBlockStorageDriverStatisticsTotalWriteTimeKey)
            total.operations += value(kIOBlockStorageDriverStatisticsReadsKey)
                + value(kIOBlockStorageDriverStatisticsWritesKey)
        }
        return total
    }

    func startupVolume() -> VolumeCapacity? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value
        else { return nil }
        return VolumeCapacity(total: total, available: free)
    }
}
