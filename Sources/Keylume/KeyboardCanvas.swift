import SwiftUI
import KeylumeKit

/// Draws the F75: an aluminium case, keycaps with legends, the knob, and the LED color under each key.
///
/// Key positions come from the vendor key table. Keys are tinted by `colors` (empty = matte caps),
/// legends come from `legend` (default: the physical legend in the given `flavor`).
struct KeyboardCanvas: View {
    var colors: [Int: RGB] = [:]
    var flavor: Flavor = .windows
    var selection: Set<Int> = []
    var highlighted: Set<Int> = []
    var showLegends = true
    var legend: ((KeyInfo) -> Legend)?
    var onTap: ((KeyInfo) -> Void)?
    var onDrag: ((KeyInfo) -> Void)?

    // Drawing area in layout units, including the case and its margin.
    private static let bounds = CGRect(x: 8, y: 4, width: 648, height: 282)
    private static let caseRect = CGRect(x: 15, y: 11, width: 634, height: 268)
    private static let outset: CGFloat = 4.5
    private static let knobCenter = CGPoint(x: 617, y: 43.5)
    private static let knobRadius: CGFloat = 15

    private struct Transform { var scale: CGFloat; var origin: CGPoint
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + origin.x, y: p.y * scale + origin.y) }
        func rect(_ r: CGRect) -> CGRect { CGRect(x: r.minX * scale + origin.x, y: r.minY * scale + origin.y, width: r.width * scale, height: r.height * scale) }
    }

    private func transform(in size: CGSize) -> Transform {
        let b = Self.bounds
        let s = min(size.width / b.width, size.height / b.height)
        return Transform(scale: s, origin: CGPoint(x: (size.width - b.width * s) / 2 - b.minX * s, y: (size.height - b.height * s) / 2 - b.minY * s))
    }

    private func cap(_ k: KeyInfo) -> CGRect {
        CGRect(x: k.x1 - Self.outset, y: k.y1 - Self.outset, width: k.x2 - k.x1 + 2 * Self.outset, height: k.y2 - k.y1 + 2 * Self.outset)
    }

    private func key(at p: CGPoint, size: CGSize) -> KeyInfo? {
        let t = transform(in: size)
        return Layout.keys.first { $0.hasLED && t.rect(cap($0)).insetBy(dx: -1, dy: -1).contains(p) }
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let t = transform(in: size)
                drawCase(&ctx, t)
                if !colors.isEmpty { drawGlow(&ctx, t) }
                for k in Layout.keys where k.hasLED { drawKey(&ctx, k, t) }
                drawKnob(&ctx, t)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard let onDrag, hypot(v.translation.width, v.translation.height) >= 4 else { return }
                    if let s = key(at: v.startLocation, size: geo.size) { onDrag(s) }
                    if let k = key(at: v.location, size: geo.size) { onDrag(k) }
                }
                .onEnded { v in
                    if let k = key(at: v.location, size: geo.size), hypot(v.translation.width, v.translation.height) < 4 { onTap?(k) }
                })
        }
        .aspectRatio(Self.bounds.width / Self.bounds.height, contentMode: .fit)
    }

    // MARK: drawing

    private func drawCase(_ ctx: inout GraphicsContext, _ t: Transform) {
        let r = t.rect(Self.caseRect)
        let path = Path(roundedRect: r, cornerRadius: 16 * t.scale, style: .continuous)
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: .black.opacity(0.45), radius: 10 * t.scale, x: 0, y: 5 * t.scale))
            l.fill(path, with: .color(Color(white: 0.12)))
        }
        ctx.fill(path, with: .linearGradient(Gradient(colors: [Color(white: 0.20), Color(white: 0.11)]),
                                             startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        ctx.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.03)]),
                                               startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)), lineWidth: max(1, t.scale))
        // The plate the keys sit on.
        let plate = Path(roundedRect: r.insetBy(dx: 6 * t.scale, dy: 6 * t.scale), cornerRadius: 11 * t.scale, style: .continuous)
        ctx.fill(plate, with: .color(Color(white: 0.055)))
    }

    /// Light bleeding out from under the keys.
    private func drawGlow(_ ctx: inout GraphicsContext, _ t: Transform) {
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 7 * t.scale))
            l.blendMode = .plusLighter
            for k in Layout.keys where k.hasLED {
                guard let c = colors[k.index], c.luminance > 0.03 else { continue }
                l.fill(Path(roundedRect: t.rect(cap(k)).insetBy(dx: -1.5 * t.scale, dy: -1.5 * t.scale), cornerRadius: 6 * t.scale),
                       with: .color(c.color.opacity(0.55)))
            }
        }
    }

    private func drawKey(_ ctx: inout GraphicsContext, _ k: KeyInfo, _ t: Transform) {
        let r = t.rect(cap(k))
        let s = t.scale
        let radius = 5 * s
        let led = colors[k.index]
        let isSelected = selection.contains(k.index), isHighlighted = highlighted.contains(k.index)

        // Cap body (the sides), then the top face, which is smaller toward the bottom for a sculpted look.
        let body = Path(roundedRect: r, cornerRadius: radius, style: .continuous)
        let face = Path(roundedRect: CGRect(x: r.minX + 1.6 * s, y: r.minY + 1 * s, width: r.width - 3.2 * s, height: r.height - 4 * s),
                        cornerRadius: radius * 0.8, style: .continuous)
        let faceRect = CGRect(x: r.minX + 1.6 * s, y: r.minY + 1 * s, width: r.width - 3.2 * s, height: r.height - 4 * s)

        if let c = led {
            // Translucent keycap with the LED shining through.
            let base = RGB.mix(RGB(18, 18, 20), c, 0.55)
            let top = RGB.mix(RGB(34, 34, 38), c, 0.95)
            ctx.fill(body, with: .color(base.color))
            ctx.fill(face, with: .linearGradient(Gradient(colors: [top.color, RGB.mix(top, RGB(0, 0, 0), 0.18).color]),
                                                 startPoint: CGPoint(x: faceRect.midX, y: faceRect.minY), endPoint: CGPoint(x: faceRect.midX, y: faceRect.maxY)))
            ctx.fill(face, with: .linearGradient(Gradient(colors: [.white.opacity(0.20), .white.opacity(0)]),
                                                 startPoint: CGPoint(x: faceRect.midX, y: faceRect.minY), endPoint: CGPoint(x: faceRect.midX, y: faceRect.midY)))
        } else {
            ctx.fill(body, with: .color(Color(white: 0.085)))
            ctx.fill(face, with: .linearGradient(Gradient(colors: [Color(white: 0.30), Color(white: 0.21)]),
                                                 startPoint: CGPoint(x: faceRect.midX, y: faceRect.minY), endPoint: CGPoint(x: faceRect.midX, y: faceRect.maxY)))
            ctx.stroke(face, with: .color(.white.opacity(0.10)), lineWidth: 0.6)
        }

        if isSelected {
            ctx.stroke(body, with: .color(.white), lineWidth: max(2, 2.4 * s))
            ctx.stroke(Path(roundedRect: r.insetBy(dx: -2 * s, dy: -2 * s), cornerRadius: radius + 2 * s, style: .continuous), with: .color(Color.accentColor.opacity(0.9)), lineWidth: max(1.5, 1.6 * s))
        } else if isHighlighted {
            ctx.stroke(body, with: .color(.orange), lineWidth: max(1.8, 2 * s))
        }

        guard showLegends else { return }
        let text = legend?(k) ?? Legends.physical(k, flavor: flavor)
        guard !text.isEmpty else { return }
        let dark = (led?.luminance ?? 0) > 0.55
        let ink: Color = led == nil ? .white.opacity(0.88) : (dark ? .black.opacity(0.72) : .white.opacity(0.92))
        let count = text.main.count
        let hasCaption = text.caption != nil
        let base = min(13, faceRect.height * (hasCaption ? 0.42 : 0.40))
        let mainSize = max(6, base * (count > 6 ? 0.62 : count > 3 ? 0.78 : count > 2 ? 0.9 : 1))
        let mainPoint = CGPoint(x: faceRect.midX, y: hasCaption ? faceRect.midY - faceRect.height * 0.10 : faceRect.midY)
        ctx.draw(Text(text.main).font(.system(size: mainSize, weight: .semibold, design: .rounded)).foregroundColor(ink), at: mainPoint)
        if let caption = text.caption {
            ctx.draw(Text(caption).font(.system(size: max(5, base * 0.5), weight: .medium, design: .rounded)).foregroundColor(ink.opacity(0.7)),
                     at: CGPoint(x: faceRect.midX, y: faceRect.midY + faceRect.height * 0.27))
        }
    }

    private func drawKnob(_ ctx: inout GraphicsContext, _ t: Transform) {
        let c = t.point(Self.knobCenter), r = Self.knobRadius * t.scale
        let outer = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: .black.opacity(0.6), radius: 3 * t.scale, x: 0, y: 2 * t.scale))
            l.fill(outer, with: .color(Color(white: 0.1)))
        }
        ctx.fill(outer, with: .conicGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.2), Color(white: 0.6), Color(white: 0.2), Color(white: 0.55)]), center: c))
        let inner = Path(ellipseIn: CGRect(x: c.x - r * 0.78, y: c.y - r * 0.78, width: r * 1.56, height: r * 1.56))
        ctx.fill(inner, with: .linearGradient(Gradient(colors: [Color(white: 0.30), Color(white: 0.12)]),
                                              startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
        var notch = Path(); notch.move(to: CGPoint(x: c.x, y: c.y - r * 0.68)); notch.addLine(to: CGPoint(x: c.x, y: c.y - r * 0.3))
        ctx.stroke(notch, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: max(1.4, 1.8 * t.scale), lineCap: .round))
    }
}
