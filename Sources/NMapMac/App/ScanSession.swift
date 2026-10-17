import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import NMapMacCore

enum SidebarMode: String, CaseIterable, Identifiable {
    case hosts = "Hosts"
    case services = "Services"
    var id: String { rawValue }
}

enum DetailTab: String, CaseIterable, Identifiable {
    case output = "Nmap Output"
    case details = "Host Details"
    case topology = "Topology"
    case scans = "Scans"
    var id: String { rawValue }
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var offerPrivileged = false
}

/// State for one main window: its scans, the target/command bar and
/// what's selected. Corresponds to zenmapGUI/ScanInterface.py.
@MainActor
@Observable
final class ScanSession {
    let commands: SavedCommandStore

    var jobs: [ScanJob] = []
    var target = "" {
        didSet { if target != oldValue { syncCommandTargets() } }
    }
    var command = ""

    var selectedJobID: UUID?
    var sidebarMode: SidebarMode = .hosts
    var selectedHostKeys: Set<String> = []
    var selectedService: String?
    var tab: DetailTab = .output
    var filterText = ""
    var alert: AlertInfo?
    /// Shows the "Save Current Command" prompt.
    var isSavingCommand = false
    /// The saved command most recently picked, so edits to it can be saved back.
    var lastUsedCommandName: String?

    init(commands: SavedCommandStore) {
        self.commands = commands
        if let initial = commands.command(named: "Intense scan") ?? commands.all.first {
            use(initial)
        }
    }

    // MARK: - Derived data

    var results: [ScanResult] { jobs.compactMap(\.result) }
    var inventory: Inventory { Inventory(scans: results) }

    var visibleHosts: [NmapHost] {
        let query = SearchQuery(filterText)
        let hosts = inventory.hosts
        return query.isEmpty ? hosts : hosts.filter(query.matches)
    }

    var selectedHosts: [NmapHost] {
        visibleHosts.filter { selectedHostKeys.contains($0.mergeKey) }
    }

    var selectedJob: ScanJob? {
        jobs.first { $0.id == selectedJobID } ?? jobs.last
    }

    var runningCount: Int { jobs.filter(\.isRunning).count }
    var isEmpty: Bool { jobs.isEmpty }

    // MARK: - Command bar

    /// Loads a saved command (or built-in scan type), keeping the current targets.
    func use(_ saved: SavedCommand) {
        var options = NmapOptions(commandLine: saved.command)
        options.targets = NmapOptions.split(target)
        command = options.commandLine
        lastUsedCommandName = saved.name
    }

    /// The saved command the command field currently matches, ignoring targets;
    /// nil once the user has modified it.
    var currentSavedCommand: SavedCommand? {
        var current = NmapOptions(commandLine: command)
        current.targets = []
        return commands.all.reversed().first { saved in
            var options = NmapOptions(commandLine: saved.command)
            options.targets = []
            return options == current
        }
    }

    /// Name recorded with scans, e.g. "Quick scan" or "Custom command".
    var commandName: String {
        currentSavedCommand?.name ?? "Custom command"
    }

    private func syncCommandTargets() {
        var options = NmapOptions(commandLine: command)
        options.targets = NmapOptions.split(target)
        command = options.commandLine
    }

    /// Called when the user edits the command directly: keep the target field in step.
    func commandEdited() {
        let targets = NmapOptions(commandLine: command).targets
        if targets != NmapOptions.split(target) {
            // Avoid re-writing the command the user is typing.
            withoutCommandSync { target = targets.joined(separator: " ") }
        }
    }

    private func withoutCommandSync(_ body: () -> Void) {
        let saved = command
        body()
        command = saved
    }

    // MARK: - Scanning

    func startScan(privileged: Bool) {
        let options = NmapOptions(commandLine: command)
        guard !options.targets.isEmpty || options.has("-iL") || options.has("-iR") else {
            alert = AlertInfo(title: "No target", message: "Enter a target host or network to scan, for example scanme.nmap.org or 192.168.1.0/24.")
            return
        }
        RecentTargets.add(target)
        let job = ScanJob.start(command: command, profileName: commandName, privileged: privileged) { [weak self] job in
            self?.jobFinished(job)
        }
        jobs.append(job)
        selectedJobID = job.id
        tab = .output
    }

    private func jobFinished(_ job: ScanJob) {
        if let result = job.result {
            _ = try? ScanArchive.store(result)
            if selectedHostKeys.isEmpty, let first = inventory.hosts.first {
                selectedHostKeys = [first.mergeKey]
            }
        }
        if case .failed(let message) = job.status {
            let needsRoot = job.output.contains("requires root privileges")
                || job.output.contains("You requested a scan type which requires root")
            alert = AlertInfo(
                title: needsRoot ? "This scan needs administrator privileges" : "Scan failed",
                message: needsRoot
                    ? "Options such as OS detection (-O) and SYN scan (-sS) need raw packet access. Turn on \"Run as administrator\" and scan again."
                    : message,
                offerPrivileged: needsRoot)
        }
    }

    func cancel(_ job: ScanJob? = nil) {
        if let job {
            job.cancel()
        } else {
            jobs.filter(\.isRunning).forEach { $0.cancel() }
        }
    }

    func remove(_ job: ScanJob) {
        job.cancel()
        jobs.removeAll { $0.id == job.id }
        if selectedJobID == job.id { selectedJobID = jobs.last?.id }
        let keys = Set(inventory.hosts.map(\.mergeKey))
        selectedHostKeys.formIntersection(keys)
    }

    // MARK: - Files

    func open(url: URL) {
        do {
            var result = try NmapXML.parse(contentsOf: url)
            if result.normalOutput.isEmpty {
                result.normalOutput = "Output for this scan was not saved. The results were loaded from \(url.lastPathComponent).\n"
            }
            let job = ScanJob(loaded: result, from: url)
            jobs.append(job)
            selectedJobID = job.id
            if jobs.count == 1 {
                if !result.target.isEmpty { target = result.target }
                command = result.args
            }
            if selectedHostKeys.isEmpty, let first = inventory.hosts.first {
                selectedHostKeys = [first.mergeKey]
            }
        } catch {
            alert = AlertInfo(title: "Can't open \(url.lastPathComponent)", message: error.localizedDescription)
        }
    }

    func runOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = true
        panel.message = "Choose Nmap XML output to open"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open(url:))
    }

    func runSavePanel(for job: ScanJob? = nil) {
        guard let job = job ?? selectedJob else { return }
        guard let result = job.result, !job.isRunning else {
            alert = AlertInfo(title: "Nothing to save", message: "The scan has no results yet. Wait for it to finish, then save.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml, UTType(filenameExtension: "nmap") ?? .plainText]
        panel.nameFieldStringValue = (job.fileURL?.deletingPathExtension().lastPathComponent ?? "scan") + ".xml"
        panel.message = "Save as .xml to keep all results, or .nmap for plain text output"
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if ["nmap", "txt"].contains(url.pathExtension.lowercased()) {
                try result.normalOutput.write(to: url, atomically: true, encoding: .utf8)
            } else {
                try NmapXML.data(for: result).write(to: url, options: .atomic)
                job.fileURL = url
                job.isSaved = true
            }
        } catch {
            alert = AlertInfo(title: "Can't save file", message: error.localizedDescription)
        }
    }

    func saveAllToDirectory() {
        let finished = jobs.filter { $0.result != nil && !$0.isRunning }
        guard !finished.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose a directory to save scans into"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        for (index, job) in finished.enumerated() {
            let url = dir.appendingPathComponent("scan-\(index + 1).xml")
            do {
                try NmapXML.data(for: job.result!).write(to: url, options: .atomic)
                job.fileURL = url
                job.isSaved = true
            } catch {
                alert = AlertInfo(title: "Can't save file", message: error.localizedDescription)
                return
            }
        }
    }

    // MARK: - Editing

    /// NmapHost comments are stored on the newest scan containing the host.
    func setComment(_ comment: String, forHost key: String) {
        for job in jobs.reversed() {
            guard var result = job.result,
                  let index = result.hosts.firstIndex(where: { $0.mergeKey == key })
            else { continue }
            result.hosts[index].comment = comment
            job.result = result
            job.isSaved = false
            return
        }
    }
}

// MARK: - Focused values for menu commands

struct FocusedSessionKey: FocusedValueKey {
    typealias Value = ScanSession
}

extension FocusedValues {
    var session: ScanSession? {
        get { self[FocusedSessionKey.self] }
        set { self[FocusedSessionKey.self] = newValue }
    }
}

// MARK: - Pixmaps

@MainActor
enum Pixmaps {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = AppResources.pixmap(name), let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}
