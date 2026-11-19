import Foundation

/// Deterministic pseudo random numbers, so previews are pure functions of time.
struct SplitMix {
    var state: UInt64
    init(_ seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
}

struct KeyPoint { let index: Int; let x: Double; let y: Double }

enum Board {
    static let x0 = 30.0, y0 = 30.0, x1 = 630.0, y1 = 263.0
    static let points: [KeyPoint] = Layout.keys.filter { $0.hasLED }.map {
        KeyPoint(index: $0.index, x: (($0.x1 + $0.x2) / 2 - x0) / (x1 - x0), y: (($0.y1 + $0.y2) / 2 - y0) / (y1 - y0))
    }
    /// Snake path: rows top to bottom, alternating direction.
    static let snake: [Int] = {
        let rows = Array(Set(points.map { ($0.y * 100).rounded() / 100 })).sorted()
        var out: [Int] = []
        for (i, row) in rows.enumerated() {
            let r = points.filter { ($0.y * 100).rounded() / 100 == row }.sorted { $0.x < $1.x }
            out += (i % 2 == 0 ? r : r.reversed()).map { $0.index }
        }
        return out
    }()
}

/// Approximate on-screen previews of the firmware effects (looked at by eye, not exact copies).
public enum EffectPreview {
    
    public static func isAnimated(_ led: LEDConfig) -> Bool {
        led.effect != 1 && led.effect != Effects.customHW && (1...LEDConfig.slotCount).contains(led.effect)
    }

    /// Colors per key at time `t`; nil means "show the per-key table".
    public static func frame(_ led: LEDConfig, t: Double, palette: [UInt8]? = nil) -> [Int: RGB]? {
        let hw = led.effect
        if hw == Effects.customHW { return nil }
        guard let slot = led.slot(hw) else { return [:] }
        let e = Effects.byHW(hw)
        let k = max(0.15, Double(slot.brightness) / 9)
        let sp = 0.4 + 0.4 * Double(slot.speed)
        var base: RGB?
        if let e, e.hasColor, slot.color < Palette.colors {
            base = Palette.factory[slot.color]
            if let palette, hw < Palette.count, let c = Palette.color(palette, hw: hw, color: slot.color) { base = c }
        }
        func color(_ x: Double, _ v: Double = 1) -> RGB {
            if let base { return base.scaled(v * k) }
            return RGB.hsv(x * 0.8 + t * 0.05 * sp, 1, max(0, min(1, v * k)))
        }
        func origin(_ period: Double, _ salt: Int) -> (Double, Double, Double) {
            let n = Int(t / period)
            var rng = SplitMix(n &* 7919 &+ salt)
            let p = Board.points[Int(rng.unit() * Double(Board.points.count)) % Board.points.count]
            return (p.x, p.y, t.truncatingRemainder(dividingBy: period) / period)
        }
        let pts = Board.points
        var out: [Int: RGB] = [:]
        switch hw {
        case 1: // static
            for p in pts { out[p.index] = color(p.x) }
        case 2: // breathing
            let v = 0.15 + 0.85 * (0.5 - 0.5 * cos(2 * .pi * t * 0.4 * sp))
            for p in pts { out[p.index] = color(p.x, v) }
        case 3: // dream rainbow: whole board, hue cycles while breathing
            let v = 0.15 + 0.85 * (0.5 - 0.5 * cos(2 * .pi * t * 0.4 * sp))
            let c = RGB.hsv(t * 0.08 * sp, 1, v * k)
            for p in pts { out[p.index] = c }
        case 7, 12: // ripple spread / shadow follow (demo: a key is "pressed" every few seconds)
            let (ox, oy, phase) = origin(2.2 / sp, hw)
            let radius = phase * 1.4
            for p in pts {
                if hw == 12 && abs(p.y - oy) > 0.05 { out[p.index] = .black; continue }
                let d = hw == 12 ? abs(p.x - ox) : hypot(p.x - ox, (p.y - oy) * 0.4)
                out[p.index] = color(p.x, max(0, 1 - abs(d - radius) / 0.12) * (1 - phase))
            }
        case 4, 9: // instant trigger / snow trail: pressed keys light up and fade (snow trail fades slower)
            for p in pts { out[p.index] = .black }
            for salt in 0..<3 {
                let (ox, oy, phase) = origin((hw == 4 ? 1.2 : 2.4) / sp, 100 + salt)
                if let nearest = pts.min(by: { ($0.x - ox) * ($0.x - ox) + ($0.y - oy) * ($0.y - oy) < ($1.x - ox) * ($1.x - ox) + ($1.y - oy) * ($1.y - oy) }) {
                    out[nearest.index] = color(ox, 1 - phase)
                }
            }
        case 5, 8: // rain walk / starry sky
            let rate = (hw == 5 ? 0.5 : 0.3) * sp
            for p in pts {
                var rng = SplitMix(p.index * 31 + hw)
                let period = rng.range(2, 5)
                let ph = ((t * rate * 2 + rng.unit() * period).truncatingRemainder(dividingBy: period)) / period
                let v = hw == 5 ? max(0, 1 - ph * 4) : max(0, sin(ph * .pi) * 2 - 1)
                out[p.index] = color(p.x, v)
            }
        case 13: // sine wave
            for p in pts { out[p.index] = color(p.x, 0.15 + 0.85 * (0.5 + 0.5 * cos(2 * .pi * (p.x - t * 0.15 * sp)))) }
        case 11: // drifting
            let head = t * 6 * sp, n = Double(Board.snake.count)
            let byIndex = Dictionary(uniqueKeysWithValues: pts.map { ($0.index, $0) })
            for (i, idx) in Board.snake.enumerated() {
                var behind = (head - Double(i)).truncatingRemainder(dividingBy: n)
                if behind < 0 { behind += n }
                out[idx] = color(byIndex[idx]?.x ?? 0, max(0, 1 - behind / 8))
            }
        case 10: // flowing stream
            for p in pts {
                var f = (p.x * 3 - t * 0.6 * sp).truncatingRemainder(dividingBy: 1)
                if f < 0 { f += 1 }
                out[p.index] = color(p.x, f * f)
            }
        case 6, 15: // rainbow wheel / spinning windmill
            for p in pts {
                let a = atan2((p.y - 0.5) * 0.4, p.x - 0.5) / (2 * .pi)
                out[p.index] = RGB.hsv((hw == 15 ? a * 3 : a) - t * 0.12 * sp, 1, k)
            }
        case 16: // left-right scan
            let pos = 0.5 + 0.5 * sin(t * 1.6 * sp)
            for p in pts { out[p.index] = color(p.x, max(0, 1 - abs(p.x - pos) / 0.14)) }
        case 17: // rainbow waterfall
            for p in pts { out[p.index] = RGB.hsv(p.y * 0.6 - t * 0.15 * sp, 1, k) }
        default:
            for p in pts { out[p.index] = color(p.x, 0.3) }
        }
        return out
    }
}

/// Animations rendered on the Mac and streamed to the keyboard as live frames (cable only).
/// Nothing is stored on the keyboard; it returns to its own effect about 2 s after the stream stops.
public enum LiveAnimation: String, CaseIterable, Identifiable, Sendable {
    case rainbowWave = "rainbow-wave"
    case aurora, fire, matrixRain = "matrix-rain", sparkle, pulse, scanner, themeFlow = "theme-flow"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rainbowWave: return "Rainbow Wave"
        case .aurora: return "Aurora"
        case .fire: return "Fire"
        case .matrixRain: return "Matrix Rain"
        case .sparkle: return "Sparkle"
        case .pulse: return "Pulse"
        case .scanner: return "Scanner"
        case .themeFlow: return "Theme Flow"
        }
    }

    /// Frame at time `t` seconds. `color` is the accent color, `theme` feeds `themeFlow`.
    public func frame(t: Double, color: RGB, theme: Theme?, brightness: Double = 1) -> [Int: RGB] {
        var out: [Int: RGB] = [:]
        let pts = Board.points
        switch self {
        case .rainbowWave:
            for p in pts { out[p.index] = RGB.hsv(p.x * 0.9 - t * 0.2, 1, brightness) }
        case .aurora:
            for p in pts {
                let w = 0.5 + 0.5 * sin(2 * .pi * (p.x * 0.8 + t * 0.07)) * cos(2 * .pi * (p.y * 0.5 - t * 0.05))
                out[p.index] = RGB.mix(RGB(10, 20, 90), RGB.mix(RGB(0, 255, 140), RGB(150, 0, 255), 0.5 + 0.5 * sin(t * 0.3 + p.x * 3)), w).scaled(brightness)
            }
        case .fire:
            for p in pts {
                var rng = SplitMix(p.index)
                let flicker = 0.5 + 0.5 * sin(t * (6 + rng.unit() * 5) + rng.unit() * 6.28)
                let heat = max(0, min(1, (p.y * 1.1) * 0.9 + flicker * 0.45 - 0.1))
                let c: RGB = heat < 0.5 ? RGB.mix(RGB(80, 0, 0), RGB(255, 60, 0), heat * 2) : RGB.mix(RGB(255, 60, 0), RGB(255, 220, 40), (heat - 0.5) * 2)
                out[p.index] = c.scaled(brightness)
            }
        case .matrixRain:
            for p in pts {
                var rng = SplitMix(Int(p.x * 1000))
                let speed = rng.range(0.6, 1.6), offset = rng.unit() * 10
                var head = (t * speed + offset).truncatingRemainder(dividingBy: 2.2)
                if head < 0 { head += 2.2 }
                let d = head - p.y * 1.2
                let v = d >= 0 ? max(0, 1 - d * 1.8) : 0
                out[p.index] = (v > 0.9 ? RGB(200, 255, 200) : RGB(0, 255, 70)).scaled(v * brightness)
            }
        case .sparkle:
            for p in pts {
                var rng = SplitMix(p.index * 17 + 3)
                let period = rng.range(1.5, 4), phase = rng.unit() * period
                let ph = ((t + phase).truncatingRemainder(dividingBy: period)) / period
                let v = max(0, 1 - ph * 5)
                out[p.index] = RGB.mix(color.scaled(0.12), .init(255, 255, 255), v).scaled(brightness)
            }
        case .pulse:
            let v = 0.1 + 0.9 * (0.5 - 0.5 * cos(2 * .pi * t * 0.5))
            for p in pts { out[p.index] = color.scaled(v * brightness) }
        case .scanner:
            let pos = 0.5 + 0.5 * sin(t * 1.6)
            for p in pts { out[p.index] = color.scaled(max(0, 1 - abs(p.x - pos) / 0.12) * brightness) }
        case .themeFlow:
            let th = theme ?? Themes.all[0]
            let pos = Themes.positions(th.direction)
            for p in pts {
                var f = ((pos[p.index] ?? 0) + t * 0.1).truncatingRemainder(dividingBy: 2)
                if f > 1 { f = 2 - f }
                out[p.index] = th.color(at: f).scaled(brightness)
            }
        }
        return out
    }
}
