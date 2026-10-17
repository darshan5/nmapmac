import SwiftUI
import NMapMacCore

/// Search Scan Results: query past scans with Zenmap's search syntax (SearchWindow.py).
struct SearchView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var entries: [ScanArchive.Entry] = []
    @State private var query = ""
    @State private var selection: ScanArchive.Entry.ID?
    @State private var showHelp = false

    private var results: [ScanArchive.Entry] {
        let q = SearchQuery(query)
        return q.isEmpty ? entries : entries.filter { q.matches($0.scan) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search", text: $query, prompt: Text("e.g. apache os:linux open:80 after:7"))
                    .textFieldStyle(.roundedBorder)
                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showHelp) { helpText.padding().frame(width: 380) }
            }

            Table(results, selection: $selection) {
                TableColumn("Scan") { (entry: ScanArchive.Entry) in Text(entry.scan.title) }
                TableColumn("Date") { (entry: ScanArchive.Entry) in
                    Text(entry.scan.startTime?.formatted(date: .abbreviated, time: .shortened) ?? "")
                }
                .width(min: 120, ideal: 150)
                TableColumn("Hosts up") { (entry: ScanArchive.Entry) in
                    Text("\(entry.scan.hostsUp)").monospacedDigit()
                }
                .width(70)
            }
            .contextMenu(forSelectionType: ScanArchive.Entry.ID.self) { ids in
                if let url = ids.first {
                    Button("Open in New Window") { openWindow(id: "main", value: url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Divider()
                    Button("Delete", role: .destructive) { delete(url) }
                }
            } primaryAction: { ids in
                if let url = ids.first { openWindow(id: "main", value: url) }
            }

            HStack {
                Text("\(results.count) of \(entries.count) scans")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh", action: reload)
                Button("Open") {
                    if let selection { openWindow(id: "main", value: selection) }
                }
                .disabled(selection == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 360)
        .onAppear(perform: reload)
    }

    private var helpText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search syntax").font(.headline)
            Text("Plain words match host names, addresses, OS, services and scan type names.")
            Group {
                Text("os:linux  ·  target:192.168.1  ·  service:ssh  ·  product:apache")
                Text("open:22,80  ·  closed:23  ·  filtered:443  ·  scanned:21")
                Text("profile:intense (scan type)  ·  option:-sV  ·  inroute:10.0.0.1")
                Text("date:2026-10-01~2  ·  after:7  ·  before:2026-01-01")
            }
            .font(.callout.monospaced())
            Text("All terms must match. Every completed scan is kept in ~/Library/Application Support/nMapMac/scans.")
                .foregroundStyle(.secondary)
        }
    }

    private func reload() {
        entries = ScanArchive.load()
    }

    private func delete(_ url: URL) {
        if let entry = entries.first(where: { $0.url == url }) {
            ScanArchive.remove(entry)
            reload()
        }
    }
}
