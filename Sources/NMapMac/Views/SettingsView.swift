import SwiftUI
import NMapMacCore

struct SettingsView: View {
    @AppStorage(NmapLocator.defaultsKey) private var nmapPath = ""
    @AppStorage("runPrivileged") private var runPrivileged = false
    @AppStorage("highlightOutput") private var highlightOutput = true
    @State private var detected = NmapLocator.find()

    var body: some View {
        Form {
            Section("Nmap") {
                HStack {
                    TextField("Nmap executable", text: $nmapPath, prompt: Text(detected ?? "/usr/local/bin/nmap"))
                    Button("Choose…", action: choose)
                }
                LabeledContent("Using") {
                    Text(detected ?? "Nmap not found — install it with Homebrew (brew install nmap)")
                        .foregroundStyle(detected == nil ? .red : .secondary)
                        .textSelection(.enabled)
                }
                Toggle("Run scans as administrator", isOn: $runPrivileged)
                Text("Root privileges are needed for SYN scans (-sS), OS detection (-O), UDP scans and other raw-packet features. macOS asks for your password when a scan starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Output") {
                Toggle("Highlight Nmap output", isOn: $highlightOutput)
            }
            Section("Scan history") {
                LabeledContent("Location") {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: AppPaths.scansDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(AppPaths.scansDirectory)
                    }
                }
                Button("Clear Recent Targets") { RecentTargets.clear() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onChange(of: nmapPath) { detected = NmapLocator.find() }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        if panel.runModal() == .OK, let url = panel.url { nmapPath = url.path }
    }
}
