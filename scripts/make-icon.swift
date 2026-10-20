// Draws Segue's icon: an envelope whose flap is a musical tie arc that turns
// into an arrow. Writes an .iconset and builds Resources/AppIcon.icns.
//   swift scripts/make-icon.swift
import AppKit

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded square with a deep blue → teal gradient (macOS icon grid: ~80% of the canvas).
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    ctx.saveGState()
    bg.addClip()
    let gradient = NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.22, blue: 0.55, alpha: 1),
                                       NSColor(srgbRed: 0.05, green: 0.62, blue: 0.62, alpha: 1)])!
    gradient.draw(in: rect, angle: -60)
    ctx.restoreGState()

    // Envelope body.
    let ew = rect.width * 0.62, eh = ew * 0.66
    let ex = rect.midX - ew / 2, ey = rect.midY - eh / 2 - rect.height * 0.04
    let body = NSBezierPath(roundedRect: CGRect(x: ex, y: ey, width: ew, height: eh), xRadius: ew * 0.07, yRadius: ew * 0.07)
    NSColor.white.setFill()
    body.fill()

    // The V of the flap, drawn as a stroke.
    let v = NSBezierPath()
    v.move(to: CGPoint(x: ex, y: ey + eh - ew * 0.02))
    v.line(to: CGPoint(x: ex + ew / 2, y: ey + eh * 0.42))
    v.line(to: CGPoint(x: ex + ew, y: ey + eh - ew * 0.02))
    v.lineWidth = s * 0.028
    v.lineJoinStyle = .round
    v.lineCapStyle = .round
    NSColor(srgbRed: 0.10, green: 0.22, blue: 0.55, alpha: 1).setStroke()
    v.stroke()

    // The tie arc: from the flap's left corner, over the top, into an arrow on the right.
    let arc = NSBezierPath()
    let startP = CGPoint(x: ex + ew * 0.08, y: ey + eh + s * 0.01)
    let endP = CGPoint(x: ex + ew * 1.12, y: ey + eh * 0.78)
    arc.move(to: startP)
    arc.curve(to: endP,
              controlPoint1: CGPoint(x: ex + ew * 0.25, y: ey + eh + s * 0.20),
              controlPoint2: CGPoint(x: ex + ew * 1.05, y: ey + eh + s * 0.16))
    arc.lineWidth = s * 0.045
    arc.lineCapStyle = .round
    NSColor(srgbRed: 1.0, green: 0.80, blue: 0.25, alpha: 1).setStroke()
    arc.stroke()
    // Arrow head.
    let head = NSBezierPath()
    let tip = CGPoint(x: endP.x + s * 0.035, y: endP.y - s * 0.04)
    head.move(to: CGPoint(x: tip.x - s * 0.085, y: tip.y + s * 0.015))
    head.line(to: tip)
    head.line(to: CGPoint(x: tip.x - s * 0.02, y: tip.y + s * 0.095))
    head.lineWidth = s * 0.045
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = draw(size: 1024)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! png(master, size: px).write(to: iconset.appendingPathComponent(name + ".png"))
}
try! png(master, size: 512).write(to: URL(fileURLWithPath: "docs/images/icon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
