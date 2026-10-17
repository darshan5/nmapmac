import SwiftUI
import NMapMacCore

/// Radial network map built from traceroute data (zenmap/radialnet).
struct TopologyTab: View {
    @Bindable var session: ScanSession
    @State private var zoom: Double = 1
    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var showRings = true
    @State private var showLabels = true
    @State private var showLatency = false

    var body: some View {
        let topology = Topology(hosts: session.visibleHosts)
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                Toggle("Rings", isOn: $showRings)
                Toggle("Labels", isOn: $showLabels)
                Toggle("Latency", isOn: $showLatency)
                Spacer()
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $zoom, in: 0.3...3).frame(width: 140)
                Image(systemName: "plus.magnifyingglass")
                Button("Fit") {
                    zoom = 1
                    pan = .zero
                }
            }
            .toggleStyle(.checkbox)
            .padding(.top, 8)

            if topology.nodes.count <= 1 {
                EmptyState(title: "No topology", systemImage: "point.3.connected.trianglepath.dotted",
                           message: "Hosts appear here after a scan. Add --traceroute (or use an Intense scan) to see the routes between them.")
            } else {
                GeometryReader { geo in
                    let layout = Layout(topology: topology, size: geo.size, zoom: zoom, pan: pan)
                    Canvas { context, _ in draw(layout, in: &context) }
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                        .gesture(
                            DragGesture(minimumDistance: 3)
                                .onChanged { value in
                                    let start = dragStart ?? pan
                                    dragStart = start
                                    pan = CGSize(width: start.width + value.translation.width,
                                                 height: start.height + value.translation.height)
                                }
                                .onEnded { _ in dragStart = nil })
                        .simultaneousGesture(
                            MagnifyGesture().onChanged { value in
                                zoom = min(max(value.magnification, 0.3), 3)
                            })
                        .onTapGesture(count: 1, coordinateSpace: .local) { point in
                            if let node = layout.node(at: point), let host = node.host {
                                session.sidebarMode = .hosts
                                session.selectedHostKeys = [host.mergeKey]
                            }
                        }
                        .onTapGesture(count: 2, coordinateSpace: .local) { point in
                            if let node = layout.node(at: point), let host = node.host {
                                session.selectedHostKeys = [host.mergeKey]
                                session.tab = .details
                            }
                        }
                }
            }
            HStack(spacing: 14) {
                legend(color: .green, "0–2 open ports")
                legend(color: .yellow, "3–6 open ports")
                legend(color: .red, "7+ open ports")
                HStack(spacing: 4) {
                    Rectangle().fill(.gray).frame(width: 9, height: 9)
                    Text("Router / hop")
                }
                Spacer()
                Text("Click a host to select it; double-click for its details. Drag to pan.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func legend(color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text)
        }
    }

    struct Layout {
        var topology: Topology
        var center: CGPoint
        var ringSpacing: Double

        init(topology: Topology, size: CGSize, zoom: Double, pan: CGSize) {
            self.topology = topology
            center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
            let radius = min(size.width, size.height) / 2 - 50
            ringSpacing = max(radius, 60) / Double(max(topology.maxRing, 1)) * zoom
        }

        func point(for node: Topology.Node) -> CGPoint {
            let r = Double(node.ring) * ringSpacing
            return CGPoint(x: center.x + r * cos(node.angle), y: center.y + r * sin(node.angle))
        }

        func node(at location: CGPoint) -> Topology.Node? {
            topology.nodes.values
                .map { ($0, hypot(point(for: $0).x - location.x, point(for: $0).y - location.y)) }
                .filter { $0.1 < 14 }
                .min { $0.1 < $1.1 }?.0
        }
    }

    private func draw(_ layout: Layout, in context: inout GraphicsContext) {
        let topology = layout.topology
        if showRings {
            for ring in 1...max(topology.maxRing, 1) {
                let r = Double(ring) * layout.ringSpacing
                let rect = CGRect(x: layout.center.x - r, y: layout.center.y - r, width: 2 * r, height: 2 * r)
                context.stroke(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.25)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }

        for edge in topology.edges {
            let a = layout.point(for: edge.from)
            let b = layout.point(for: edge.to)
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1.2)
            if showLatency, !edge.to.rtt.isEmpty, edge.to.rtt != "--" {
                context.draw(Text("\(edge.to.rtt) ms").font(.system(size: 9)).foregroundColor(.secondary),
                             at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 7))
            }
        }

        for node in topology.nodes.values {
            let p = layout.point(for: node)
            let selected = node.host.map { session.selectedHostKeys.contains($0.mergeKey) } ?? false
            let size: Double = node.isLocalhost ? 16 : (node.host == nil ? 9 : 13)
            let rect = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            let shape = node.host == nil && !node.isLocalhost
                ? Path(rect)
                : Path(ellipseIn: rect)
            context.fill(shape, with: .color(fill(for: node)))
            context.stroke(shape, with: .color(selected ? .accentColor : .primary.opacity(0.6)),
                           lineWidth: selected ? 3 : 1)

            if showLabels {
                let label = Text(node.label)
                    .font(.system(size: 10, weight: selected ? .bold : .regular))
                    .foregroundColor(.primary)
                // Put labels outside the ring, on the node's side of the centre.
                let dx = cos(node.angle), dy = sin(node.angle)
                let anchor: UnitPoint = node.isLocalhost ? .top : (dx >= 0 ? .leading : .trailing)
                let offset = node.isLocalhost ? CGPoint(x: p.x, y: p.y + 12)
                    : CGPoint(x: p.x + dx * 12, y: p.y + dy * 12)
                context.draw(label, at: offset, anchor: anchor)
            }
        }
    }

    private func fill(for node: Topology.Node) -> Color {
        if node.isLocalhost { return .primary }
        guard let host = node.host else { return .gray }
        switch host.openPortCount {
        case 0...2: return .green
        case 3...6: return .yellow
        default: return .red
        }
    }
}
