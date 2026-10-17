import Foundation

/// A parsed Nmap command line: an ordered list of options plus targets.
///
/// This is a simplified port of zenmapCore/NmapOptions.py. It understands
/// enough of Nmap's option grammar to round-trip commands between the
/// command entry and the profile editor without losing anything it doesn't
/// recognise.
public struct NmapOptions: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var argument: String?

        public init(name: String, argument: String? = nil) {
            self.name = name
            self.argument = argument
        }
    }

    public var executable = "nmap"
    public var entries: [Entry] = []
    public var targets: [String] = []

    /// Short options whose argument is glued to the option (-PS22,80, -T4, -v3).
    static let attachedArgumentOptions: Set<String> = [
        "-PS", "-PA", "-PU", "-PO", "-PY", "-T", "-v", "-d",
    ]

    /// Options that take their argument as the next token.
    static let separateArgumentOptions: Set<String> = [
        "-sI", "-b", "-D", "-S", "-e", "-g", "-iL", "-iR", "-p", "-oN", "-oX", "-oG",
        "-oA", "-oS", "-oM", "-oH",
        "--script", "--script-args", "--script-args-file", "--script-help",
        "--exclude", "--excludefile", "--exclude-ports", "--source-port", "--ttl",
        "--max-retries", "--host-timeout", "--max-rtt-timeout", "--min-rtt-timeout",
        "--initial-rtt-timeout", "--max-hostgroup", "--min-hostgroup",
        "--max-parallelism", "--min-parallelism", "--max-scan-delay", "--scan-delay",
        "--min-rate", "--max-rate", "--data-length", "--data", "--data-string",
        "--datadir", "--dns-servers", "--spoof-mac", "--mtu", "--proxies", "--top-ports",
        "--port-ratio", "--version-intensity", "--stylesheet", "--resume", "--ip-options",
        "--servicedb", "--versiondb", "--stats-every", "--scanflags", "--script-timeout",
    ]

    public init() {}

    public init(commandLine: String) {
        self.init(arguments: Self.split(commandLine))
    }

    public init(arguments: [String]) {
        var args = arguments[...]
        if let first = args.first, !first.hasPrefix("-"), Self.looksLikeExecutable(first) {
            executable = first
            args = args.dropFirst()
        }
        while let token = args.popFirst() {
            if token == "-" || !token.hasPrefix("-") {
                targets.append(token)
                continue
            }
            if token.hasPrefix("--") {
                if let eq = token.firstIndex(of: "=") {
                    entries.append(Entry(name: String(token[..<eq]),
                                         argument: String(token[token.index(after: eq)...])))
                } else if Self.separateArgumentOptions.contains(token), let next = args.first {
                    args = args.dropFirst()
                    entries.append(Entry(name: token, argument: next))
                } else {
                    entries.append(Entry(name: token))
                }
                continue
            }
            entries.append(contentsOf: Self.parseShort(token, rest: &args))
        }
    }

    private static func looksLikeExecutable(_ token: String) -> Bool {
        let base = (token as NSString).lastPathComponent.lowercased()
        return base == "nmap" || base == "nmap.exe" || base == "sudo"
    }

    private static func parseShort(_ token: String, rest: inout ArraySlice<String>) -> [Entry] {
        // -sI zombie, -oX file, -iL file: two-letter options with a separate argument.
        let two = String(token.prefix(3))
        if token.count > 3, separateArgumentOptions.contains(two) {
            return [Entry(name: two, argument: String(token.dropFirst(3)))]
        }
        if separateArgumentOptions.contains(token) {
            if let next = rest.first {
                rest = rest.dropFirst()
                return [Entry(name: token, argument: next)]
            }
            return [Entry(name: token)]
        }
        if token.hasPrefix("-P"), token.count >= 3 {
            let name = String(token.prefix(3))
            let arg = String(token.dropFirst(3))
            return [Entry(name: name, argument: arg.isEmpty ? nil : arg)]
        }
        if token.hasPrefix("-T"), token.count > 2 {
            return [Entry(name: "-T", argument: String(token.dropFirst(2)))]
        }
        if token.hasPrefix("-v") || token.hasPrefix("-d"), token.count > 2 {
            let name = String(token.prefix(2))
            let tail = token.dropFirst(2)
            let letter = name.last!
            if tail.allSatisfy({ $0 == letter }) {
                return [Entry(name: name, argument: String(tail.count + 1))]
            }
            return [Entry(name: name, argument: String(tail))]
        }
        if token.hasPrefix("-p"), token.count > 2 {
            return [Entry(name: "-p", argument: String(token.dropFirst(2)))]
        }
        // -sSV is shorthand for -sS -sV.
        if token.hasPrefix("-s"), token.count > 3 {
            return token.dropFirst(2).map { Entry(name: "-s\($0)") }
        }
        return [Entry(name: token)]
    }

    // MARK: - Querying and editing

    public func has(_ name: String) -> Bool {
        entries.contains { $0.name == name }
    }

    public func argument(for name: String) -> String? {
        entries.first { $0.name == name }?.argument
    }

    /// Adds the option or replaces the argument of an existing one.
    public mutating func set(_ name: String, argument: String? = nil) {
        let arg = argument.flatMap { $0.isEmpty ? nil : $0 }
        if let index = entries.firstIndex(where: { $0.name == name }) {
            entries[index].argument = arg
        } else {
            entries.append(Entry(name: name, argument: arg))
        }
    }

    public mutating func remove(_ name: String) {
        entries.removeAll { $0.name == name }
    }

    // MARK: - Rendering

    public var arguments: [String] {
        var out: [String] = []
        for entry in entries {
            guard let arg = entry.argument, !arg.isEmpty else {
                out.append(entry.name)
                continue
            }
            if entry.name.hasPrefix("--") {
                out.append(entry.name)
                out.append(arg)
            } else if Self.attachedArgumentOptions.contains(entry.name) {
                out.append(entry.name + arg)
            } else {
                out.append(entry.name)
                out.append(arg)
            }
        }
        return out + targets
    }

    /// The full command line, quoted for display and re-parsing.
    public var commandLine: String {
        ([executable] + arguments).map(Self.quote).joined(separator: " ")
    }

    // MARK: - Shell-style word splitting

    public static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escape = false
        for ch in line {
            if escape {
                current.append(ch)
                escape = false
                continue
            }
            if let q = quote {
                if ch == q {
                    quote = nil
                } else if ch == "\\" && q == "\"" {
                    escape = true
                } else {
                    current.append(ch)
                }
                continue
            }
            switch ch {
            case "\"", "'":
                quote = ch
                inWord = true
            case "\\":
                escape = true
                inWord = true
            case " ", "\t", "\n":
                if inWord {
                    words.append(current)
                    current = ""
                    inWord = false
                }
            default:
                current.append(ch)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }

    public static func quote(_ word: String) -> String {
        if word.isEmpty { return "\"\"" }
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./,:=@%+[]"))
        if word.unicodeScalars.allSatisfy(safe.contains) { return word }
        return "\"" + word.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
