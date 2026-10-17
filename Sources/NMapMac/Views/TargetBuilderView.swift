import SwiftUI
import NMapMacCore

/// Helps pick what to scan without knowing subnet masks: the Mac's own
/// network in one click, or a plain "from … to …" address range.
struct TargetBuilderView: View {
    @Binding var target: String
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case network = "My Network"
        case range = "Address Range"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .network
    @State private var networks = LocalNetwork.current()
    @State private var from = ""
    @State private var to = ""
    @State private var append = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose What to Scan").font(.title3.bold())
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .network: networkPicker
            case .range: rangeForm
            }

            Divider()
            preview

            HStack {
                Toggle("Add to existing targets", isOn: $append)
                    .disabled(target.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use These Addresses") {
                    let existing = target.trimmingCharacters(in: .whitespaces)
                    target = append && !existing.isEmpty ? "\(existing) \(result)" : result
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(result.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            // Pre-fill the range with this Mac's network as a sensible starting point.
            if let net = networks.first {
                from = TargetRange.network(address: net.address, netmask: net.netmask).start.next.description
                to = net.range.end.previous.description
            }
        }
    }

    // MARK: - My network

    @State private var selectedNetwork: LocalNetwork.ID?

    private var networkPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan every device on a network this Mac is connected to.")
                .foregroundStyle(.secondary)
            if networks.isEmpty {
                Label("This Mac doesn't seem to be connected to a network.", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            } else {
                ForEach(networks) { net in
                    Button {
                        selectedNetwork = net.id
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: selectedNetwork == net.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selectedNetwork == net.id ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(net.friendlyName).bold()
                                Text("This Mac is \(net.address). Covers \(net.range.start) to \(net.range.end) — \(net.addressCount.formatted()) addresses.")
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Refresh") { networks = LocalNetwork.current() }
                .controlSize(.small)
        }
        .onAppear {
            if selectedNetwork == nil { selectedNetwork = networks.first?.id }
        }
    }

    // MARK: - Address range

    private var rangeForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type the first and last address. Everything in between is scanned.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("From:")
                    TextField("e.g. 192.168.1.1", text: $from)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                    validity(from)
                }
                GridRow {
                    Text("To:")
                    TextField("e.g. 192.168.1.254", text: $to)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                    validity(to)
                }
            }
            Text("Tip: home networks usually run from x.x.x.1 to x.x.x.254.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func validity(_ text: String) -> some View {
        if text.isEmpty {
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        } else if IPv4(text) != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                .help("An address is four numbers from 0 to 255 separated by dots, like 192.168.1.10")
        }
    }

    // MARK: - Result

    private var result: String {
        switch mode {
        case .network:
            return networks.first { $0.id == selectedNetwork }?.range.cidr ?? ""
        case .range:
            guard let a = IPv4(from), let b = IPv4(to) else { return "" }
            return TargetRange.spec(from: a, to: b)
        }
    }

    private var preview: some View {
        let summary = TargetRange.summarize(result)
        let count = summary.addressCount ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            if result.isEmpty {
                Text("Nothing selected yet.").foregroundStyle(.secondary)
            } else {
                Text(summary.description).bold()
                HStack(spacing: 4) {
                    Text("Nmap target:").foregroundStyle(.secondary)
                    Text(result).font(.body.monospaced()).textSelection(.enabled)
                }
                if count > 4096 {
                    Label("That's a lot of addresses — a scan may take a long time. A Ping scan is a quick way to find which ones are in use.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private extension IPv4 {
    var next: IPv4 { IPv4(value == .max ? value : value + 1) }
    var previous: IPv4 { IPv4(value == 0 ? value : value - 1) }
}
