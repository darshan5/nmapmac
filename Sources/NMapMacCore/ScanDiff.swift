import Foundation

/// Compares two scans, producing ndiff-style text output. Used by the
/// Compare Results window (zenmapGUI/DiffCompare.py runs ndiff for this).
public enum ScanDiff {
    public enum LineKind: Sendable {
        case context, header, added, removed
    }

    public struct Line: Hashable, Sendable {
        public var kind: LineKind
        public var text: String
    }

    public static func compare(_ a: ScanResult, _ b: ScanResult) -> [Line] {
        var lines: [Line] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"

        func scanLine(_ scan: ScanResult) -> String {
            let when = scan.startTime.map(formatter.string(from:)) ?? "unknown time"
            return "Nmap \(scan.version) scan initiated \(when) as: \(scan.args)"
        }
        let headerA = scanLine(a)
        let headerB = scanLine(b)
        if headerA == headerB {
            lines.append(Line(kind: .context, text: " " + headerA))
        } else {
            lines.append(Line(kind: .removed, text: "-" + headerA))
            lines.append(Line(kind: .added, text: "+" + headerB))
        }
        lines.append(Line(kind: .context, text: ""))

        let hostsA = Dictionary(a.hosts.map { ($0.mergeKey, $0) }, uniquingKeysWith: { $1 })
        let hostsB = Dictionary(b.hosts.map { ($0.mergeKey, $0) }, uniquingKeysWith: { $1 })
        let keys = Set(hostsA.keys).union(hostsB.keys).sorted {
            switch (Inventory.numericKey($0), Inventory.numericKey($1)) {
            case let (x?, y?): return x < y
            default: return $0 < $1
            }
        }

        var changedHosts = 0
        for key in keys {
            let hostLines = diffHost(hostsA[key], hostsB[key])
            guard !hostLines.isEmpty else { continue }
            changedHosts += 1
            lines += hostLines
            lines.append(Line(kind: .context, text: ""))
        }
        if changedHosts == 0 {
            lines.append(Line(kind: .context, text: " No differences between hosts."))
        }
        return lines
    }

    static func diffHost(_ a: NmapHost?, _ b: NmapHost?) -> [Line] {
        var out: [Line] = []
        let name = (b ?? a)!.displayName

        switch (a, b) {
        case (nil, let b?):
            out.append(Line(kind: .added, text: "+\(name):"))
            out.append(Line(kind: .added, text: "+Host is \(b.state)."))
            out += portLines(b).map { Line(kind: .added, text: "+" + $0) }
            return out
        case (let a?, nil):
            out.append(Line(kind: .removed, text: "-\(name):"))
            out.append(Line(kind: .removed, text: "-Host is \(a.state)."))
            out += portLines(a).map { Line(kind: .removed, text: "-" + $0) }
            return out
        case (let a?, let b?):
            var body: [Line] = []
            if a.state != b.state {
                body.append(Line(kind: .removed, text: "-Host is \(a.state)."))
                body.append(Line(kind: .added, text: "+Host is \(b.state)."))
            }
            let portsA = Dictionary(a.ports.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            let portsB = Dictionary(b.ports.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            let ids = Set(portsA.keys).union(portsB.keys).sorted {
                (portsA[$0] ?? portsB[$0])!.portID < (portsA[$1] ?? portsB[$1])!.portID
            }
            var portBody: [Line] = []
            for id in ids {
                let pa = portsA[id].map(portLine)
                let pb = portsB[id].map(portLine)
                if pa == pb { continue }
                if let pa { portBody.append(Line(kind: .removed, text: "-" + pa)) }
                if let pb { portBody.append(Line(kind: .added, text: "+" + pb)) }
            }
            if !portBody.isEmpty {
                body.append(Line(kind: .header, text: " PORT      STATE    SERVICE  VERSION"))
                body += portBody
            }
            let osA = a.osMatches.map(\.name)
            let osB = b.osMatches.map(\.name)
            if osA != osB {
                body.append(Line(kind: .header, text: " OS details:"))
                body += osA.filter { !osB.contains($0) }.map { Line(kind: .removed, text: "-  \($0)") }
                body += osB.filter { !osA.contains($0) }.map { Line(kind: .added, text: "+  \($0)") }
            }
            if body.isEmpty { return [] }
            return [Line(kind: .context, text: " \(name):")] + body
        default:
            return []
        }
    }

    static func portLines(_ host: NmapHost) -> [String] {
        host.ports.map(portLine)
    }

    static func portLine(_ port: NmapPort) -> String {
        let id = "\(port.portID)/\(port.proto)".padding(toLength: 9, withPad: " ", startingAt: 0)
        let state = port.state.padding(toLength: 8, withPad: " ", startingAt: 0)
        let service = port.service.name.padding(toLength: 8, withPad: " ", startingAt: 0)
        return "\(id) \(state) \(service) \(port.service.versionString)"
            .trimmingCharacters(in: .whitespaces)
    }
}
