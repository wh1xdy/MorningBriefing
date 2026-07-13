// Generates the app icon set: a charcoal rounded square with the same yellow
// bolt the menu bar item wears. Run by make_app.sh:
//   swift scripts/make_icon.swift <output.iconset>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

/// Tinted bolt symbol at a generous raster size; it gets resampled per icon size.
func boltImage() -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 512, weight: .semibold)
    let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
    NSColor.systemYellow.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

let bolt = boltImage()

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(px)
    // macOS icon grid: content inset ~10%, continuous-corner feel via large radius.
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSColor(calibratedRed: 0.106, green: 0.106, blue: 0.118, alpha: 1).setFill()
    bg.fill()
    // Hairline edge so the dark tile does not dissolve into dark backgrounds.
    NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
    bg.lineWidth = max(1, s * 0.004)
    bg.stroke()

    let bs = bolt.size
    let target = s * 0.46
    let scale = target / max(bs.width, bs.height)
    let w = bs.width * scale, h = bs.height * scale
    bolt.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h),
              from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(px: Int, name: String) throws {
    let rep = render(px: px)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

for (points, scales) in [16: [1, 2], 32: [1, 2], 128: [1, 2], 256: [1, 2], 512: [1, 2]] {
    for scale in scales {
        let suffix = scale == 1 ? "" : "@\(scale)x"
        try write(px: points * scale, name: "icon_\(points)x\(points)\(suffix).png")
    }
}
print("iconset written to \(outDir)")
