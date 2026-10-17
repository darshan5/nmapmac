import SwiftUI
import NMapMacCore

/// The scans aggregated in this window (ScanScanListPage.py).
struct ScansTab: View {
    @Bindable var session: ScanSession
    @State private var selection: ScanJob.ID?

    var body: some View {
        VStack(spacing: 8) {
            Table(session.jobs, selection: $selection) {
                TableColumn("Status") { (job: ScanJob) in
                    HStack(spacing: 6) {
                        statusIcon(job)
                        Text(job.status.label + (job.isSaved || job.result == nil ? "" : " (unsaved)"))
                    }
                }
                .width(min: 90, ideal: 130)
                TableColumn("Command") { (job: ScanJob) in
                    Text(job.command)
                        .font(.system(.body, design: .monospaced))
                        .help(job.command)
                }
                TableColumn("Hosts up") { (job: ScanJob) in
                    Text(job.result.map { "\($0.hostsUp) / \($0.hostsTotal)" } ?? "")
                        .monospacedDigit()
                }
                .width(70)
            }
            .contextMenu(forSelectionType: ScanJob.ID.self) { ids in
                if let job = job(ids.first) {
                    Button("Show Output") {
                        session.selectedJobID = job.id
                        session.tab = .output
                    }
                    Button("Save…") { session.runSavePanel(for: job) }
                        .disabled(job.result == nil || job.isRunning)
                    Button("Remove") { session.remove(job) }
                }
            } primaryAction: { ids in
                if let job = job(ids.first) {
                    session.selectedJobID = job.id
                    session.tab = .output
                }
            }

            HStack {
                Button("Append Scan…") { session.runOpenPanel() }
                    .help("Open saved scan results and add them to this window")
                Button("Remove Scan") {
                    if let job = job(selection) { session.remove(job) }
                }
                .disabled(selection == nil)
                Button("Cancel Scan") { job(selection)?.cancel() }
                    .disabled(job(selection)?.isRunning != true)
                Spacer()
                Text("\(session.inventory.hosts.count) hosts from \(session.results.count) scans")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func job(_ id: ScanJob.ID?) -> ScanJob? {
        session.jobs.first { $0.id == id }
    }

    @ViewBuilder
    private func statusIcon(_ job: ScanJob) -> some View {
        switch job.status {
        case .running: ProgressView().controlSize(.mini)
        case .finished, .loaded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .cancelled: Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
