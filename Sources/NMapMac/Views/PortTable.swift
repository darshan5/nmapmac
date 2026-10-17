import SwiftUI
import NMapMacCore

/// One row of a port table.
struct PortRow: Identifiable, Hashable {
    var host: NmapHost
    var port: NmapPort

    var id: String { "\(host.mergeKey)|\(port.id)" }
    var hostName: String { host.displayName }
    var portID: Int { port.portID }
    var proto: String { port.proto }
    var state: String { port.state }
    var service: String { port.service.name }
    var version: String { port.service.versionString }
    var reason: String { port.reason }
}

/// Sortable table of ports (ScanOpenPortsPage.py). Shows a Host column when
/// rows come from more than one host.
struct PortTable: View {
    var rows: [PortRow]
    var showsHost: Bool
    @State private var sortOrder = [KeyPathComparator(\PortRow.portID)]

    /// Tall enough to show every row without an inner scroll bar, up to a limit.
    static func height(rows: Int) -> CGFloat {
        min(CGFloat(rows) * 24 + 32, 520)
    }

    var body: some View {
        let sorted = rows.sorted(using: sortOrder)
        Group {
            if showsHost {
                Table(sorted, sortOrder: $sortOrder) {
                    TableColumn("") { (row: PortRow) in StateDot(row: row) }.width(16)
                    TableColumn("Host", value: \.hostName).width(min: 120, ideal: 200)
                    TableColumn("Port", value: \.portID) { Text(String($0.portID)).monospacedDigit() }
                        .width(min: 50, ideal: 60)
                    TableColumn("Protocol", value: \.proto).width(min: 50, ideal: 60)
                    TableColumn("State", value: \.state).width(min: 60, ideal: 80)
                    TableColumn("Service", value: \.service).width(min: 80, ideal: 110)
                    TableColumn("Version", value: \.version) { Text($0.version).help($0.version) }
                }
            } else {
                Table(sorted, sortOrder: $sortOrder) {
                    TableColumn("") { (row: PortRow) in StateDot(row: row) }.width(16)
                    TableColumn("Port", value: \.portID) { Text(String($0.portID)).monospacedDigit() }
                        .width(min: 50, ideal: 60)
                    TableColumn("Protocol", value: \.proto).width(min: 50, ideal: 60)
                    TableColumn("State", value: \.state).width(min: 60, ideal: 80)
                    TableColumn("Service", value: \.service).width(min: 80, ideal: 110)
                    TableColumn("Reason", value: \.reason).width(min: 60, ideal: 90)
                    TableColumn("Version", value: \.version) { Text($0.version).help($0.version) }
                }
            }
        }
        .contextMenu(forSelectionType: PortRow.ID.self) { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                Button("Copy \(row.host.primaryAddress):\(row.portID)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(row.host.primaryAddress):\(row.portID)", forType: .string)
                }
            }
        }
        .frame(height: Self.height(rows: rows.count))
    }
}

private struct StateDot: View {
    var row: PortRow

    var body: some View {
        Circle()
            .fill(color(for: row.state))
            .frame(width: 9, height: 9)
            .help(row.reason.isEmpty ? row.state : "\(row.state) (\(row.reason))")
    }
}

/// Hosts offering the service selected in the sidebar's Services list.
struct ServiceHostsView: View {
    @Bindable var session: ScanSession

    var body: some View {
        if let name = session.selectedService {
            let entries = session.inventory.services[name] ?? []
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Service: \(name)").font(.title2.bold())
                    Text("\(Set(entries.map(\.host.mergeKey)).count) hosts, \(entries.count) ports")
                        .foregroundStyle(.secondary)
                    PortTable(rows: entries.map { PortRow(host: $0.host, port: $0.port) }, showsHost: true)
                    let scripted = entries.filter { !$0.port.scripts.isEmpty }
                    if !scripted.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(scripted) { entry in
                                    Text("\(entry.host.displayName) — \(entry.port.id)").font(.headline)
                                    ScriptOutputList(scripts: entry.port.scripts)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Text("Script Output").font(.headline)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyState(title: "No service selected", systemImage: "list.bullet.rectangle",
                       message: "Select a service on the left to see which hosts offer it.")
        }
    }
}

func color(for state: String) -> Color {
    switch state {
    case "open": return .green
    case "closed": return .red
    case let s where s.contains("filtered"): return .orange
    default: return .gray
    }
}

/// NSE script results, shown in full.
struct ScriptOutputList: View {
    var scripts: [ScriptResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(scripts, id: \.self) { script in
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.id).bold()
                    Text(script.output.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
