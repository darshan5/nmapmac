import Foundation

/// Keeps a copy of every completed scan so Search Scan Results can find it
/// later. Zenmap stores these in an SQLite database (zenmapCore/UmitDB.py);
/// plain XML files in Application Support serve the same purpose here.
public enum ScanArchive {
    public static func store(_ scan: ScanResult, in directory: URL = AppPaths.scansDirectory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: scan.startTime ?? Date())
        let url = directory.appendingPathComponent("\(stamp)-\(scan.id.uuidString.prefix(8)).xml")
        try NmapXML.data(for: scan).write(to: url, options: .atomic)
        return url
    }

    public struct Entry: Identifiable, Sendable {
        public var url: URL
        public var scan: ScanResult
        public var id: URL { url }

        public init(url: URL, scan: ScanResult) {
            self.url = url
            self.scan = scan
        }
    }

    /// Loads archived scans, newest first. Unreadable files are skipped.
    public static func load(from directory: URL = AppPaths.scansDirectory,
                            olderThan days: Int? = nil) -> [Entry] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        let cutoff = days.map { Date().addingTimeInterval(-Double($0) * 86400) }
        return urls.filter { $0.pathExtension == "xml" }
            .compactMap { url in
                guard let scan = try? NmapXML.parse(contentsOf: url) else { return nil }
                if let cutoff, let start = scan.startTime, start < cutoff { return nil }
                return Entry(url: url, scan: scan)
            }
            .sorted { ($0.scan.startTime ?? .distantPast) > ($1.scan.startTime ?? .distantPast) }
    }

    public static func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
    }
}

/// Recently scanned targets, shown in the Target combo box.
public enum RecentTargets {
    static let key = "recentTargets"
    static let limit = 20

    public static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    public static func add(_ target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = all.filter { $0 != trimmed }
        list.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
