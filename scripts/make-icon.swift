// Renders Resources/AppIcon.png (1024×1024): a radar sweep over a network.
//   swift scripts/make-icon.swift
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-square background with a deep blue-green gradient.
let inset = 100.0
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.04, green: 0.16, blue: 0.24, alpha: 1),
                    NSColor(red: 0.02, green: 0.36, blue: 0.40, alpha: 1)])!
    .draw(in: bg, angle: -90)
bg.addClip()

let center = CGPoint(x: size / 2, y: size / 2)
let green = NSColor(red: 0.35, green: 0.95, blue: 0.65, alpha: 1)

// Radar rings.
for r in [110.0, 210.0, 310.0] {
    green.withAlphaComponent(0.35).setStroke()
    let ring = NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    ring.lineWidth = 10
    ring.stroke()
}

// Sweep wedge.
ctx.saveGState()
let wedge = NSBezierPath()
wedge.move(to: center)
wedge.appendArc(withCenter: center, radius: 330, startAngle: 20, endAngle: 75)
wedge.close()
wedge.addClip()
NSGradient(colors: [green.withAlphaComponent(0.0), green.withAlphaComponent(0.55)])!
    .draw(in: wedge, relativeCenterPosition: .zero)
ctx.restoreGState()

// Network nodes and links.
let nodes = [CGPoint(x: 0, y: 0), CGPoint(x: 150, y: 230), CGPoint(x: 260, y: 90),
             CGPoint(x: -200, y: 150), CGPoint(x: -120, y: -240), CGPoint(x: 210, y: -190)]
    .map { CGPoint(x: center.x + $0.x, y: center.y + $0.y) }
green.withAlphaComponent(0.8).setStroke()
for node in nodes.dropFirst() {
    let link = NSBezierPath()
    link.move(to: nodes[0])
    link.line(to: node)
    link.lineWidth = 12
    link.stroke()
}
for (i, node) in nodes.enumerated() {
    let r = i == 0 ? 52.0 : 34.0
    (i == 0 ? NSColor.white : green).setFill()
    NSBezierPath(ovalIn: CGRect(x: node.x - r, y: node.y - r, width: 2 * r, height: 2 * r)).fill()
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
