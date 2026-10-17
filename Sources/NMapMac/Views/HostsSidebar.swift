import SwiftUI
import NMapMacCore

/// The Hosts / Services list on the left of Zenmap's window, with the host filter.
struct HostsSidebar: View {
    @Bindable var session: ScanSession
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $session.sidebarMode) {
                ForEach(SidebarMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            switch session.sidebarMode {
            case .hosts: hostList
            case .services: serviceList
            }

            Divider()
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter hosts", text: $session.filterText)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .help("Filter syntax: words match anywhere; os:linux, open:22,80, service:http, target:10.0, product:apache, inroute:IP")
                if !session.filterText.isEmpty {
                    Button {
                        session.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusHostFilter)) { _ in
            filterFocused = true
        }
    }

    private var hostList: some View {
        let hosts = session.visibleHosts
        return List(selection: Binding(
            get: { session.selectedHostKeys },
            set: { keys in
                // Only user clicks call this setter, so programmatic selection
                // (e.g. after a scan finishes) doesn't switch tabs.
                session.selectedHostKeys = keys
                if !keys.isEmpty { session.tab = .details }
            })
        ) {
            ForEach(hosts, id: \.mergeKey) { host in
                HStack(spacing: 8) {
                    if let icon = Pixmaps.image("\(host.osIconName)_32") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(host.hostname ?? host.primaryAddress)
                            .lineLimit(1)
                        if host.hostname != nil {
                            Text(host.primaryAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if host.openPortCount > 0 {
                        Text("\(host.openPortCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .help("\(host.openPortCount) open ports")
                    }
                }
                .tag(host.mergeKey)
            }
        }
        .overlay {
            if hosts.isEmpty {
                Text(session.filterText.isEmpty ? "No hosts" : "No matching hosts")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var serviceList: some View {
        let services = session.inventory.services
        let names = services.keys.sorted()
        return List(selection: Binding(
            get: { session.selectedService },
            set: { name in
                session.selectedService = name
                if name != nil { session.tab = .details }
            })
        ) {
            ForEach(names, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Text("\(services[name]?.count ?? 0)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .tag(Optional(name))
            }
        }
        .overlay {
            if names.isEmpty {
                Text("No services").foregroundStyle(.secondary)
            }
        }
    }
}
