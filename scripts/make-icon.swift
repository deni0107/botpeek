// Draws BotPeek's app icon into an .iconset folder (then `iconutil -c icns`).
// Original artwork: a friendly character peeking around the edge of a screen.
//
//   swift scripts/make-icon.swift dist/AppIcon.iconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Squircle background (inset like Apple's icon grid).
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(calibratedRed: 0.36, green: 0.33, blue: 0.86, alpha: 1).setFill()
    tilePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.47, green: 0.44, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.25, green: 0.20, blue: 0.66, alpha: 1),
    ])!.draw(in: tilePath, angle: -90)

    NSGraphicsContext.current?.saveGraphicsState()
    tilePath.addClip()

    // A "screen edge": a lighter panel on the right.
    let edgeX = 640 * s
    NSColor.white.withAlphaComponent(0.14).setFill()
    NSRect(x: edgeX, y: 100 * s, width: 300 * s, height: 824 * s).fill()

    // The character, half hidden behind the edge.
    let body = NSBezierPath()
    let cx = 520 * s, cy = 430 * s, r = 215 * s
    body.appendOval(in: NSRect(x: cx - r, y: cy - r * 0.95, width: r * 2, height: r * 1.95))
    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: edgeX + 6 * s, height: size)).addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.71, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 1.00, green: 0.52, blue: 0.12, alpha: 1),
    ])!.draw(in: body, angle: -90)
    NSColor.white.setFill()
    for eyeX in [cx - 30 * s, cx + 62 * s] {
        NSBezierPath(roundedRect: NSRect(x: eyeX - 17 * s, y: cy + 10 * s, width: 34 * s, height: 70 * s), xRadius: 17 * s, yRadius: 17 * s).fill()
    }
    NSGraphicsContext.current?.restoreGraphicsState()

    // The edge line the character peeks around.
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: edgeX, y: 180 * s, width: 14 * s, height: 664 * s), xRadius: 7 * s, yRadius: 7 * s).fill()

    // Speech bubble.
    let bubble = NSBezierPath(roundedRect: NSRect(x: 220 * s, y: 650 * s, width: 330 * s, height: 170 * s), xRadius: 70 * s, yRadius: 70 * s)
    bubble.move(to: NSPoint(x: 400 * s, y: 660 * s))
    bubble.line(to: NSPoint(x: 470 * s, y: 600 * s))
    bubble.line(to: NSPoint(x: 470 * s, y: 680 * s))
    bubble.close()
    NSColor.white.setFill()
    bubble.fill()
    NSColor(calibratedRed: 0.36, green: 0.33, blue: 0.86, alpha: 1).setFill()
    for dot in 0..<3 {
        NSBezierPath(ovalIn: NSRect(x: (300 + CGFloat(dot) * 62) * s, y: 712 * s, width: 44 * s, height: 44 * s)).fill()
    }
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes {
    let data = drawIcon(size: size).representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name + ".png"))
}
print("Wrote \(sizes.count) icon images to \(output.path)")
