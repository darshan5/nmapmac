import SwiftUI
import NMapMacCore

/// Compare Results: pick two scans and show what changed (DiffCompare.py).
struct CompareView: View {
    @State private var entries: [ScanArchive.Entry] = []
    @State private var leftURL: URL?
    @State private var rightURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                chooser("A Scan", selection: $leftURL)
                chooser("B Scan", selection: $rightURL)
            }
            GroupBox {
                diffText
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } label: {
                HStack(spacing: 12) {
                    Text("Differences").font(.headline)
                    Text("− only in A").foregroundStyle(.red)
                    Text("+ only in B").foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 420)
        .onAppear(perform: reload)
    }

    private func chooser(_ title: String, selection: Binding<URL?>) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading) {
                HStack {
                    Picker(title, selection: selection) {
                        Text("Choose a scan").tag(URL?.none)
                        ForEach(entries) { entry in
                            Text(label(entry)).tag(Optional(entry.url))
                        }
                    }
                    .labelsHidden()
                    Button("Open…") { openFile(into: selection) }
                }
                if let scan = scan(selection.wrappedValue) {
                    Text(scan.args)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var diffText: some View {
        if let a = scan(leftURL), let b = scan(rightURL) {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ScanDiff.compare(a, b).enumerated()), id: \.offset) { _, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .foregroundStyle(color(line.kind))
                            .bold(line.kind == .header)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(entries.isEmpty
                 ? "Finished scans are kept automatically. Run some scans, or use Open… to pick saved XML files."
                 : "Choose two scans to compare.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func color(_ kind: ScanDiff.LineKind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .header, .context: return .primary
        }
    }

    private func scan(_ url: URL?) -> ScanResult? {
        entries.first { $0.url == url }?.scan
    }

    private func label(_ entry: ScanArchive.Entry) -> String {
        let date = entry.scan.startTime?.formatted(date: .abbreviated, time: .shortened) ?? ""
        return "\(entry.scan.title) — \(date)"
    }

    private func reload() {
        entries = ScanArchive.load()
    }

    private func openFile(into selection: Binding<URL?>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let scan = try NmapXML.parse(contentsOf: url)
            if !entries.contains(where: { $0.url == url }) {
                entries.insert(ScanArchive.Entry(url: url, scan: scan), at: 0)
            }
            selection.wrappedValue = url
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
