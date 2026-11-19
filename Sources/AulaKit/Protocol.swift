import Foundation

/// Wired (USB cable) protocol of the AULA F75: 520-byte feature reports, id 0x06.
///
///     [0] 0x06  [1] command  [2] sub (keymap layer)  [3] 0  [4] 0x01  [5] 0
///     [6..7] length (little endian)  [8...] data
///
/// A read sends the request as a feature report, then fetches the reply the same way.
/// The reply echoes the header followed by the data. Writes are not acknowledged, so
/// every write is followed by a read-back that must match byte for byte.
///
/// Sources: reverse engineering of the vendor's OemDrv.exe, cross-checked against the
/// hardware-verified notes of bakiakyol/aula-f75-hub (MIT). See NOTICE.
public enum Wire {
    public static let reportID: UInt8 = 0x06
    public static let reportLength = 520
    public static let headerLength = 8
    public static let pageLength = 0x200

    // reads
    public static let readKeymap: UInt8 = 0x83
    public static let readLED: UInt8 = 0x84
    public static let readCustom: UInt8 = 0x86
    public static let readPalette: UInt8 = 0x8A
    public static let readInfo: UInt8 = 0x82      // sub 1: uuid, firmware version
    public static let readBattery: UInt8 = 0x87
    // writes
    public static let writeKeymap: UInt8 = 0x03   // layout taken from the official Aula Hub 1.1.22 (JS source)
    public static let writeLED: UInt8 = 0x04
    public static let writeCustom: UInt8 = 0x06
    public static let writePalette: UInt8 = 0x0A
    public static let live: UInt8 = 0x08

    /// Keymap table selector: bits 0-1 layer (0 base, 1 Fn), bit 2 system (0 Windows table, 1 Mac table).
    public static func keymapSub(layer: Int, system: Int) -> UInt8 { UInt8((layer & 3) | ((system & 1) << 2)) }
    /// The keymap page that is written: 504 bytes of keys, six zero bytes and the 5a a5 trailer.
    public static let keymapPage = 512

    public static let ledLength = 128
    public static let ledMagic: [UInt8] = [0x5A, 0xA5]
    public static let matrixLength = 126
    public static let customLength = matrixLength * 3
    public static let keymapLength = matrixLength * 4
    public static let paletteLength = 490
    public static let paletteMagicOffset = 506
    public static let liveKeys = 122
    /// The firmware repaints after a write and is busy for a moment.
    public static let settle: TimeInterval = 0.4

    /// Commands that are never sent: they return firmware code or reset the keyboard.
    public static let forbidden: Set<UInt8> = [0x88, 0x8B, 0x8E, 0x91, 0x11]

    public static func request(cmd: UInt8, sub: UInt8, length: Int) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: reportLength)
        r[0] = reportID; r[1] = cmd; r[2] = sub; r[3] = 0; r[4] = 1; r[5] = 0
        r[6] = UInt8(length & 0xFF); r[7] = UInt8((length >> 8) & 0xFF)
        return r
    }

    /// `declaredLength` is the length field of the header; it defaults to the data size
    /// (the keymap write declares 504 bytes but carries a 512-byte page, like the official app).
    public static func writeReport(cmd: UInt8, sub: UInt8 = 0, data: [UInt8], declaredLength: Int? = nil) throws -> [UInt8] {
        guard data.count <= reportLength - headerLength else { throw AulaError.protocolError("too much data for one report") }
        var r = request(cmd: cmd, sub: sub, length: declaredLength ?? data.count)
        r.replaceSubrange(headerLength..<headerLength + data.count, with: data)
        return r
    }

    /// The first `length` data bytes of a reply to `cmd`/`sub`, or nil if it answers something else.
    public static func reply(_ report: [UInt8], cmd: UInt8, sub: UInt8, length: Int) -> [UInt8]? {
        var rep = report
        // Some stacks strip the report id; tolerate that.
        if rep.count >= 2, rep[0] != reportID, rep[0] == cmd { rep.insert(reportID, at: 0) }
        guard rep.count >= headerLength + length, rep[0] == reportID, rep[1] == cmd, rep[2] == sub else { return nil }
        return Array(rep[headerLength..<headerLength + length])
    }

    public static let liveHeader: [UInt8] = [reportID, live, 0, 0, 1, 0, 0x7A, 0x01]

    public static func liveReport(colors: [Int: RGB]) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: reportLength)
        r.replaceSubrange(0..<headerLength, with: liveHeader)
        for (idx, c) in colors where idx >= 0 && idx < liveKeys {
            let o = headerLength + 3 * idx
            r[o] = c.r; r[o + 1] = c.g; r[o + 2] = c.b
        }
        return r
    }
}

public enum AulaError: Error, LocalizedError, Equatable {
    case notFound
    case openFailed(String)
    case protocolError(String)
    case refused(String)
    case noReply(String)
    case verifyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "No AULA F75 found on the cable. Plug it in with USB (the 2.4G dongle and Bluetooth can't be configured)."
        case .openFailed(let s): return "Couldn't open the keyboard: \(s)"
        case .protocolError(let s): return s
        case .refused(let s): return "Refused: \(s)"
        case .noReply(let s): return s
        case .verifyFailed(let s): return s
        }
    }
}

public struct RGB: Hashable, Sendable, Codable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    public init(_ r: Int, _ g: Int, _ b: Int) { self.init(UInt8(clamping: r), UInt8(clamping: g), UInt8(clamping: b)) }
    public static let black = RGB(0, 0, 0)
    public var hex: String { String(format: "#%02x%02x%02x", r, g, b) }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(Int((v >> 16) & 0xFF), Int((v >> 8) & 0xFF), Int(v & 0xFF))
    }

    public func scaled(_ k: Double) -> RGB {
        let k = max(0, min(1, k))
        return RGB(Int((Double(r) * k).rounded()), Int((Double(g) * k).rounded()), Int((Double(b) * k).rounded()))
    }

    public static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let t = max(0, min(1, t))
        func m(_ x: UInt8, _ y: UInt8) -> Int { Int((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
        return RGB(m(a.r, b.r), m(a.g, b.g), m(a.b, b.b))
    }

    public static func hsv(_ h: Double, _ s: Double = 1, _ v: Double = 1) -> RGB {
        let h = h - floor(h)
        let i = Int(h * 6), f = h * 6 - Double(i)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch i % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGB(Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

// MARK: - Effects

public struct Effect: Sendable, Hashable, Identifiable {
    public let hw: Int
    public let name: String
    public let hasSpeed: Bool
    public let hasColor: Bool
    public var id: Int { hw }
    public var title: String { name.split(separator: "-").map { $0.capitalized }.joined(separator: " ") }
}

public enum Effects {
    /// Mode numbers and names as listed by the official Aula Hub 1.1.22 for the F75
    /// (mode = byte[9] << 8 | byte[10]). `custom` is 277 (0x0115) there.
    public static let all: [Effect] = [
        Effect(hw: 1, name: "static", hasSpeed: false, hasColor: true),
        Effect(hw: 2, name: "breathing", hasSpeed: true, hasColor: true),
        Effect(hw: 3, name: "dream-rainbow", hasSpeed: true, hasColor: false),
        Effect(hw: 4, name: "instant-trigger", hasSpeed: true, hasColor: true),   // reacts to key presses
        Effect(hw: 5, name: "rain-walk", hasSpeed: true, hasColor: true),
        Effect(hw: 6, name: "rainbow-wheel", hasSpeed: true, hasColor: false),
        Effect(hw: 7, name: "ripple-spread", hasSpeed: true, hasColor: true),     // reacts to key presses
        Effect(hw: 8, name: "starry-sky", hasSpeed: true, hasColor: true),
        Effect(hw: 9, name: "snow-trail", hasSpeed: true, hasColor: true),        // reacts to key presses
        Effect(hw: 10, name: "flowing-stream", hasSpeed: true, hasColor: true),
        Effect(hw: 11, name: "drifting", hasSpeed: true, hasColor: true),
        Effect(hw: 12, name: "shadow-follow", hasSpeed: true, hasColor: true),    // reacts to key presses
        Effect(hw: 13, name: "sine-wave", hasSpeed: true, hasColor: true),
        Effect(hw: 15, name: "spinning-windmill", hasSpeed: true, hasColor: false),
        Effect(hw: 16, name: "left-right-scan", hasSpeed: true, hasColor: true),
        Effect(hw: 17, name: "rainbow-waterfall", hasSpeed: true, hasColor: false),
        Effect(hw: 277, name: "custom", hasSpeed: false, hasColor: false),
    ]
    public static let customHW = 277
    public static let reactive: Set<Int> = [4, 7, 9, 12]
    public static func named(_ n: String) -> Effect? { all.first { $0.name == n } }
    public static func byHW(_ hw: Int) -> Effect? { all.first { $0.hw == hw } }
}

public enum Names {
    public static let colors = ["red", "green", "blue", "yellow", "purple", "cyan", "white", "multi"]
    public static let sideModes = ["off", "fill", "breathing", "static"]
    public static let knobModes = ["media", "lighting"]
    public static let osModes = ["windows", "android", "mac"]
    public static let sleepChoices = [60, 90, 120, 180, 240, 300, 600, 900, 1200]
    public static func sleepText(_ s: Int) -> String {
        if s == 0 { return "never" }
        return s % 60 == 0 ? "\(s / 60) min" : String(format: "%g min", Double(s) / 60)
    }
}

// MARK: - LED block

public struct EffectSlot: Hashable, Sendable {
    public var brightness: Int  // 0-9
    public var speed: Int       // 0-4
    public var color: Int       // 0-6 palette, 7 multicolor
    public init(brightness: Int, speed: Int, color: Int) { self.brightness = brightness; self.speed = speed; self.color = color }
}

/// The 128-byte lighting block (read 0x84 / write 0x04).
public struct LEDConfig: Equatable, Sendable {
    public static let effectHighOffset = 9
    public static let effectOffset = 10
    public static let winLockOffset = 15
    public static let sideModeOffset = 18
    public static let sleepOffset = 24
    public static let knobModeOffset = 26
    public static let osModeOffset = 27
    public static let slotsOffset = 58
    public static let slotCount = 34
    public static let sleepUnit = 30
    public static let sleepMax = 1200
    /// The only bytes a write may change (plus the active effect's own slot).
    public static let writable: Set<Int> = [effectHighOffset, effectOffset, winLockOffset, sideModeOffset, sleepOffset, knobModeOffset, osModeOffset]

    public private(set) var raw: [UInt8]

    public init(raw: [UInt8]) throws {
        guard raw.count == Wire.ledLength, Array(raw.suffix(2)) == Wire.ledMagic else {
            throw AulaError.protocolError("unexpected LED config block")
        }
        self.raw = raw
    }

    /// 16-bit mode: byte[9] is the high byte (0 for normal effects, 1 for "custom" = 277).
    public var effect: Int {
        get { Int(raw[Self.effectHighOffset]) << 8 | Int(raw[Self.effectOffset]) }
        set { raw[Self.effectHighOffset] = UInt8((newValue >> 8) & 0xFF); raw[Self.effectOffset] = UInt8(newValue & 0xFF) }
    }
    public var winLock: Bool { get { raw[Self.winLockOffset] != 0 } set { raw[Self.winLockOffset] = newValue ? 1 : 0 } }
    public var sideMode: Int { get { Int(raw[Self.sideModeOffset]) } set { raw[Self.sideModeOffset] = UInt8(clamping: min(max(newValue, 0), 3)) } }
    public var knobMode: Int { get { Int(raw[Self.knobModeOffset]) } set { raw[Self.knobModeOffset] = UInt8(clamping: min(max(newValue, 0), 1)) } }
    public var osMode: Int { get { Int(raw[Self.osModeOffset]) } set { raw[Self.osModeOffset] = UInt8(clamping: min(max(newValue, 0), 2)) } }

    /// Idle seconds before sleeping (wireless only); 0 = never.
    public var sleep: Int { Int(raw[Self.sleepOffset]) * Self.sleepUnit }
    public mutating func setSleep(_ seconds: Int) throws {
        guard seconds % Self.sleepUnit == 0, (0...Self.sleepMax).contains(seconds) else {
            throw AulaError.refused("sleep time must be a multiple of 30 s, at most 20 min")
        }
        raw[Self.sleepOffset] = UInt8(seconds / Self.sleepUnit)
    }

    public static func slotOffset(_ hw: Int) -> Int? {
        (1...slotCount).contains(hw) ? slotsOffset + 2 * (hw - 1) : nil
    }

    public func slot(_ hw: Int) -> EffectSlot? {
        guard let o = Self.slotOffset(hw) else { return nil }
        return EffectSlot(brightness: Int(raw[o]), speed: Int(raw[o + 1] >> 4), color: Int(raw[o + 1] & 0x0F))
    }

    public mutating func setSlot(_ hw: Int, _ s: EffectSlot) throws {
        guard let o = Self.slotOffset(hw), (0...9).contains(s.brightness), (0...4).contains(s.speed), (0...7).contains(s.color) else {
            throw AulaError.refused("brightness must be 0-9, speed 0-4, color 0-7")
        }
        raw[o] = UInt8(s.brightness)
        raw[o + 1] = UInt8(s.speed << 4 | s.color)
    }
}

// MARK: - Palettes

/// One palette per firmware effect number 0-22: 7 colors x RGB. 490 bytes in total.
public enum Palette {
    public static let count = 23
    public static let colors = 7
    public static let factory: [RGB] = [RGB(255, 0, 0), RGB(0, 255, 0), RGB(0, 0, 255), RGB(255, 255, 0),
                                        RGB(255, 0, 255), RGB(0, 255, 255), RGB(255, 255, 255)]

    static func offset(_ hw: Int, _ color: Int) throws -> Int {
        guard (0..<count).contains(hw) else { throw AulaError.refused("effect \(hw) has no palette") }
        guard (0..<colors).contains(color) else { throw AulaError.refused("color must be 0-6") }
        return hw * colors * 3 + color * 3
    }

    public static func color(_ raw: [UInt8], hw: Int, color: Int) -> RGB? {
        guard let o = try? offset(hw, color), o + 2 < raw.count else { return nil }
        return RGB(raw[o], raw[o + 1], raw[o + 2])
    }

    public static func setting(_ raw: [UInt8], hw: Int, color: Int, to c: RGB) throws -> [UInt8] {
        var b = raw
        let o = try offset(hw, color)
        b[o] = c.r; b[o + 1] = c.g; b[o + 2] = c.b
        return b
    }

    public static func reset(_ raw: [UInt8], hw: Int) throws -> [UInt8] {
        var r = raw
        for (i, c) in factory.enumerated() { r = try setting(r, hw: hw, color: i, to: c) }
        return r
    }
}

// MARK: - Per-key colors

public enum Custom {
    /// {matrix index: color} -> 378 bytes (all R, then all G, then all B).
    public static func encode(_ colors: [Int: RGB]) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: Wire.customLength)
        let n = Wire.matrixLength
        for (i, c) in colors where (0..<n).contains(i) { b[i] = c.r; b[n + i] = c.g; b[2 * n + i] = c.b }
        return b
    }

    public static func decode(_ raw: [UInt8]) -> [Int: RGB] {
        let n = Wire.matrixLength
        guard raw.count >= Wire.customLength else { return [:] }
        return Dictionary(uniqueKeysWithValues: (0..<n).map { ($0, RGB(raw[$0], raw[n + $0], raw[2 * n + $0])) })
    }
}
