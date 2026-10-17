import Foundation

/// A tree of the network built from traceroute data, laid out radially
/// around localhost the way RadialNet (zenmap/radialnet) does it.
public struct Topology: Sendable {
    public struct Node: Identifiable, Hashable, Sendable {
        public var id: String
        public var label: String
        /// The scanned host, or nil for intermediate routers and localhost.
        public var host: NmapHost?
        public var parentID: String?
        public var ring: Int
        /// Angle in radians, assigned by `layout`.
        public var angle: Double = 0
        public var isLocalhost: Bool { ring == 0 }
        /// The hop RTT shown on the link to the parent, if known.
        public var rtt: String = ""
    }

    public private(set) var nodes: [String: Node] = [:]
    public private(set) var maxRing = 0
    public static let rootID = "localhost"

    public init(hosts: [NmapHost]) {
        nodes[Self.rootID] = Node(id: Self.rootID, label: "localhost", host: nil, parentID: nil, ring: 0)

        for host in hosts {
            var parent = Self.rootID
            var ring = 0
            let hops = host.trace?.hops.sorted { $0.ttl < $1.ttl } ?? []
            for hop in hops where hop.ipAddress != host.primaryAddress {
                ring = hop.ttl
                // Unknown hops ("*") are kept distinct per path.
                let id = hop.ipAddress.isEmpty ? "\(parent)>*\(hop.ttl)" : hop.ipAddress
                if nodes[id] == nil {
                    nodes[id] = Node(id: id,
                                     label: hop.ipAddress.isEmpty ? "?" : (hop.host.isEmpty ? hop.ipAddress : hop.host),
                                     host: nil, parentID: parent, ring: ring, rtt: hop.rtt)
                }
                parent = id
            }
            let id = host.primaryAddress
            ring = hops.last?.ttl ?? max(host.distance ?? 1, ring + 1)
            if ring == 0 { ring = 1 }
            var node = Node(id: id, label: host.hostname ?? id, host: host, parentID: parent,
                            ring: ring, rtt: hops.last?.rtt ?? "")
            // A scanned host may already exist as a router on another path.
            if let existing = nodes[id] {
                node.parentID = existing.parentID
                node.ring = existing.ring
            }
            nodes[id] = node
        }
        maxRing = nodes.values.map(\.ring).max() ?? 0
        layout()
    }

    public var edges: [(from: Node, to: Node)] {
        nodes.values.compactMap { node in
            guard let parentID = node.parentID, let parent = nodes[parentID] else { return nil }
            return (parent, node)
        }
    }

    public func children(of id: String) -> [Node] {
        nodes.values.filter { $0.parentID == id }.sorted { $0.id < $1.id }
    }

    /// Gives each subtree an angular wedge proportional to its leaf count.
    private mutating func layout() {
        func leaves(_ id: String) -> Int {
            let kids = children(of: id)
            return kids.isEmpty ? 1 : kids.reduce(0) { $0 + leaves($1.id) }
        }
        func place(_ id: String, from start: Double, to end: Double) {
            nodes[id]?.angle = (start + end) / 2
            let kids = children(of: id)
            let total = Double(kids.reduce(0) { $0 + leaves($1.id) })
            var cursor = start
            for kid in kids {
                let span = (end - start) * Double(leaves(kid.id)) / max(total, 1)
                place(kid.id, from: cursor, to: cursor + span)
                cursor += span
            }
        }
        place(Self.rootID, from: 0, to: 2 * .pi)
    }
}
