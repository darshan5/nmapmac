import Foundation
import Observation

/// Locates the nmap executable. A path set in Settings wins; otherwise the
/// usual install locations and $PATH are searched.
public enum NmapLocator {
    public static let defaultsKey = "nmapPath"

    public static func find() -> String? {
        if let custom = UserDefaults.standard.string(forKey: defaultsKey), !custom.isEmpty,
           FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        var dirs = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/local/bin", "/usr/bin"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs += path.split(separator: ":").map(String.init)
        }
        for dir in dirs {
            let candidate = (dir as NSString).appendingPathComponent("nmap")
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

/// One scan run from this window: the nmap process, its live output and,
/// once finished, the parsed result. Mirrors zenmapCore/NmapCommand.py.
@MainActor
@Observable
public final class ScanJob: Identifiable {
    public enum Status: Equatable {
        case running
        case finished
        case cancelled
        case failed(String)
        /// Loaded from a file rather than run.
        case loaded

        public var label: String {
            switch self {
            case .running: return "Running"
            case .finished: return "Finished"
            case .cancelled: return "Cancelled"
            case .failed: return "Failed"
            case .loaded: return "Loaded"
            }
        }
    }

    public let id = UUID()
    public let command: String
    public let profileName: String
    public let target: String
    public private(set) var status: Status
    public private(set) var output = ""
    /// 0…1 when Nmap reports "About N% done", nil otherwise.
    public private(set) var progress: Double?
    public var result: ScanResult?
    /// Saved to disk since the last change.
    public var isSaved = false
    public var fileURL: URL?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var workDir: URL?
    @ObservationIgnored private var outputFile: FileHandle?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var lineBuffer = ""
    @ObservationIgnored private var onComplete: ((ScanJob) -> Void)?

    /// A job for a scan loaded from a file.
    public init(loaded result: ScanResult, from url: URL?) {
        command = result.args
        profileName = result.profileName
        target = result.target
        status = .loaded
        output = result.normalOutput
        self.result = result
        fileURL = url
        isSaved = url != nil
    }

    private init(command: String, profileName: String, target: String) {
        self.command = command
        self.profileName = profileName
        self.target = target
        status = .running
    }

    public var isRunning: Bool { status == .running }

    /// Starts nmap. With `privileged`, macOS asks for an administrator password
    /// and nmap runs as root (needed for SYN scans, OS detection, etc.).
    public static func start(command: String, profileName: String, privileged: Bool,
                             onComplete: @escaping (ScanJob) -> Void) -> ScanJob {
        var options = NmapOptions(commandLine: command)
        let job = ScanJob(command: command, profileName: profileName,
                          target: options.targets.joined(separator: " "))
        job.onComplete = onComplete

        guard let nmap = NmapLocator.find() else {
            job.fail("Nmap could not be found. Install it (e.g. `brew install nmap`) or set its path in Settings.")
            return job
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmapmac-\(job.id.uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            job.fail(error.localizedDescription)
            return job
        }
        job.workDir = workDir

        // Zenmap reads results from its own XML file, so replace any -oX.
        options.remove("-oX")
        let xmlPath = workDir.appendingPathComponent("scan.xml").path
        let args = options.arguments + ["-oX", xmlPath]

        if privileged {
            job.runPrivileged(nmap: nmap, args: args, workDir: workDir)
        } else {
            job.runUnprivileged(nmap: nmap, args: args)
        }
        return job
    }

    private func runUnprivileged(nmap: String, args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nmap)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.append(text) }
        }
        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            let reason = proc.terminationReason
            Task { @MainActor in
                // Drain anything still buffered in the pipe.
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                if !rest.isEmpty { self?.append(String(decoding: rest, as: UTF8.self)) }
                self?.finish(exitCode: status, signalled: reason == .uncaughtSignal)
            }
        }
        self.process = process
        do {
            try process.run()
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Runs nmap as root through `osascript ... with administrator privileges`.
    /// A small wrapper script writes output to a file we poll, and watches for a
    /// cancel marker file so cancelling doesn't need a second password prompt.
    private func runPrivileged(nmap: String, args: [String], workDir: URL) {
        let outPath = workDir.appendingPathComponent("output.txt").path
        let cancelPath = workDir.appendingPathComponent("cancel").path
        let statusPath = workDir.appendingPathComponent("status").path
        FileManager.default.createFile(atPath: outPath, contents: nil)

        let quoted = ([nmap] + args).map(Self.shellQuote).joined(separator: " ")
        let script = """
        #!/bin/sh
        \(quoted) >> \(Self.shellQuote(outPath)) 2>&1 &
        pid=$!
        sent=0
        while kill -0 $pid 2>/dev/null; do
          if [ -f \(Self.shellQuote(cancelPath)) ] && [ $sent -eq 0 ]; then kill -INT $pid; sent=1; fi
          sleep 0.3
        done
        wait $pid
        echo $? > \(Self.shellQuote(statusPath))
        chmod -R a+rwX \(Self.shellQuote(workDir.path))
        """
        let scriptURL = workDir.appendingPathComponent("run.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            fail(error.localizedDescription)
            return
        }

        let shellCommand = "/bin/sh " + Self.shellQuote(scriptURL.path)
        let appleScript = "do shell script \"\(shellCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        outputFile = FileHandle(forReadingAtPath: outPath)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOutputFile() }
        }

        process.terminationHandler = { [weak self] proc in
            let osascriptStatus = proc.terminationStatus
            let errText = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            Task { @MainActor in
                guard let self else { return }
                self.pollOutputFile()
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                if osascriptStatus != 0 {
                    if errText.contains("-128") {
                        self.fail("Authentication was cancelled.")
                    } else {
                        self.fail(errText.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    return
                }
                let code = (try? String(contentsOfFile: statusPath, encoding: .utf8))
                    .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
                self.finish(exitCode: code, signalled: false)
            }
        }
        self.process = process
        do {
            try process.run()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func pollOutputFile() {
        guard let handle = outputFile else { return }
        let data = handle.readDataToEndOfFile()
        if !data.isEmpty { append(String(decoding: data, as: UTF8.self)) }
    }

    public func cancel() {
        guard isRunning else { return }
        status = .cancelled
        if let workDir, process?.executableURL?.path == "/usr/bin/osascript" {
            FileManager.default.createFile(atPath: workDir.appendingPathComponent("cancel").path, contents: nil)
        } else {
            process?.interrupt()
        }
    }

    private func append(_ text: String) {
        output += text
        lineBuffer += text
        // Nmap prints "About 12.34% done" in its timing lines.
        while let newline = lineBuffer.firstIndex(of: "\n") {
            let line = lineBuffer[..<newline]
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newline)...])
            if let range = line.range(of: #"About (\d+(\.\d+)?)% done"#, options: .regularExpression) {
                let number = line[range].dropFirst(6).prefix { $0.isNumber || $0 == "." }
                if let pct = Double(number) { progress = pct / 100 }
            }
        }
    }

    private func finish(exitCode: Int32, signalled: Bool) {
        defer { cleanUp() }
        let xmlURL = workDir?.appendingPathComponent("scan.xml")
        var parsed: ScanResult?
        if let xmlURL, let data = try? Data(contentsOf: xmlURL), !data.isEmpty {
            parsed = try? NmapXML.parse(data: data)
        }
        if var parsed {
            parsed.normalOutput = output
            parsed.profileName = profileName
            if parsed.target.isEmpty { parsed.target = target }
            result = parsed
        }
        if status == .cancelled {
            // Keep whatever partial results nmap managed to write.
        } else if exitCode != 0 || signalled || parsed == nil {
            let lastLines = output.split(separator: "\n").suffix(3).joined(separator: "\n")
            status = .failed(lastLines.isEmpty ? "nmap exited with status \(exitCode)" : lastLines)
        } else {
            status = .finished
            progress = 1
        }
        onComplete?(self)
        onComplete = nil
    }

    private func fail(_ message: String) {
        if !message.isEmpty { output += "\n" + message + "\n" }
        status = .failed(message)
        cleanUp()
        onComplete?(self)
        onComplete = nil
    }

    private func cleanUp() {
        pollTimer?.invalidate()
        pollTimer = nil
        try? outputFile?.close()
        outputFile = nil
        process = nil
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
        workDir = nil
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
