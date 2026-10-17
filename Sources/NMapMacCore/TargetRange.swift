import Darwin
import Foundation

/// An IPv4 address as a 32-bit number, so ranges can be computed.
public struct IPv4: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var value: UInt32

    public init(_ value: UInt32) {
        self.value = value
    }

    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet < 256 else { return nil }
            value = value << 8 | octet
        }
        self.value = value
    }

    public var octets: [UInt32] {
        [value >> 24, value >> 16 & 255, value >> 8 & 255, value & 255]
    }

    public var description: String {
        octets.map(String.init).joined(separator: ".")
    }

    public static func < (a: IPv4, b: IPv4) -> Bool { a.value < b.value }
}

/// Plain-language helpers for building and explaining Nmap target specs, so
/// users can think in "from this address to that one" instead of netmasks.
public enum TargetRange {
    /// Nmap target text covering exactly `start...end`.
    ///
    /// Ranges inside one last octet become `192.168.1.10-50`; anything wider
    /// is split into the fewest CIDR blocks (`10.0.0.0/23 10.0.2.0/24`).
    public static func spec(from start: IPv4, to end: IPv4) -> String {
        let (lo, hi) = start <= end ? (start, end) : (end, start)
        if lo == hi { return lo.description }
        if lo.value >> 8 == hi.value >> 8 {
            return "\(lo.description)-\(hi.octets[3])"
        }
        var blocks: [String] = []
        var cursor = UInt64(lo.value)
        let last = UInt64(hi.value)
        while cursor <= last {
            // Largest aligned block starting at cursor that doesn't pass `last`.
            var size: UInt64 = cursor == 0 ? 1 << 32 : cursor & (~cursor + 1)
            while cursor + size - 1 > last { size >>= 1 }
            let prefix = 32 - size.trailingZeroBitCount
            let base = IPv4(UInt32(cursor))
            blocks.append(prefix == 32 ? base.description : "\(base)/\(prefix)")
            cursor += size
        }
        return blocks.joined(separator: " ")
    }

    /// The network containing `address` with the given netmask, as start/end/CIDR.
    public static func network(address: IPv4, netmask: IPv4) -> (start: IPv4, end: IPv4, cidr: String) {
        let start = IPv4(address.value & netmask.value)
        let end = IPv4(start.value | ~netmask.value)
        let prefix = netmask.value.nonzeroBitCount
        return (start, end, "\(start)/\(prefix)")
    }

    // MARK: - Explaining a target

    public struct Summary: Equatable, Sendable {
        /// Number of addresses Nmap will consider (nil if any part is a host name we can't count).
        public var addressCount: Int?
        public var first: String?
        public var last: String?
        public var hostNames: [String]
        public var invalid: [String]

        public var description: String {
            var parts: [String] = []
            if let count = addressCount, count > 0 {
                let noun = count == 1 ? "address" : "addresses"
                if let first, let last, first != last {
                    parts.append("\(count.formatted()) \(noun) (\(first) – \(last))")
                } else {
                    parts.append("\(count.formatted()) \(noun)")
                }
            }
            if !hostNames.isEmpty {
                parts.append(hostNames.count == 1 ? "host \(hostNames[0])" : "\(hostNames.count) host names")
            }
            if !invalid.isEmpty {
                parts.append("can't understand: \(invalid.joined(separator: ", "))")
            }
            return parts.joined(separator: " + ")
        }
    }

    /// Counts the addresses in a target string (CIDR, dash/comma octet ranges,
    /// `*` wildcards, single IPs) and lists anything that's a host name.
    public static func summarize(_ targets: String) -> Summary {
        var total = 0
        var first: IPv4?
        var last: IPv4?
        var names: [String] = []
        var invalid: [String] = []

        for word in NmapOptions.split(targets) {
            if let range = expand(word) {
                total += range.count
                first = min(first ?? range.first, range.first)
                last = max(last ?? range.last, range.last)
            } else if looksLikeHostName(word) {
                names.append(word)
            } else {
                invalid.append(word)
            }
        }
        return Summary(addressCount: total, first: first?.description, last: last?.description,
                       hostNames: names, invalid: invalid)
    }

    struct Expanded {
        var count: Int
        var first: IPv4
        var last: IPv4
    }

    static func expand(_ word: String) -> Expanded? {
        // CIDR: 192.168.1.0/24 (also allowed on host names, which we can't count).
        if let slash = word.firstIndex(of: "/") {
            guard let base = IPv4(String(word[..<slash])),
                  let prefix = Int(word[word.index(after: slash)...]), (0...32).contains(prefix)
            else { return nil }
            let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
            let net = network(address: base, netmask: IPv4(mask))
            return Expanded(count: Int(UInt64(net.end.value) - UInt64(net.start.value) + 1),
                            first: net.start, last: net.end)
        }
        // Octet ranges: 192.168.1-3.1-254, 10.0.0.1,5,9, 192.168.*.1
        let parts = word.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var lists: [[UInt32]] = []
        for part in parts {
            guard let values = octetValues(String(part)) else { return nil }
            lists.append(values)
        }
        let count = lists.reduce(1) { $0 * $1.count }
        let first = IPv4(lists.reduce(0) { $0 << 8 | $1.min()! })
        let last = IPv4(lists.reduce(0) { $0 << 8 | $1.max()! })
        return Expanded(count: count, first: first, last: last)
    }

    static func octetValues(_ part: String) -> [UInt32]? {
        if part == "*" { return Array(0...255) }
        var values = Set<UInt32>()
        for piece in part.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = piece.split(separator: "-", omittingEmptySubsequences: false)
            switch bounds.count {
            case 1:
                guard let v = UInt32(bounds[0]), v < 256 else { return nil }
                values.insert(v)
            case 2:
                // "-5" means 0-5 and "250-" means 250-255, as in Nmap.
                let lo = bounds[0].isEmpty ? 0 : UInt32(bounds[0])
                let hi = bounds[1].isEmpty ? 255 : UInt32(bounds[1])
                guard let lo, let hi, lo <= hi, hi < 256 else { return nil }
                values.formUnion(lo...hi)
            default:
                return nil
            }
        }
        return values.isEmpty ? nil : values.sorted()
    }

    static func looksLikeHostName(_ word: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_:"))
        return word.rangeOfCharacter(from: .letters) != nil
            && word.unicodeScalars.allSatisfy(allowed.contains)
    }
}

/// The Mac's own IPv4 networks, for the "My network" shortcut.
public struct LocalNetwork: Hashable, Identifiable, Sendable {
    public var interface: String
    public var address: IPv4
    public var netmask: IPv4

    public var id: String { "\(interface) \(address)" }
    public var range: (start: IPv4, end: IPv4, cidr: String) {
        TargetRange.network(address: address, netmask: netmask)
    }
    public var addressCount: Int { Int(UInt64(range.end.value) - UInt64(range.start.value) + 1) }

    /// en0 is usually Wi-Fi on laptops and Ethernet on desktops; others are named as-is.
    public var friendlyName: String {
        switch interface {
        case "en0": return "Wi-Fi / Ethernet (en0)"
        case let name where name.hasPrefix("en"): return "Network adapter (\(name))"
        case let name where name.hasPrefix("bridge"): return "Bridge (\(name))"
        case let name where name.hasPrefix("utun"), let name where name.hasPrefix("ipsec"):
            return "VPN (\(name))"
        default: return interface
        }
    }

    public static func current() -> [LocalNetwork] {
        var result: [LocalNetwork] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var cursor = head
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let mask = entry.ifa_netmask
            else { continue }
            func ipv4(_ sa: UnsafeMutablePointer<sockaddr>) -> IPv4 {
                sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    IPv4(UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
                }
            }
            let address = ipv4(addr)
            // Skip link-local (169.254.x.x) self-assigned addresses.
            if address.octets[0] == 169 && address.octets[1] == 254 { continue }
            result.append(LocalNetwork(interface: String(cString: entry.ifa_name),
                                       address: address, netmask: ipv4(mask)))
        }
        return result.sorted { $0.interface < $1.interface }
    }
}
