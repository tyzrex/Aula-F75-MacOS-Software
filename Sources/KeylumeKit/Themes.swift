import Foundation

public enum GradientDirection: String, Sendable { case x, y, diagonal, center }

/// A per-key color theme: a gradient over the key positions plus fixed accent keys.
public struct Theme: Sendable, Identifiable {
    public let name: String
    public let summary: String
    public let stops: [(Double, RGB)]
    public let accents: [String: RGB]
    public let direction: GradientDirection
    public var id: String { name }

    public init(name: String, summary: String, stops: [(Double, RGB)], accents: [String: RGB] = [:], direction: GradientDirection = .x) {
        self.name = name; self.summary = summary; self.stops = stops; self.accents = accents; self.direction = direction
    }

    public func color(at t: Double) -> RGB {
        for (a, b) in zip(stops, stops.dropFirst()) where t <= b.0 {
            let f = b.0 == a.0 ? 1 : (t - a.0) / (b.0 - a.0)
            return RGB.mix(a.1, b.1, f)
        }
        return stops.last?.1 ?? .black
    }

    /// {matrix index: color} for every key.
    public func render() -> [Int: RGB] {
        var out: [Int: RGB] = [:]
        for (idx, t) in Themes.positions(direction) { out[idx] = color(at: t) }
        for (key, c) in accents { if let i = Keymap.index(of: key) { out[i] = c } }
        return out
    }
}

public enum Themes {
    public static var all: [Theme] { ThemeData.all }
    public static func named(_ n: String) -> Theme? { all.first { $0.name == n } }

    static let centers: [(Int, Double, Double)] = Layout.keys.filter { $0.hasLED }.map { ($0.index, ($0.x1 + $0.x2) / 2, ($0.y1 + $0.y2) / 2) }

    /// {matrix index: 0...1} along a gradient direction.
    public static func positions(_ d: GradientDirection) -> [Int: Double] {
        let xs = centers.map { $0.1 }, ys = centers.map { $0.2 }
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        let placed: [(Int, Double)] = centers.map { idx, x, y in
            switch d {
            case .x: return (idx, x)
            case .y: return (idx, y)
            case .diagonal: return (idx, x + y)
            case .center: return (idx, hypot((x - (x0 + x1) / 2) / (x1 - x0), (y - (y0 + y1) / 2) / (y1 - y0)))
            }
        }
        let lo = placed.map { $0.1 }.min()!, hi = placed.map { $0.1 }.max()!
        return Dictionary(uniqueKeysWithValues: placed.map { ($0.0, ($0.1 - lo) / (hi - lo)) })
    }

    /// Single color on every key.
    public static func solid(_ c: RGB) -> [Int: RGB] {
        Dictionary(uniqueKeysWithValues: centers.map { ($0.0, c) })
    }
}
