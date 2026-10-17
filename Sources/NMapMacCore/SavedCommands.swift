import Foundation
import Observation

/// A named nmap command (without targets): a built-in scan type or one the
/// user saved. Built-ins come from Zenmap's scan_profile.usp.
public struct SavedCommand: Hashable, Identifiable, Sendable {
    public var name: String
    public var command: String
    public var description: String

    public var id: String { name }

    public init(name: String, command: String, description: String = "") {
        self.name = name
        self.command = command
        self.description = description
    }
}

/// Reads and writes the INI format of Zenmap's scan_profile.usp.
public enum SavedCommandFile {
    public static func parse(_ text: String) -> [SavedCommand] {
        var commands: [SavedCommand] = []
        var current: SavedCommand?
        var lastKey: String?

        func flush() {
            if let command = current { commands.append(command) }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                flush()
                current = SavedCommand(name: String(line.dropFirst().dropLast()), command: "")
                lastKey = nil
                continue
            }
            // ConfigParser continuation lines start with whitespace.
            if rawLine.first?.isWhitespace == true, let key = lastKey {
                if key == "description" { current?.description += "\n" + line }
                continue
            }
            guard let sep = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else { continue }
            let key = line[..<sep].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            lastKey = key
            switch key {
            case "command": current?.command = value
            case "description": current?.description = value
            default: break
            }
        }
        flush()
        return commands
    }

    public static func serialize(_ commands: [SavedCommand]) -> String {
        commands.map { command in
            let description = command.description
                .components(separatedBy: .newlines)
                .joined(separator: "\n\t")
            return "[\(command.name)]\ncommand = \(command.command)\ndescription = \(description)\n"
        }.joined(separator: "\n")
    }
}

/// Built-in scan types plus the user's own saved commands. Only the user's
/// commands are written to disk; built-ins can't be changed or deleted.
@Observable
public final class SavedCommandStore {
    public let builtIn: [SavedCommand]
    public private(set) var custom: [SavedCommand] = []
    private let fileURL: URL

    public init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("saved_commands.usp"),
                builtIn: [SavedCommand] = SavedCommandStore.bundledCommands) {
        self.fileURL = fileURL
        self.builtIn = builtIn
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            custom = SavedCommandFile.parse(text)
        }
    }

    public static var bundledCommands: [SavedCommand] {
        guard let url = AppResources.url(for: "scan_profile.usp"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return SavedCommandFile.parse(text)
    }

    public var all: [SavedCommand] { builtIn + custom }

    public func command(named name: String) -> SavedCommand? {
        custom.first { $0.name == name } ?? builtIn.first { $0.name == name }
    }

    public func isBuiltIn(_ name: String) -> Bool {
        builtIn.contains { $0.name == name }
    }

    /// Saves (or overwrites) one of the user's commands. Targets are dropped,
    /// since they're chosen separately for each scan.
    public func save(name: String, command: String, description: String = "") throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw SavedCommandError.emptyName }
        guard !isBuiltIn(trimmed) else { throw SavedCommandError.builtInName(trimmed) }
        var options = NmapOptions(commandLine: command)
        options.targets = []
        let saved = SavedCommand(name: trimmed, command: options.commandLine, description: description)
        if let index = custom.firstIndex(where: { $0.name == trimmed }) {
            custom[index] = saved
        } else {
            custom.append(saved)
            custom.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        try persist()
    }

    public func delete(named name: String) throws {
        custom.removeAll { $0.name == name }
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try SavedCommandFile.serialize(custom).write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

public enum SavedCommandError: Error, LocalizedError {
    case emptyName
    case builtInName(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Give the command a name."
        case .builtInName(let name): return "“\(name)” is a built-in scan type. Choose a different name."
        }
    }
}

public enum AppPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("nMapMac", isDirectory: true)
    }

    /// Completed scans are kept here for Search Scan Results (Zenmap uses an SQLite DB).
    public static var scansDirectory: URL {
        supportDirectory.appendingPathComponent("scans", isDirectory: true)
    }
}

public enum AppResources {
    /// In a packaged .app the resource bundle lives in Contents/Resources, where
    /// SwiftPM's generated `Bundle.module` doesn't look; check there first.
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("nMapMac_NMapMacCore.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    public static func url(for name: String) -> URL? {
        bundle.url(forResource: name, withExtension: nil, subdirectory: "Resources")
    }

    public static func pixmap(_ name: String) -> URL? {
        bundle.url(forResource: name, withExtension: "png", subdirectory: "Resources/pixmaps")
    }
}
