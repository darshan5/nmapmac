import SwiftUI
import NMapMacCore

/// Everything known about the selected hosts, including their ports
/// (ScanHostDetailsPage.py and ScanOpenPortsPage.py combined). With the
/// sidebar in Services mode, shows the hosts offering the selected service.
struct HostDetailsTab: View {
    @Bindable var session: ScanSession

    var body: some View {
        if session.sidebarMode == .services {
            ServiceHostsView(session: session)
        } else if session.selectedHosts.isEmpty {
            EmptyState(title: "No host selected", systemImage: "desktopcomputer",
                       message: session.inventory.hosts.isEmpty
                           ? "Run a scan to see hosts here."
                           : "Select a host on the left to see its details.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    ForEach(session.selectedHosts, id: \.mergeKey) { host in
                        HostDetailCard(host: host) { comment in
                            session.setComment(comment, forHost: host.mergeKey)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct HostDetailCard: View {
    var host: NmapHost
    var onComment: (String) -> Void
    @State private var comment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Section("Ports") {
                if host.ports.isEmpty {
                    Text("No interesting ports found.").foregroundStyle(.secondary)
                } else {
                    PortTable(rows: host.ports.map { PortRow(host: host, port: $0) }, showsHost: false)
                }
                ForEach(host.extraPorts, id: \.self) { extra in
                    Text("Not shown: \(extra.count) \(extra.state) ports")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            let scriptedPorts = host.ports.filter { !$0.scripts.isEmpty }
            if !scriptedPorts.isEmpty {
                Section("Port Script Output") {
                    ForEach(scriptedPorts) { port in
                        Text("\(port.id) \(port.service.name)").font(.headline)
                        ScriptOutputList(scripts: port.scripts)
                    }
                }
            }

            if !host.hostScripts.isEmpty {
                Section("Host Script Output") {
                    ScriptOutputList(scripts: host.hostScripts)
                }
            }

            Section("Host Status") {
                Fields([
                    ("State", host.state + (host.reason.isEmpty ? "" : " (\(host.reason))")),
                    ("Open ports", "\(host.openPortCount)"),
                    ("Filtered ports", "\(host.filteredPortCount)"),
                    ("Closed ports", "\(host.closedPortCount)"),
                    ("Scanned ports", "\(host.scannedPortCount)"),
                    ("Up time", host.uptimeSeconds.map(Self.formatUptime) ?? ""),
                    ("Last boot", host.lastBoot),
                    ("Network distance", host.distance.map { "\($0) hop\($0 == 1 ? "" : "s")" } ?? ""),
                    ("Scan started", host.startTime?.formatted(date: .abbreviated, time: .standard) ?? ""),
                    ("Scan finished", host.endTime?.formatted(date: .abbreviated, time: .standard) ?? ""),
                ])
            }

            Section("Addresses") {
                Fields([
                    ("IPv4", host.ipv4 ?? ""),
                    ("IPv6", host.ipv6 ?? ""),
                    ("MAC", host.mac?.addr ?? ""),
                    ("Vendor", host.mac?.vendor ?? ""),
                ])
            }

            if !host.hostnames.isEmpty {
                Section("Hostnames") {
                    Fields(host.hostnames.map { ($0.type.isEmpty ? "Name" : $0.type, $0.name) })
                }
            }

            if !host.osMatches.isEmpty {
                Section("Operating System") {
                    ForEach(Array(host.osMatches.enumerated()), id: \.offset) { index, match in
                        osMatch(match, best: index == 0)
                        if index < host.osMatches.count - 1 { Divider() }
                    }
                }
            }

            if !host.portsUsed.isEmpty {
                Section("Ports Used for OS Detection") {
                    Fields(host.portsUsed.map { ("\($0.portID)/\($0.proto)", $0.state) })
                }
            }

            if !host.tcpSequence.index.isEmpty || !host.tcpSequence.difficulty.isEmpty {
                Section("TCP Sequence") {
                    Fields([("Class", host.tcpSequence.index), ("Difficulty", host.tcpSequence.difficulty),
                            ("Values", host.tcpSequence.values)])
                }
            }
            if !host.ipIDSequence.classDescription.isEmpty {
                Section("IP ID Sequence") {
                    Fields([("Class", host.ipIDSequence.classDescription), ("Values", host.ipIDSequence.values)])
                }
            }
            if !host.tcpTSSequence.classDescription.isEmpty {
                Section("TCP Timestamp Sequence") {
                    Fields([("Class", host.tcpTSSequence.classDescription), ("Values", host.tcpTSSequence.values)])
                }
            }

            if let trace = host.trace, !trace.hops.isEmpty {
                Section("Traceroute") {
                    if !trace.port.isEmpty {
                        Text("Using port \(trace.port)/\(trace.proto)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                        GridRow { Text("Hop").bold(); Text("RTT").bold(); Text("Address").bold() }
                        ForEach(trace.hops, id: \.self) { hop in
                            GridRow {
                                Text("\(hop.ttl)").monospacedDigit()
                                Text(hop.rtt == "--" ? "--" : "\(hop.rtt) ms").monospacedDigit()
                                Text(hop.host.isEmpty ? hop.ipAddress : "\(hop.host) (\(hop.ipAddress))")
                            }
                        }
                    }
                    .textSelection(.enabled)
                }
            }

            Section("Comments") {
                TextEditor(text: $comment)
                    .font(.body)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                    .onChange(of: comment) {
                        if comment != host.comment { onComment(comment) }
                    }
            }
        }
        .onAppear { comment = host.comment }
        .onChange(of: host.mergeKey) { comment = host.comment }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let logo = Pixmaps.image("\(host.osIconName)_75") {
                Image(nsImage: logo).resizable().frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName).font(.title2.bold()).textSelection(.enabled)
                if let os = host.bestOSMatch {
                    Text(os.name).foregroundStyle(.secondary)
                }
                Text("\(host.openPortCount) open · \(host.filteredPortCount) filtered · \(host.closedPortCount) closed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let vl = Pixmaps.image("\(host.vulnerabilityIconName)_32") {
                Image(nsImage: vl).help("\(host.openPortCount) open ports")
            }
        }
    }

    private func osMatch(_ match: OSMatch, best: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(match.name).bold(best)
                if best { Text("Best match").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                ProgressView(value: Double(match.accuracy), total: 100).frame(width: 120)
                Text("\(match.accuracy)%").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            if !match.classes.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                    GridRow {
                        ForEach(["Type", "Vendor", "Family", "Generation", "Accuracy", "CPE"], id: \.self) {
                            Text($0).font(.caption.bold()).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(match.classes, id: \.self) { c in
                        GridRow {
                            Text(c.type); Text(c.vendor); Text(c.family)
                            Text(c.generation); Text("\(c.accuracy)%")
                            Text(c.cpe.joined(separator: ", ")).font(.caption.monospaced())
                        }
                        .font(.callout)
                    }
                }
                .textSelection(.enabled)
                .padding(.leading, 12)
            }
        }
    }

    static func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        return "\(days)d \(hours)h \(minutes)m (\(seconds.formatted()) seconds)"
    }

    private struct Section<Content: View>: View {
        var title: String
        @ViewBuilder var content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            } label: {
                Text(title).font(.headline)
            }
        }
    }

    private struct Fields: View {
        var rows: [(String, String)]

        init(_ rows: [(String, String)]) {
            self.rows = rows.filter { !$0.1.isEmpty }
        }

        var body: some View {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        Text(rows[i].0)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .trailing)
                        Text(rows[i].1).textSelection(.enabled)
                    }
                }
            }
        }
    }
}
