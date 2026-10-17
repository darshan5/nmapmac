import Foundation

/// Output from an NSE script, attached to a port or a host.
public struct ScriptResult: Hashable, Sendable {
    public var id: String
    public var output: String

    public init(id: String, output: String) {
        self.id = id
        self.output = output
    }
}

public struct Service: Hashable, Sendable {
    public var name: String = ""
    public var product: String = ""
    public var version: String = ""
    public var extraInfo: String = ""
    public var osType: String = ""
    public var method: String = ""
    public var conf: String = ""
    public var tunnel: String = ""

    public init() {}

    /// "product version (extrainfo)" — the VERSION column in Nmap's normal output.
    public var versionString: String {
        var parts: [String] = []
        if !product.isEmpty { parts.append(product) }
        if !version.isEmpty { parts.append(version) }
        if !extraInfo.isEmpty { parts.append("(\(extraInfo))") }
        return parts.joined(separator: " ")
    }
}

public struct NmapPort: Hashable, Identifiable, Sendable {
    public var proto: String
    public var portID: Int
    public var state: String
    public var reason: String = ""
    public var reasonTTL: String = ""
    public var service = Service()
    public var scripts: [ScriptResult] = []

    public var id: String { "\(portID)/\(proto)" }

    public init(proto: String, portID: Int, state: String) {
        self.proto = proto
        self.portID = portID
        self.state = state
    }
}

public struct ExtraPorts: Hashable, Sendable {
    public var state: String
    public var count: Int
}

public struct OSClass: Hashable, Sendable {
    public var type: String = ""
    public var vendor: String = ""
    public var family: String = ""
    public var generation: String = ""
    public var accuracy: Int = 0
    public var cpe: [String] = []
}

public struct OSMatch: Hashable, Sendable {
    public var name: String
    public var accuracy: Int
    public var line: String = ""
    public var classes: [OSClass] = []
}

public struct PortUsed: Hashable, Sendable {
    public var state: String
    public var proto: String
    public var portID: Int
}

public struct SequenceInfo: Hashable, Sendable {
    public var index: String = ""
    public var difficulty: String = ""
    public var classDescription: String = ""
    public var values: String = ""
}

public struct TraceHop: Hashable, Sendable {
    public var ttl: Int
    public var ipAddress: String
    public var rtt: String
    public var host: String
}

public struct Trace: Hashable, Sendable {
    public var port: String = ""
    public var proto: String = ""
    public var hops: [TraceHop] = []
}

public struct Address: Hashable, Sendable {
    public var addr: String
    public var type: String
    public var vendor: String = ""
}

public struct Hostname: Hashable, Sendable {
    public var name: String
    public var type: String
}

public struct NmapHost: Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var state: String = "unknown"
    public var reason: String = ""
    public var addresses: [Address] = []
    public var hostnames: [Hostname] = []
    public var ports: [NmapPort] = []
    public var extraPorts: [ExtraPorts] = []
    public var osMatches: [OSMatch] = []
    public var portsUsed: [PortUsed] = []
    public var uptimeSeconds: Int?
    public var lastBoot: String = ""
    public var distance: Int?
    public var tcpSequence = SequenceInfo()
    public var ipIDSequence = SequenceInfo()
    public var tcpTSSequence = SequenceInfo()
    public var trace: Trace?
    public var hostScripts: [ScriptResult] = []
    public var comment: String = ""
    public var startTime: Date?
    public var endTime: Date?

    public init() {}

    public var ipv4: String? { addresses.first { $0.type == "ipv4" }?.addr }
    public var ipv6: String? { addresses.first { $0.type == "ipv6" }?.addr }
    public var mac: Address? { addresses.first { $0.type == "mac" } }

    /// The address Nmap uses to identify the host (IPv4, then IPv6, then MAC).
    public var primaryAddress: String {
        ipv4 ?? ipv6 ?? mac?.addr ?? ""
    }

    public var hostname: String? { hostnames.first?.name }

    /// Label used in the hosts list, e.g. "scanme.nmap.org (45.33.32.156)".
    public var displayName: String {
        if let name = hostname, !name.isEmpty {
            return "\(name) (\(primaryAddress))"
        }
        return primaryAddress
    }

    public var isUp: Bool { state == "up" }

    public var bestOSMatch: OSMatch? {
        osMatches.max { $0.accuracy < $1.accuracy }
    }

    public func ports(inState state: String) -> [NmapPort] {
        ports.filter { $0.state == state }
    }

    public var openPortCount: Int { ports(inState: "open").count }
    public var filteredPortCount: Int {
        ports(inState: "filtered").count
            + extraPorts.filter { $0.state == "filtered" }.reduce(0) { $0 + $1.count }
    }
    public var closedPortCount: Int {
        ports(inState: "closed").count
            + extraPorts.filter { $0.state == "closed" }.reduce(0) { $0 + $1.count }
    }
    public var scannedPortCount: Int {
        ports.count + extraPorts.reduce(0) { $0 + $1.count }
    }

    /// Identity used when merging the same host across scans.
    public var mergeKey: String { primaryAddress }

    /// OS icon name, following zenmapGUI/Icons.py:get_os.
    public var osIconName: String {
        guard let match = bestOSMatch, let family = match.classes.first?.family else {
            return "unknown"
        }
        if family == "Linux" {
            let name = match.name.lowercased()
            if name.contains("ubuntu") { return "ubuntu" }
            if name.contains("red hat") { return "redhat" }
            return "linux"
        }
        let names = [
            "Windows": "win", "OpenBSD": "openbsd", "FreeBSD": "freebsd",
            "Solaris": "solaris", "OpenSolaris": "solaris", "IRIX": "irix",
            "Mac OS X": "macosx", "Mac OS": "macosx", "macOS": "macosx",
        ]
        return names[family] ?? "default"
    }

    /// Vulnerability level icon name ("vl_1" … "vl_5") based on open ports.
    public var vulnerabilityIconName: String {
        let level = min(openPortCount, 9) / 2 + 1
        return "vl_\(level)"
    }
}

public struct ScanInfo: Hashable, Sendable {
    public var type: String
    public var proto: String
    public var numServices: Int
    public var services: String
}

/// One Nmap run, parsed from its XML output.
public struct ScanResult: Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var scanner: String = "nmap"
    public var args: String = ""
    public var version: String = ""
    public var xmlOutputVersion: String = ""
    public var startTime: Date?
    public var endTime: Date?
    public var elapsed: Double?
    public var summary: String = ""
    public var exitStatus: String = ""
    public var scanInfo: [ScanInfo] = []
    public var verbose: Int = 0
    public var debugging: Int = 0
    public var hostsUp: Int = 0
    public var hostsDown: Int = 0
    public var hostsTotal: Int = 0
    public var hosts: [NmapHost] = []
    public var preScripts: [ScriptResult] = []
    public var postScripts: [ScriptResult] = []
    /// The "normal" Nmap text output, captured live or reconstructed.
    public var normalOutput: String = ""
    /// Zenmap metadata (stored as extra attributes in saved XML).
    public var profileName: String = ""
    public var target: String = ""
    /// The XML document as Nmap produced it; used as the base when saving.
    public var rawXML: Data?

    public init() {}

    public var openPortCount: Int { hosts.reduce(0) { $0 + $1.openPortCount } }
    public var filteredPortCount: Int { hosts.reduce(0) { $0 + $1.filteredPortCount } }
    public var closedPortCount: Int { hosts.reduce(0) { $0 + $1.closedPortCount } }

    /// Short label for scan lists, e.g. "Intense scan on 192.168.1.0/24".
    public var title: String {
        let what = target.isEmpty ? args : target
        if profileName.isEmpty { return what }
        return "\(profileName) on \(what)"
    }
}
