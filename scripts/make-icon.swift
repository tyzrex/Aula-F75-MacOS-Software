// Draws the app icon: `swift scripts/make-icon.swift Resources/AppIcon.icns`
import AppKit

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: an 824 pt rounded square centred in 1024.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(tilePath); ctx.setFillColor(NSColor(white: 0.1, alpha: 1).cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space, colors: [NSColor(red: 0.16, green: 0.15, blue: 0.24, alpha: 1).cgColor,
                                                    NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // A 75% keyboard in perspective-free top view: rows of keys with a synthwave sweep.
    let rows: [[CGFloat]] = [
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2],
        [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5],
        [1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.25],
        [1.25, 1.25, 1.25, 6.25, 1.25, 1.25],
    ]
    let unit: CGFloat = 52, gap: CGFloat = 8
    let totalW: CGFloat = 12 * unit + 11 * gap
    let originX = 512 - totalW / 2
    var y: CGFloat = 606
    let colors: [NSColor] = [NSColor(red: 0.45, green: 0.2, blue: 1, alpha: 1), NSColor(red: 0.95, green: 0.2, blue: 0.75, alpha: 1),
                             NSColor(red: 1, green: 0.55, blue: 0.2, alpha: 1)]
    func mix(_ t: CGFloat) -> NSColor {
        let p = max(0, min(0.999, t)) * CGFloat(colors.count - 1)
        let i = Int(p), f = p - CGFloat(i)
        let a = colors[i], b = colors[i + 1]
        return NSColor(red: a.redComponent + (b.redComponent - a.redComponent) * f, green: a.greenComponent + (b.greenComponent - a.greenComponent) * f,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * f, alpha: 1)
    }
    for (r, row) in rows.enumerated() {
        var x = originX
        let rowUnits = row.reduce(0, +)
        let scale = (totalW - CGFloat(row.count - 1) * gap) / (rowUnits * unit)
        for w in row {
            let width = w * unit * scale
            let rect = CGRect(x: x, y: y, width: width, height: unit)
            let t = ((x - originX) / totalW) * 0.85 + CGFloat(r) * 0.05
            let c = mix(t)
            let key = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 22, color: c.withAlphaComponent(0.85).cgColor)
            ctx.addPath(key); ctx.setFillColor(c.cgColor); ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(key); ctx.clip()
            let sheen = CGGradient(colorsSpace: space, colors: [NSColor.white.withAlphaComponent(0.35).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(sheen, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.midY), options: [])
            ctx.restoreGState()
            x += width + gap
        }
        y -= unit + gap
    }
    ctx.restoreGState()

    // Rim light.
    ctx.addPath(tilePath); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor); ctx.setLineWidth(3); ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let set = NSTemporaryDirectory() + "Keylume.iconset"
try? FileManager.default.removeItem(atPath: set)
try FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let png = drawIcon(size: px).representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: "\(set)/\(name).png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", out]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(out)" : "iconutil failed")
