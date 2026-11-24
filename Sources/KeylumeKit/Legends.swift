import Foundation

/// How key legends are written: Windows names or Mac symbols (⌘ ⌥ ⌃ ⇧).
public enum Flavor: String, CaseIterable, Sendable, Identifiable {
    case windows, mac
    public var id: String { rawValue }
    public var title: String { self == .mac ? "Mac" : "Windows" }

    /// The OS mode the keyboard is in (LED byte 27: 0 Windows, 1 Android, 2 Mac).
    public init(osMode: Int) { self = osMode == 2 ? .mac : .windows }
    /// The key table the keyboard uses in that mode (0 Windows table, 1 Mac table).
    public var keymapSystem: Int { self == .mac ? 1 : 0 }
}

/// What is printed on a keycap: a main legend and an optional small caption under it.
public struct Legend: Equatable, Sendable {
    public var main: String
    public var caption: String?
    public init(_ main: String, _ caption: String? = nil) { self.main = main; self.caption = caption }
    public var isEmpty: Bool { main.isEmpty }
}

public enum Legends {
    // MARK: physical keycaps

    /// The legend printed on a key of the F75, written for the given OS mode.
    public static func physical(_ k: KeyInfo, flavor: Flavor) -> Legend {
        switch flavor {
        case .windows:
            switch k.name {
            case "rctrl": return Legend("Ctrl")
            case "lwin": return Legend("Win")
            case "backspace": return Legend("Bksp")
            default: return Legend(k.label)
            }
        case .mac:
            switch k.name {
            case "lwin": return Legend("⌘", "cmd")
            case "lalt": return Legend("⌥", "opt")
            case "lctrl", "rctrl": return Legend("⌃", "ctrl")
            case "lshift", "rshift": return Legend("⇧", "shift")
            case "capslock": return Legend("⇪", "caps")
            case "tab": return Legend("⇥", "tab")
            case "backspace": return Legend("⌫", "delete")
            case "enter": return Legend("⏎", "return")
            case "delete": return Legend("⌦", "del")
            case "esc": return Legend("esc")
            case "pgup": return Legend("⇞", "pg up")
            case "pgdn": return Legend("⇟", "pg dn")
            case "end": return Legend("↘", "end")
            case "space": return Legend("")
            default: return Legend(k.label)
            }
        }
    }

    // MARK: what a keymap entry does

    private static let modifierOrder: [(name: String, bit: Int, windows: String, mac: String)] = [
        ("ctrl", 0x01, "Ctrl", "⌃"), ("shift", 0x02, "Shift", "⇧"), ("alt", 0x04, "Alt", "⌥"), ("win", 0x08, "Win", "⌘"),
        ("ctrl", 0x10, "Ctrl", "⌃"), ("shift", 0x20, "Shift", "⇧"), ("alt", 0x40, "Alt", "⌥"), ("win", 0x80, "Win", "⌘"),
    ]

    private static let keyNames: [String: (windows: String, mac: String)] = [
        "enter": ("Enter", "⏎"), "esc": ("Esc", "esc"), "backspace": ("Bksp", "⌫"), "tab": ("Tab", "⇥"), "space": ("Space", "Space"),
        "capslock": ("Caps", "⇪"), "delete": ("Del", "⌦"), "insert": ("Ins", "Ins"), "home": ("Home", "↖"), "end": ("End", "↘"),
        "pgup": ("PgUp", "⇞"), "pgdn": ("PgDn", "⇟"), "up": ("↑", "↑"), "down": ("↓", "↓"), "left": ("←", "←"), "right": ("→", "→"),
        "printscreen": ("PrtSc", "PrtSc"), "scrolllock": ("ScrLk", "ScrLk"), "pause": ("Pause", "Pause"), "menu": ("Menu", "Menu"),
        "minus": ("-", "-"), "equal": ("=", "="), "lbracket": ("[", "["), "rbracket": ("]", "]"), "backslash": ("\\", "\\"),
        "semicolon": (";", ";"), "quote": ("'", "'"), "grave": ("`", "`"), "comma": (",", ","), "period": (".", "."), "slash": ("/", "/"),
    ]

    private static let consumerLabels: [Int: String] = [
        0xCD: "⏯", 0xB5: "⏭", 0xB6: "⏮", 0xB7: "⏹", 0xE2: "Mute", 0xE9: "Vol +", 0xEA: "Vol −",
        0x6F: "Bri +", 0x70: "Bri −", 0x192: "Calc", 0x196: "Web", 0x18A: "Mail", 0x194: "PC", 0x223: "Home",
    ]

    /// Fn-layer functions built into the firmware (type 7 entries, by their last byte).
    private static let specials: [UInt8: Legend] = [
        0x08: Legend("2.4G"), 0x05: Legend("BT 1"), 0x06: Legend("BT 2"), 0x07: Legend("BT 3"),
        0x18: Legend("Win", "mode"), 0x1A: Legend("Mac", "mode"), 0x19: Legend("Android", "mode"),
        0x11: Legend("Battery"), 0x01: Legend("Win lock"), 0x04: Legend("Reset"), 0x0A: Legend("?"),
    ]

    public static func entry(_ e: KeyEntry, flavor: Flavor) -> Legend {
        let b = e.bytes
        if e.isEmpty { return Legend("—") }
        switch b[0] {
        case 0:
            let mods = modifierOrder.filter { Int(b[1]) & $0.bit != 0 }.map { flavor == .mac ? $0.mac : $0.windows }
            var key = ""
            if b[3] != 0 {
                if let name = Keymap.hidName[Int(b[3])] {
                    key = keyNames[name].map { flavor == .mac ? $0.mac : $0.windows } ?? (name.count == 1 ? name.uppercased() : name.uppercased())
                } else { key = String(format: "%02X", b[3]) }
            }
            if mods.isEmpty { return Legend(key) }
            if key.isEmpty { return Legend(mods.joined(separator: flavor == .mac ? "" : "+")) }
            return Legend(mods.joined(separator: flavor == .mac ? "" : "+") + (flavor == .mac ? "" : "+") + key)
        case 2:
            let u = Int(b[2]) << 8 | Int(b[3])
            return Legend(consumerLabels[u] ?? String(format: "%X", u))
        case 3: return Legend("Macro", "\(b[3])")
        case 7: return specials[b[3]] ?? Legend("Fn", String(format: "%02X", b[3]))
        case 8:
            switch b[1] {
            case 0: return Legend("Effect", "next")
            case 1: return Legend("Side", "light")
            case 2: return Legend("Color", "next")
            case 3: return Legend(b[2] == 1 ? "Bright +" : "Bright −")
            case 4: return Legend(b[2] == 1 ? "Speed +" : "Speed −")
            default: return Legend("Fn", e.hex)
            }
        case 0x0D: return Legend("Fn")
        default: return Legend("?", e.hex)
        }
    }
}
