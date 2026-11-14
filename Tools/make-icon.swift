// Renders AppIcon.icns: a light squircle with a keyboard and a blue lock badge.
import AppKit

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill(); squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(white: 0.99, alpha: 1), ending: NSColor(white: 0.86, alpha: 1))!
        .draw(in: squircle, angle: -90)

    func symbol(_ name: String, _ pt: CGFloat, _ color: NSColor) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: pt * s, weight: .medium)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    }
    let kb = symbol("keyboard", 400, NSColor(white: 0.22, alpha: 1))
    kb.draw(in: NSRect(x: 512 * s - kb.size.width / 2, y: 540 * s - kb.size.height / 2,
                       width: kb.size.width, height: kb.size.height))

    let badge = NSRect(x: 600 * s, y: 170 * s, width: 250 * s, height: 250 * s)
    NSGraphicsContext.saveGraphicsState()
    let bshadow = NSShadow()
    bshadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    bshadow.shadowOffset = NSSize(width: 0, height: -6 * s)
    bshadow.shadowBlurRadius = 14 * s
    bshadow.set()
    let circle = NSBezierPath(ovalIn: badge)
    NSColor.systemBlue.setFill(); circle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.62, blue: 1, alpha: 1),
               ending: NSColor(srgbRed: 0.0, green: 0.42, blue: 0.95, alpha: 1))!.draw(in: circle, angle: -90)
    let lock = symbol("lock.fill", 120, .white)
    lock.draw(in: NSRect(x: badge.midX - lock.size.width / 2, y: badge.midY - lock.size.height / 2,
                         width: lock.size.width, height: lock.size.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
