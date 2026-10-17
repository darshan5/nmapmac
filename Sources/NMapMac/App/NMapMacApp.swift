import AppKit
import SwiftUI
import NMapMacCore

/// Files opened from Finder or passed at launch, waiting for a window to take them.
@MainActor
@Observable
final class PendingFiles {
    static let shared = PendingFiles()
    var urls: [URL] = []

    func take() -> [URL] {
        defer { urls = [] }
        return urls
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (swift run) rather than an .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        DebugSnapshot.scheduleIfRequested()
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSLog("nMapMac: open %@", urls.map(\.path).joined(separator: ", "))
        Task { @MainActor in
            PendingFiles.shared.urls += urls.filter(\.isFileURL)
            // SwiftUI skips its initial window when launched to open files.
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                Self.newWindow()
            }
        }
    }

    @MainActor static func newWindow() {
        guard let fileMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "File" })?.submenu,
              let index = fileMenu.items.firstIndex(where: { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command })
        else { return }
        fileMenu.performActionForItem(at: index)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct NMapMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var commands = SavedCommandStore()

    var body: some Scene {
        // A window optionally opened on a saved scan file.
        WindowGroup("nMapMac", id: "main", for: URL.self) { $url in
            MainWindow(commands: commands, initialURL: url)
        }
        .defaultSize(width: 1100, height: 720)
        .commands { NMapMacCommands() }

        Window("Compare Results", id: "compare") {
            CompareView()
        }
        .defaultSize(width: 760, height: 560)

        Window("Search Scan Results", id: "search") {
            SearchView()
        }
        .defaultSize(width: 760, height: 520)

        Settings {
            SettingsView()
        }
    }
}

struct NMapMacCommands: Commands {
    @FocusedValue(\.session) private var session
    @Environment(\.openWindow) private var openWindow
    @AppStorage("runPrivileged") private var runPrivileged = false

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About nMapMac") { showAboutPanel() }
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Open Scan…") { openScan(inNewWindow: !(session?.isEmpty ?? true)) }
                .keyboardShortcut("o")
            Button("Open Scan in This Window…") { session?.runOpenPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(session == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Scan…") { session?.runSavePanel() }
                .keyboardShortcut("s")
                .disabled(session?.selectedJob?.result == nil)
            Button("Save All Scans to Directory…") { session?.saveAllToDirectory() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(session?.results.isEmpty ?? true)
        }
        CommandMenu("Scan") {
            Button("Scan") { session?.startScan(privileged: runPrivileged) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(session == nil)
            Button("Cancel Running Scans") { session?.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled((session?.runningCount ?? 0) == 0)
            Button("Save Current Command…") { session?.isSavingCommand = true }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(session == nil)
            Divider()
            Toggle("Run as Administrator", isOn: $runPrivileged)
        }
        CommandMenu("Tools") {
            Button("Compare Results") { openWindow(id: "compare") }
                .keyboardShortcut("d")
            Button("Search Scan Results") { openWindow(id: "search") }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Filter Hosts") {
                session?.sidebarMode = .hosts
                NSApp.keyWindow?.makeFirstResponder(nil)
                NotificationCenter.default.post(name: .focusHostFilter, object: nil)
            }
            .keyboardShortcut("l")
        }
        CommandGroup(replacing: .help) {
            Button("Nmap Documentation") { open("https://nmap.org/docs.html") }
            Button("Nmap Reference Guide") { open("https://nmap.org/book/man.html") }
        }
    }

    private func openScan(inNewWindow: Bool) {
        guard inNewWindow else {
            session?.runOpenPanel()
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { openWindow(id: "main", value: $0) }
    }

    private func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    private func showAboutPanel() {
        let credits = NSAttributedString(
            string: "A native macOS front end for the Nmap network scanner, modelled on Zenmap.\n\nNmap and Zenmap are created by Gordon “Fyodor” Lyon and the Nmap Project contributors. https://nmap.org",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "nMapMac",
            .credits: credits,
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}

extension Notification.Name {
    static let focusHostFilter = Notification.Name("NMapMacFocusHostFilter")
}
