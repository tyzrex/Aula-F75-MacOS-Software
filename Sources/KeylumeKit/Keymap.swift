import Foundation

/// A 4-byte keymap entry `[type, mods, key2, key1]`.
public struct KeyEntry: Hashable, Sendable {
    public var bytes: [UInt8]
    public init(_ bytes: [UInt8]) { precondition(bytes.count == 4); self.bytes = bytes }

    public static let disabled = KeyEntry([0, 0, 0, 0])
    public static func key(hid: Int, modifiers: Int = 0) -> KeyEntry { KeyEntry([0, UInt8(modifiers & 0xFF), 0, UInt8(hid & 0xFF)]) }
    public static func consumer(_ usage: Int) -> KeyEntry { KeyEntry([2, 0, UInt8((usage >> 8) & 0xFF), UInt8(usage & 0xFF)]) }

    public var type: UInt8 { bytes[0] }
    public var isEmpty: Bool { bytes == [0, 0, 0, 0] }
    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

    /// Human readable name, best effort.
    public var description: String {
        if isEmpty { return "—" }
        switch bytes[0] {
        case 0:
            var parts: [String] = []
            for (name, bit) in Keymap.modifiers.sorted(by: { $0.value < $1.value }) where Int(bytes[1]) & bit != 0 { parts.append(Keymap.display(name)) }
            if bytes[3] != 0 { parts.append(Keymap.hidName[Int(bytes[3])].map(Keymap.display) ?? String(format: "HID %02x", bytes[3])) }
            return parts.joined(separator: " + ")
        case 2:
            let u = Int(bytes[2]) << 8 | Int(bytes[3])
            return Keymap.consumerName[u] ?? String(format: "Media %04x", u)
        case 3: return "Macro \(bytes[3])"
        case 7: return "Special \(hex)"
        case 8: return "Fn function \(hex)"
        case 0x0D: return "Fn"
        default: return hex
        }
    }
}

public enum Keymap {
    public static let hid: [String: Int] = {
        var d: [String: Int] = [:]
        for i in 0..<26 { d[String(UnicodeScalar(UInt8(97 + i)))] = 0x04 + i }
        for i in 1...9 { d[String(i)] = 0x1E + i - 1 }
        d["0"] = 0x27
        let rest: [String: Int] = [
            "enter": 0x28, "esc": 0x29, "backspace": 0x2A, "tab": 0x2B, "space": 0x2C, "minus": 0x2D, "equal": 0x2E,
            "lbracket": 0x2F, "rbracket": 0x30, "backslash": 0x31, "iso_hash": 0x32, "semicolon": 0x33, "quote": 0x34,
            "grave": 0x35, "comma": 0x36, "period": 0x37, "slash": 0x38, "capslock": 0x39,
            "printscreen": 0x46, "scrolllock": 0x47, "pause": 0x48, "insert": 0x49, "home": 0x4A, "pgup": 0x4B,
            "delete": 0x4C, "end": 0x4D, "pgdn": 0x4E, "right": 0x4F, "left": 0x50, "down": 0x51, "up": 0x52,
            "iso_backslash": 0x64, "menu": 0x65,
        ]
        d.merge(rest) { a, _ in a }
        for i in 1...12 { d["f\(i)"] = 0x3A + i - 1 }
        return d
    }()

    public static let hidName: [Int: String] = Dictionary(hid.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })

    public static let modifiers: [String: Int] = [
        "lctrl": 0x01, "lshift": 0x02, "lalt": 0x04, "lwin": 0x08,
        "rctrl": 0x10, "rshift": 0x20, "ralt": 0x40, "rwin": 0x80,
    ]

    public static let consumer: [String: Int] = [
        "play-pause": 0xCD, "next-track": 0xB5, "prev-track": 0xB6, "stop": 0xB7, "mute": 0xE2,
        "volume-up": 0xE9, "volume-down": 0xEA, "brightness-up": 0x6F, "brightness-down": 0x70,
        "calculator": 0x192, "browser": 0x196, "mail": 0x18A, "my-computer": 0x194,
    ]
    public static let consumerName: [Int: String] = Dictionary(consumer.map { ($0.value, display($0.key)) }, uniquingKeysWith: { a, _ in a })

    public static func display(_ s: String) -> String {
        if s.count == 1 { return s.uppercased() }
        let names = ["lctrl": "L Ctrl", "rctrl": "R Ctrl", "lshift": "L Shift", "rshift": "R Shift", "lalt": "L Alt", "ralt": "R Alt",
                     "lwin": "L Cmd/Win", "rwin": "R Cmd/Win", "pgup": "Page Up", "pgdn": "Page Down", "capslock": "Caps Lock"]
        if let n = names[s] { return n }
        let symbols = ["minus": "-", "equal": "=", "lbracket": "[", "rbracket": "]", "backslash": "\\", "semicolon": ";", "quote": "'",
                       "grave": "`", "comma": ",", "period": ".", "slash": "/"]
        if let n = symbols[s] { return n }
        return s.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Names that can be typed on the CLI or picked in the UI, with the entry they produce.
    public static func target(named raw: String) -> KeyEntry? {
        let n = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if n == "none" || n == "disabled" { return .disabled }
        if let m = modifiers[n] { return KeyEntry([0, UInt8(m), 0, 0]) }
        if let u = consumer[n] { return .consumer(u) }
        if let h = hid[n] { return .key(hid: h) }
        return nil
    }

    public static var allTargetNames: [String] {
        ["none"] + modifiers.keys.sorted() + consumer.keys.sorted() + hid.keys.sorted { (hid[$0]!, $0) < (hid[$1]!, $1) }
    }

    /// Turkish Q aliases for the physical key under each letter.
    public static let aliases = ["ğ": "lbracket", "ü": "rbracket", "ş": "semicolon", "ö": "comma", "ç": "period", "ı": "i"]

    /// Resolve a key name (or `#53`) to a matrix index.
    public static func index(of raw: String) -> Int? {
        var n = raw.lowercased().trimmingCharacters(in: .whitespaces)
        n = aliases[n] ?? n
        if let k = Layout.byName[n] { return k.index }
        if n.hasPrefix("#"), let i = Int(n.dropFirst()), (0..<Layout.matrixLength).contains(i) { return i }
        return nil
    }

    public static func entry(_ raw: [UInt8], _ index: Int) -> KeyEntry {
        KeyEntry(Array(raw[4 * index..<4 * index + 4]))
    }
    public static func setting(_ raw: [UInt8], _ index: Int, to e: KeyEntry) -> [UInt8] {
        var b = raw
        b.replaceSubrange(4 * index..<4 * index + 4, with: e.bytes)
        return b
    }
}
