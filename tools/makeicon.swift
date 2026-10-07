import AppKit

// Renders Assets/AppIcon.icns: an OLED-black squircle with a glowing activity trace.
//   swiftc tools/makeicon.swift -o build/makeicon && build/makeicon Assets
func draw(_ ctx: CGContext, _ px: CGFloat) {
    ctx.scaleBy(x: px / 1024, y: px / 1024)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: col(0, 0, 0, 0.5))
    ctx.addPath(squircle); ctx.setFillColor(col(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [col(0.07, 0.07, 0.09), col(0, 0, 0)] as CFArray, locations: [0, 0.55])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // faint grid
    ctx.setStrokeColor(col(1, 1, 1, 0.06)); ctx.setLineWidth(3)
    for i in 1...4 { let y = 100 + CGFloat(i) * 164.8; ctx.move(to: CGPoint(x: 100, y: y)); ctx.addLine(to: CGPoint(x: 924, y: y)) }
    for i in 1...4 { let x = 100 + CGFloat(i) * 164.8; ctx.move(to: CGPoint(x: x, y: 100)); ctx.addLine(to: CGPoint(x: x, y: 924)) }
    ctx.strokePath()

    // activity trace
    let pts: [(CGFloat, CGFloat)] = [(40, 410), (260, 420), (340, 380), (420, 560), (500, 340), (590, 700), (680, 470), (760, 540), (990, 505)]
    let line = CGMutablePath()
    line.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
    for i in 1..<pts.count {
        let a = pts[i - 1], b = pts[i], mx = (a.0 + b.0) / 2
        line.addCurve(to: CGPoint(x: b.0, y: b.1), control1: CGPoint(x: mx, y: a.1), control2: CGPoint(x: mx, y: b.1))
    }
    let gradient = CGGradient(colorsSpace: cs, colors: [col(0.04, 0.52, 1), col(0.75, 0.35, 0.95), col(1, 0.62, 0.04)] as CFArray, locations: [0, 0.55, 1])!

    // fill under the line
    ctx.saveGState()
    let area = CGMutablePath(); area.addPath(line)
    area.addLine(to: CGPoint(x: 990, y: 100)); area.addLine(to: CGPoint(x: 40, y: 100)); area.closeSubpath()
    ctx.addPath(area); ctx.clip()
    let fade = CGGradient(colorsSpace: cs, colors: [col(0.75, 0.35, 0.95, 0.28), col(0.75, 0.35, 0.95, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fade, start: CGPoint(x: 512, y: 700), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // glow, then the crisp gradient line
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46, color: col(0.65, 0.4, 1, 0.9))
    ctx.addPath(line); ctx.setLineWidth(26); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(col(0.65, 0.4, 1, 0.9)); ctx.strokePath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(line); ctx.setLineWidth(26); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 0), end: CGPoint(x: 924, y: 0), options: [])
    ctx.restoreGState()
    ctx.restoreGState()

    // edge highlight
    ctx.addPath(squircle); ctx.setStrokeColor(col(1, 1, 1, 0.12)); ctx.setLineWidth(4); ctx.strokePath()
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    draw(g.cgContext, CGFloat(px))
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let set = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(1024).write(to: out.appendingPathComponent("AppIcon-1024.png"))
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
