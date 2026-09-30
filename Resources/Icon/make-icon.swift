// Draws the app icon and writes AppIcon.icns next to this script.
// Run: swift Resources/Icon/make-icon.swift  (or: make icon)
import AppKit

let canvas: CGFloat = 1024

func drawIcon(in ctx: CGContext) {
    // Work in top-left coordinates, like the design grid.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    // Tile: the macOS icon grid leaves a 100 pt margin on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let colors = [NSColor(srgbRed: 0.27, green: 0.55, blue: 1.0, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.11, green: 0.23, blue: 0.66, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    ctx.restoreGState()

    let white = NSColor.white.cgColor

    // Display: screen, neck and foot.
    let screen = CGRect(x: 222, y: 270, width: 580, height: 380)
    let screenPath = CGPath(roundedRect: screen, cornerWidth: 44, cornerHeight: 44, transform: nil)
    ctx.addPath(screenPath)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    ctx.fillPath()
    ctx.addPath(screenPath)
    ctx.setStrokeColor(white)
    ctx.setLineWidth(34)
    ctx.strokePath()

    ctx.setFillColor(white)
    ctx.fill(CGRect(x: 482, y: 667, width: 60, height: 80))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 372, y: 740, width: 280, height: 40),
                       cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.fillPath()

    // Touch point with ripple rings, placed on the screen.
    let touch = CGPoint(x: 588, y: 452)
    for (radius, alpha) in [(118.0, 0.28), (80.0, 0.55)] {
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(18)
        ctx.strokeEllipse(in: CGRect(x: touch.x - radius, y: touch.y - radius, width: radius * 2, height: radius * 2))
    }
    ctx.setFillColor(white)
    ctx.fillEllipse(in: CGRect(x: touch.x - 42, y: touch.y - 42, width: 84, height: 84))
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: here.appendingPathComponent("AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", here.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
