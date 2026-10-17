import Foundation

/// Zenmap's search/filter syntax (see zenmapCore/SearchResult.py):
/// plain words match anywhere; `key:value` terms match specific fields.
///
///     apache os:linux open:22,80 target:192.168.1
///
/// NmapHost keys: keyword, os, target (host), open, closed, filtered, scanned,
/// service, product, inroute (in_route). Scan-only keys: profile, option,
/// date, after, before.
public struct SearchQuery: Equatable, Sendable {
    public struct Term: Equatable, Sendable {
        public var key: String
        public var value: String
    }

    public var terms: [Term]

    public static let hostKeys: Set<String> = [
        "keyword", "os", "target", "host", "open", "closed", "filtered", "scanned",
        "service", "product", "inroute", "in_route",
    ]
    public static let scanKeys: Set<String> = ["profile", "option", "date", "after", "before"]

    public init(_ text: String) {
        terms = NmapOptions.split(text).compactMap { word in
            if let colon = word.firstIndex(of: ":") {
                let key = word[..<colon].lowercased()
                if Self.hostKeys.contains(key) || Self.scanKeys.contains(key) {
                    return Term(key: key, value: String(word[word.index(after: colon)...]))
                }
            }
            return word.isEmpty ? nil : Term(key: "keyword", value: word)
        }
    }

    public var isEmpty: Bool { terms.isEmpty }

    // MARK: - Hosts

    public func matches(_ host: NmapHost) -> Bool {
        terms.filter { Self.hostKeys.contains($0.key) }.allSatisfy { Self.match(term: $0, host: host) }
    }

    static func match(term: Term, host: NmapHost) -> Bool {
        let value = term.value.lowercased()
        switch term.key {
        case "keyword":
            return hostKeywordFields(host).contains { $0.lowercased().contains(value) }
        case "os":
            return host.osMatches.contains { match in
                match.name.lowercased().contains(value)
                    || match.classes.contains {
                        [$0.vendor, $0.family, $0.generation, $0.type]
                            .contains { $0.lowercased().contains(value) }
                    }
            }
        case "target", "host":
            return host.addresses.contains { $0.addr.lowercased().contains(value) }
                || host.hostnames.contains { $0.name.lowercased().contains(value) }
        case "open", "closed", "filtered":
            return matchPorts(value, in: host.ports.filter { $0.state.contains(term.key) })
        case "scanned":
            return matchPorts(value, in: host.ports)
        case "service":
            return host.ports.contains { $0.service.name.lowercased().contains(value) }
        case "product":
            return host.ports.contains {
                $0.service.versionString.lowercased().contains(value)
            }
        case "inroute", "in_route":
            return host.trace?.hops.contains {
                $0.ipAddress.contains(value) || $0.host.lowercased().contains(value)
            } ?? false
        default:
            return true
        }
    }

    /// "22,80" requires each listed port; an empty value means "any".
    static func matchPorts(_ value: String, in ports: [NmapPort]) -> Bool {
        let wanted = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if wanted.isEmpty { return !ports.isEmpty }
        let ids = Set(ports.map(\.portID))
        return wanted.allSatisfy(ids.contains)
    }

    static func hostKeywordFields(_ host: NmapHost) -> [String] {
        var fields = host.addresses.flatMap { [$0.addr, $0.vendor] }
        fields += host.hostnames.map(\.name)
        fields += host.osMatches.map(\.name)
        fields += host.ports.flatMap { [$0.service.name, $0.service.versionString] }
        fields.append(host.comment)
        return fields
    }

    // MARK: - Scans

    /// A scan matches if its scan-level terms match and at least one host
    /// matches all host-level terms (or there are no host terms).
    public func matches(_ scan: ScanResult) -> Bool {
        for term in terms where Self.scanKeys.contains(term.key) {
            guard Self.match(term: term, scan: scan) else { return false }
        }
        let hostTerms = terms.filter { Self.hostKeys.contains($0.key) }
        if hostTerms.isEmpty { return true }
        return scan.hosts.contains { host in
            hostTerms.allSatisfy { term in
                if term.key == "keyword" {
                    let value = term.value.lowercased()
                    return Self.match(term: term, host: host)
                        || scan.profileName.lowercased().contains(value)
                        || scan.args.lowercased().contains(value)
                }
                return Self.match(term: term, host: host)
            }
        }
    }

    static func match(term: Term, scan: ScanResult) -> Bool {
        let value = term.value.lowercased()
        switch term.key {
        case "profile":
            return scan.profileName.lowercased().contains(value)
        case "option":
            let options = NmapOptions(commandLine: scan.args)
            return options.entries.contains { $0.name.lowercased() == value || $0.name.lowercased().hasSuffix(value) }
        case "date", "after", "before":
            guard let start = scan.startTime else { return false }
            return matchDate(term.key, value, start)
        default:
            return true
        }
    }

    /// Dates are YYYY-MM-DD; `date:` also accepts a trailing `~N` fuzz in days,
    /// and `after:`/`before:` accept a bare number of days ago.
    static func matchDate(_ key: String, _ value: String, _ date: Date) -> Bool {
        let calendar = Calendar.current
        let parts = value.split(separator: "~", maxSplits: 1)
        let fuzz = parts.count > 1 ? Int(parts[1]) ?? 1 : 0

        let reference: Date
        if let days = Int(parts.first ?? ""), key != "date" {
            reference = calendar.startOfDay(for: Date()).addingTimeInterval(-Double(days) * 86400)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            guard let parsed = formatter.date(from: String(parts.first ?? "")) else { return false }
            reference = parsed
        }
        let day = calendar.startOfDay(for: date)
        switch key {
        case "after": return day >= reference
        case "before": return day < reference
        default:
            let diff = abs(calendar.dateComponents([.day], from: reference, to: day).day ?? .max)
            return diff <= fuzz
        }
    }
}
