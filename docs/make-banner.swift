// Renders docs/banner.png (1280x640: GitHub social preview + README header) from the app icon.
// Build: swiftc docs/make-banner.swift -o /tmp/mb && /tmp/mb Assets/AppIcon-1024.png docs/banner.png
import AppKit

let W = 1280, H = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
let blue = c(0.04, 0.52, 1.00), purple = c(0.75, 0.35, 0.95), green = c(0.19, 0.82, 0.35), sky = c(0.20, 0.68, 0.90)

NSGradient(starting: c(0.10, 0.11, 0.15), ending: c(0.04, 0.04, 0.07))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)
NSGradient(colors: [blue.withAlphaComponent(0.24), blue.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: 250, y: 430), radius: 0, toCenter: NSPoint(x: 250, y: 430), radius: 430, options: [])

// app icon
let tile = NSRect(x: 90, y: 250, width: 240, height: 240)
if let icon = NSImage(contentsOfFile: CommandLine.arguments[1]) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = .black.withAlphaComponent(0.5); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -10); sh.set()
    icon.draw(in: tile)
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: NSPoint(x: x, y: y))
}
text("Task Manager", 90, 150, size: 84, weight: .bold, color: .white)
text("A fast, native task manager for macOS", 94, 98, size: 30, weight: .regular, color: c(1, 1, 1, 0.72))
text("CPU · Memory · GPU · Disk · Network · Processes", 94, 56, size: 22, weight: .medium, color: sky)

// mock performance card
let card = NSRect(x: 700, y: 120, width: 480, height: 400)
let cp = NSBezierPath(roundedRect: card, xRadius: 28, yRadius: 28)
c(1, 1, 1, 0.06).setFill(); cp.fill()
c(1, 1, 1, 0.12).setStroke(); cp.lineWidth = 1.5; cp.stroke()

func row(_ label: String, _ value: String, _ color: NSColor, _ pts: [Double], y: CGFloat) {
    text(label, card.minX + 36, y + 52, size: 26, weight: .semibold, color: .white)
    let w = NSAttributedString(string: value, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold)]).size().width
    NSAttributedString(string: value, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold), .foregroundColor: color])
        .draw(at: NSPoint(x: card.maxX - 36 - w, y: y + 52))
    let box = NSRect(x: card.minX + 36, y: y, width: card.width - 72, height: 40)
    color.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
    let line = NSBezierPath(), area = NSBezierPath()
    for (i, p) in pts.enumerated() {
        let pt = NSPoint(x: box.minX + box.width * CGFloat(i) / CGFloat(pts.count - 1), y: box.minY + 4 + (box.height - 8) * CGFloat(p))
        if i == 0 { line.move(to: pt); area.move(to: NSPoint(x: pt.x, y: box.minY)); area.line(to: pt) } else { line.line(to: pt); area.line(to: pt) }
    }
    area.line(to: NSPoint(x: box.maxX, y: box.minY)); area.close()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).addClip()
    color.withAlphaComponent(0.25).setFill(); area.fill()
    color.setStroke(); line.lineWidth = 2.5; line.lineJoinStyle = .round; line.stroke()
    NSGraphicsContext.restoreGraphicsState()
}
row("CPU", "34%", blue, [0.1, 0.12, 0.2, 0.15, 0.3, 0.25, 0.5, 0.35, 0.28, 0.4, 0.33, 0.34], y: card.minY + 300)
row("Memory", "76%", purple, [0.7, 0.72, 0.72, 0.74, 0.73, 0.75, 0.75, 0.76, 0.76, 0.77, 0.76, 0.76], y: card.minY + 205)
row("Disk", "2.4 MB/s", green, [0.05, 0.05, 0.4, 0.1, 0.05, 0.7, 0.2, 0.05, 0.1, 0.5, 0.15, 0.1], y: card.minY + 110)
row("Network", "18 KB/s", sky, [0.1, 0.15, 0.1, 0.3, 0.2, 0.15, 0.35, 0.2, 0.1, 0.25, 0.3, 0.2], y: card.minY + 15)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
