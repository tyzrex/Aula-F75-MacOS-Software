import SwiftUI
import AulaKit

extension RGB {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1) }
    init(_ c: Color) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
        self.init(Int((ns.redComponent * 255).rounded()), Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }
    /// Perceived brightness, to pick a readable label color.
    var luminance: Double { (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255 }
}

/// Draws the F75 from the vendor key table. Keys are colored by `colors`, labeled by `label`.
struct KeyboardCanvas: View {
    var colors: [Int: RGB] = [:]
    var selection: Set<Int> = []
    var label: (KeyInfo) -> String = { $0.label }
    var highlighted: Set<Int> = []
    var onTap: ((KeyInfo) -> Void)?
    var onDrag: ((KeyInfo) -> Void)?

    private static let bounds = CGRect(x: 22, y: 22, width: 616, height: 248)
    private static let outset: CGFloat = 4.5

    private func transform(in size: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let b = Self.bounds
        let s = min(size.width / b.width, size.height / b.height)
        return (s, CGPoint(x: (size.width - b.width * s) / 2 - b.minX * s, y: (size.height - b.height * s) / 2 - b.minY * s))
    }

    private func rect(_ k: KeyInfo, _ t: (scale: CGFloat, origin: CGPoint)) -> CGRect {
        let o = Self.outset
        return CGRect(x: (k.x1 - o) * t.scale + t.origin.x, y: (k.y1 - o) * t.scale + t.origin.y,
                      width: (k.x2 - k.x1 + 2 * o) * t.scale, height: (k.y2 - k.y1 + 2 * o) * t.scale)
    }

    private func key(at p: CGPoint, size: CGSize) -> KeyInfo? {
        let t = transform(in: size)
        return Layout.keys.first { $0.hasLED && rect($0, t).contains(p) }
    }

    var body: some View {
        GeometryReader { geo in
            let t = transform(in: geo.size)
            Canvas { ctx, size in
                let board = CGRect(x: (Self.bounds.minX + 2) * t.scale + t.origin.x, y: (Self.bounds.minY + 2) * t.scale + t.origin.y,
                                   width: (Self.bounds.width - 4) * t.scale, height: (Self.bounds.height - 4) * t.scale)
                ctx.fill(Path(roundedRect: board, cornerRadius: 14 * t.scale), with: .color(Color(white: 0.09)))
                for k in Layout.keys where k.hasLED {
                    let r = rect(k, t)
                    let c = colors[k.index]
                    let fill: Color = c?.color ?? Color(white: 0.2)
                    let path = Path(roundedRect: r, cornerRadius: 5 * t.scale)
                    ctx.fill(path, with: .color(fill))
                    let sel = selection.contains(k.index)
                    ctx.stroke(path, with: .color(sel ? .white : (highlighted.contains(k.index) ? .orange : Color(white: 0.32))), lineWidth: sel ? 2.5 : (highlighted.contains(k.index) ? 2 : 1))
                    let text = label(k)
                    if !text.isEmpty {
                        let dark = (c?.luminance ?? 0.1) > 0.55
                        let size = max(7, min(12, r.height * 0.34)) * (text.count > 5 ? 0.78 : 1)
                        ctx.draw(Text(text).font(.system(size: size, weight: .medium, design: .rounded)).foregroundColor(dark ? .black.opacity(0.8) : .white.opacity(0.85)),
                                 at: CGPoint(x: r.midX, y: r.midY))
                    }
                }
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
}
