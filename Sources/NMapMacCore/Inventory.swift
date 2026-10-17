import Foundation

/// Hosts from every scan open in a window, merged by address. When the same
/// host appears in several scans, the most recent scan's view of it wins
/// (zenmapCore/NetworkInventory.py).
public struct Inventory: Sendable {
    public struct ServiceEntry: Hashable, Identifiable, Sendable {
        public var host: NmapHost
        public var port: NmapPort
        public var id: String { "\(host.mergeKey)|\(port.id)" }
    }

    public private(set) var hosts: [NmapHost] = []

    public init(scans: [ScanResult]) {
        var byKey: [String: (host: NmapHost, time: Date)] = [:]
        var order: [String] = []
        for (index, scan) in scans.enumerated() {
            // Fall back to load order for scans without timestamps.
            let time = scan.startTime ?? Date(timeIntervalSince1970: Double(index))
            for host in scan.hosts where host.isUp {
                let key = host.mergeKey
                if let existing = byKey[key] {
                    if time >= existing.time { byKey[key] = (host, time) }
                } else {
                    byKey[key] = (host, time)
                    order.append(key)
                }
            }
        }
        hosts = order.compactMap { byKey[$0]?.host }.sorted(by: Self.addressOrder)
    }

    /// Service names with the (host, port) pairs offering them, open ports first.
    public var services: [String: [ServiceEntry]] {
        var out: [String: [ServiceEntry]] = [:]
        for host in hosts {
            for port in host.ports {
                let name = port.service.name.isEmpty ? "unknown" : port.service.name
                out[name, default: []].append(ServiceEntry(host: host, port: port))
            }
        }
        return out
    }

    public var serviceNames: [String] {
        services.keys.sorted()
    }

    /// Sorts IPv4 addresses numerically, everything else lexically after them.
    static func addressOrder(_ a: NmapHost, _ b: NmapHost) -> Bool {
        let ka = numericKey(a.primaryAddress)
        let kb = numericKey(b.primaryAddress)
        switch (ka, kb) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.primaryAddress < b.primaryAddress
        }
    }

    static func numericKey(_ address: String) -> UInt32? {
        let parts = address.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        return parts.reduce(0) { $0 << 8 | $1 }
    }
}
