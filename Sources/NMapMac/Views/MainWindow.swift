import SwiftUI
import NMapMacCore

struct MainWindow: View {
    @State private var session: ScanSession
    @AppStorage("runPrivileged") private var runPrivileged = false
    private let initialURL: URL?

    init(commands: SavedCommandStore, initialURL: URL?) {
        _session = State(initialValue: ScanSession(commands: commands))
        self.initialURL = initialURL
    }

    var body: some View {
        NavigationSplitView {
            HostsSidebar(session: session)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)
        } detail: {
            VStack(spacing: 0) {
                ScanBar(session: session)
                Divider()
                DetailTabs(session: session)
            }
        }
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let job = session.jobs.last(where: \.isRunning) {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                        .help(job.progress.map { "\(Int($0 * 100))% done" } ?? "Scanning…")
                }
                Toggle(isOn: $runPrivileged) {
                    Label("Run as Administrator", systemImage: runPrivileged ? "lock.open.fill" : "lock.fill")
                }
                .help("Run scans as root. Required for SYN scans, OS detection and other raw-packet features.")
            }
        }
        .focusedSceneValue(\.session, session)
        .sheet(isPresented: $session.isSavingCommand) {
            SaveCommandSheet(session: session)
        }
        .alert(item: $session.alert) { info in
            if info.offerPrivileged {
                return Alert(
                    title: Text(info.title), message: Text(info.message),
                    primaryButton: .default(Text("Run as Administrator")) {
                        runPrivileged = true
                        session.startScan(privileged: true)
                    },
                    secondaryButton: .cancel())
            }
            return Alert(title: Text(info.title), message: Text(info.message))
        }
        .onAppear {
            if let initialURL, session.isEmpty { session.open(url: initialURL) }
            PendingFiles.shared.take().forEach(session.open(url:))
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugSelectTab)) { note in
            if let name = note.object as? String, let tab = DetailTab.allCases.first(where: { $0.rawValue == name }) {
                session.tab = tab
            } else if note.object as? String == "Save Command" {
                session.isSavingCommand = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .debugScan)) { note in
            if let quick = session.commands.command(named: "Quick scan") { session.use(quick) }
            session.target = note.object as? String ?? ""
            session.startScan(privileged: false)
        }
        #endif
        .onChange(of: PendingFiles.shared.urls) {
            // Files opened from Finder go to whichever window sees them first.
            PendingFiles.shared.take().forEach(session.open(url:))
        }
    }

    private var windowTitle: String {
        guard let job = session.selectedJob else { return "nMapMac" }
        return job.result?.title ?? (job.target.isEmpty ? "nMapMac" : "\(job.profileName) on \(job.target)")
    }
}

/// Target / saved command / Scan / Command, as at the top of Zenmap's window.
struct ScanBar: View {
    @Bindable var session: ScanSession
    @AppStorage("runPrivileged") private var runPrivileged = false
    @State private var recentTargets = RecentTargets.all
    @State private var showBuilder = false

    /// Plain-language reading of the target, e.g. "254 addresses (192.168.1.1 – 192.168.1.254)".
    private var targetHint: String {
        let target = session.target.trimmingCharacters(in: .whitespaces)
        if target.isEmpty { return "Not sure what to type? Click Choose… to pick your network or a range of addresses." }
        return "Will scan " + TargetRange.summarize(target).description
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("Target:").gridColumnAlignment(.trailing)
                HStack(spacing: 12) {
                    ComboBox(text: $session.target, items: recentTargets,
                             placeholder: "Host name, IP address or network (e.g. scanme.nmap.org, 192.168.1.0/24)") {
                        scan()
                    }
                    .frame(minWidth: 200)

                    Button {
                        showBuilder = true
                    } label: {
                        Label("Choose…", systemImage: "network")
                    }
                    .help("Pick your own network or an address range — no subnet masks needed")
                    .popover(isPresented: $showBuilder, arrowEdge: .bottom) {
                        TargetBuilderView(target: $session.target)
                    }

                    SavedCommandsMenu(session: session)

                    Button("Scan", action: scan)
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { session.cancel() }
                        .disabled(session.runningCount == 0)
                }
            }
            if !targetHint.isEmpty {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    Text(targetHint)
                        .font(.caption)
                        .foregroundStyle(TargetRange.summarize(session.target).invalid.isEmpty ? Color.secondary : Color.orange)
                        .padding(.top, -4)
                }
            }
            GridRow {
                Text("Command:").gridColumnAlignment(.trailing)
                TextField("nmap command", text: $session.command)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: session.command) { session.commandEdited() }
                    .onSubmit(scan)
            }
            if let description = session.currentSavedCommand?.description, !description.isEmpty {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, -4)
                }
            }
        }
        .padding(12)
        #if DEBUG
        .onReceive(debugBuilder) { note in
            if note.object as? String == "Choose" { showBuilder = true }
        }
        #endif
    }

    #if DEBUG
    private let debugBuilder = NotificationCenter.default.publisher(for: .debugSelectTab)
    #endif

    private func scan() {
        session.startScan(privileged: runPrivileged)
        recentTargets = RecentTargets.all
    }
}

struct DetailTabs: View {
    @Bindable var session: ScanSession

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $session.tab) {
                ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 10)

            Group {
                switch session.tab {
                case .output: OutputTab(session: session)
                case .details: HostDetailsTab(session: session)
                case .topology: TopologyTab(session: session)
                case .scans: ScansTab(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

/// Shown in tabs that have nothing to display yet.
struct EmptyState: View {
    var title: String
    var systemImage: String
    var message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
