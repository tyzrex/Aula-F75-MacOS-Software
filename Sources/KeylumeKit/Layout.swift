// Generated from the key layout in aula-f75-hub (MIT) / the official KB.ini.
// Edited by hand: indices 53 and 59 are Fn and R Ctrl, as read from this keyboard's own keymap (KB.ini agrees).
import Foundation

public struct KeyInfo: Sendable, Hashable, Identifiable {
    public let index: Int
    public let name: String
    public let label: String
    public let x1: Double, y1: Double, x2: Double, y2: Double
    public var id: Int { index }
    public var hasLED: Bool { x2 > x1 }
}

public enum Layout {
    public static let matrixLength = 126
    public static let keys: [KeyInfo] = [
        KeyInfo(index: 0, name: "esc", label: "Esc", x1: 30, y1: 30, x2: 55, y2: 57),
        KeyInfo(index: 12, name: "f1", label: "F1", x1: 107, y1: 30, x2: 132, y2: 57),
        KeyInfo(index: 18, name: "f2", label: "F2", x1: 144, y1: 30, x2: 169, y2: 57),
        KeyInfo(index: 24, name: "f3", label: "F3", x1: 183, y1: 30, x2: 208, y2: 57),
        KeyInfo(index: 30, name: "f4", label: "F4", x1: 222, y1: 30, x2: 247, y2: 57),
        KeyInfo(index: 36, name: "f5", label: "F5", x1: 269, y1: 30, x2: 294, y2: 57),
        KeyInfo(index: 42, name: "f6", label: "F6", x1: 305, y1: 30, x2: 330, y2: 57),
        KeyInfo(index: 48, name: "f7", label: "F7", x1: 343, y1: 30, x2: 368, y2: 57),
        KeyInfo(index: 54, name: "f8", label: "F8", x1: 388, y1: 30, x2: 413, y2: 57),
        KeyInfo(index: 60, name: "f9", label: "F9", x1: 439, y1: 30, x2: 464, y2: 57),
        KeyInfo(index: 66, name: "f10", label: "F10", x1: 477, y1: 30, x2: 502, y2: 57),
        KeyInfo(index: 72, name: "f11", label: "F11", x1: 516, y1: 30, x2: 541, y2: 57),
        KeyInfo(index: 78, name: "f12", label: "F12", x1: 555, y1: 30, x2: 580, y2: 57),
        KeyInfo(index: 1, name: "grave", label: "`", x1: 31, y1: 81, x2: 56, y2: 108),
        KeyInfo(index: 7, name: "1", label: "1", x1: 70, y1: 81, x2: 95, y2: 108),
        KeyInfo(index: 13, name: "2", label: "2", x1: 108, y1: 81, x2: 133, y2: 108),
        KeyInfo(index: 19, name: "3", label: "3", x1: 147, y1: 81, x2: 172, y2: 108),
        KeyInfo(index: 25, name: "4", label: "4", x1: 184, y1: 81, x2: 209, y2: 108),
        KeyInfo(index: 31, name: "5", label: "5", x1: 223, y1: 81, x2: 248, y2: 108),
        KeyInfo(index: 37, name: "6", label: "6", x1: 262, y1: 81, x2: 287, y2: 108),
        KeyInfo(index: 43, name: "7", label: "7", x1: 300, y1: 81, x2: 325, y2: 108),
        KeyInfo(index: 49, name: "8", label: "8", x1: 338, y1: 81, x2: 363, y2: 108),
        KeyInfo(index: 55, name: "9", label: "9", x1: 377, y1: 81, x2: 402, y2: 108),
        KeyInfo(index: 61, name: "0", label: "0", x1: 416, y1: 81, x2: 441, y2: 108),
        KeyInfo(index: 67, name: "minus", label: "-", x1: 453, y1: 81, x2: 478, y2: 108),
        KeyInfo(index: 73, name: "equal", label: "=", x1: 491, y1: 81, x2: 516, y2: 108),
        KeyInfo(index: 79, name: "backspace", label: "Backspace", x1: 531, y1: 81, x2: 591, y2: 108),
        KeyInfo(index: 85, name: "delete", label: "Del", x1: 604, y1: 81, x2: 629, y2: 108),
        KeyInfo(index: 2, name: "tab", label: "Tab", x1: 34, y1: 120, x2: 78, y2: 147),
        KeyInfo(index: 8, name: "q", label: "Q", x1: 89, y1: 119, x2: 114, y2: 146),
        KeyInfo(index: 14, name: "w", label: "W", x1: 127, y1: 119, x2: 152, y2: 146),
        KeyInfo(index: 20, name: "e", label: "E", x1: 165, y1: 119, x2: 190, y2: 146),
        KeyInfo(index: 26, name: "r", label: "R", x1: 204, y1: 119, x2: 229, y2: 146),
        KeyInfo(index: 32, name: "t", label: "T", x1: 242, y1: 119, x2: 267, y2: 146),
        KeyInfo(index: 38, name: "y", label: "Y", x1: 280, y1: 119, x2: 305, y2: 146),
        KeyInfo(index: 44, name: "u", label: "U", x1: 318, y1: 119, x2: 343, y2: 146),
        KeyInfo(index: 50, name: "i", label: "I", x1: 356, y1: 119, x2: 381, y2: 146),
        KeyInfo(index: 56, name: "o", label: "O", x1: 395, y1: 119, x2: 420, y2: 146),
        KeyInfo(index: 62, name: "p", label: "P", x1: 433, y1: 119, x2: 458, y2: 146),
        KeyInfo(index: 68, name: "lbracket", label: "[", x1: 471, y1: 119, x2: 496, y2: 146),
        KeyInfo(index: 74, name: "rbracket", label: "]", x1: 509, y1: 119, x2: 534, y2: 146),
        KeyInfo(index: 80, name: "backslash", label: "\\", x1: 549, y1: 119, x2: 593, y2: 146),
        KeyInfo(index: 86, name: "pgup", label: "PgUp", x1: 605, y1: 120, x2: 630, y2: 147),
        KeyInfo(index: 3, name: "capslock", label: "Caps", x1: 33, y1: 158, x2: 85, y2: 185),
        KeyInfo(index: 9, name: "a", label: "A", x1: 98, y1: 158, x2: 123, y2: 185),
        KeyInfo(index: 15, name: "s", label: "S", x1: 136, y1: 158, x2: 161, y2: 185),
        KeyInfo(index: 21, name: "d", label: "D", x1: 174, y1: 158, x2: 199, y2: 185),
        KeyInfo(index: 27, name: "f", label: "F", x1: 213, y1: 158, x2: 238, y2: 185),
        KeyInfo(index: 33, name: "g", label: "G", x1: 252, y1: 158, x2: 277, y2: 185),
        KeyInfo(index: 39, name: "h", label: "H", x1: 290, y1: 158, x2: 315, y2: 185),
        KeyInfo(index: 45, name: "j", label: "J", x1: 327, y1: 158, x2: 352, y2: 185),
        KeyInfo(index: 51, name: "k", label: "K", x1: 366, y1: 158, x2: 391, y2: 185),
        KeyInfo(index: 57, name: "l", label: "L", x1: 405, y1: 158, x2: 430, y2: 185),
        KeyInfo(index: 63, name: "semicolon", label: ";", x1: 443, y1: 158, x2: 468, y2: 185),
        KeyInfo(index: 69, name: "quote", label: "'", x1: 481, y1: 158, x2: 506, y2: 185),
        KeyInfo(index: 81, name: "enter", label: "Enter", x1: 521, y1: 158, x2: 591, y2: 185),
        KeyInfo(index: 87, name: "pgdn", label: "PgDn", x1: 604, y1: 159, x2: 629, y2: 186),
        KeyInfo(index: 4, name: "lshift", label: "Shift", x1: 33, y1: 195, x2: 105, y2: 222),
        KeyInfo(index: 10, name: "z", label: "Z", x1: 116, y1: 195, x2: 141, y2: 222),
        KeyInfo(index: 16, name: "x", label: "X", x1: 155, y1: 195, x2: 180, y2: 222),
        KeyInfo(index: 22, name: "c", label: "C", x1: 193, y1: 195, x2: 218, y2: 222),
        KeyInfo(index: 28, name: "v", label: "V", x1: 232, y1: 195, x2: 257, y2: 222),
        KeyInfo(index: 34, name: "b", label: "B", x1: 270, y1: 195, x2: 295, y2: 222),
        KeyInfo(index: 40, name: "n", label: "N", x1: 309, y1: 195, x2: 334, y2: 222),
        KeyInfo(index: 46, name: "m", label: "M", x1: 347, y1: 195, x2: 372, y2: 222),
        KeyInfo(index: 52, name: "comma", label: ",", x1: 384, y1: 195, x2: 409, y2: 222),
        KeyInfo(index: 58, name: "period", label: ".", x1: 424, y1: 195, x2: 449, y2: 222),
        KeyInfo(index: 64, name: "slash", label: "/", x1: 463, y1: 195, x2: 488, y2: 222),
        KeyInfo(index: 70, name: "rshift", label: "Shift", x1: 502, y1: 195, x2: 558, y2: 222),
        KeyInfo(index: 82, name: "up", label: "↑", x1: 567, y1: 195, x2: 592, y2: 222),
        KeyInfo(index: 88, name: "end", label: "End", x1: 605, y1: 195, x2: 630, y2: 222),
        KeyInfo(index: 5, name: "lctrl", label: "Ctrl", x1: 34, y1: 234, x2: 69, y2: 261),
        KeyInfo(index: 11, name: "lwin", label: "Win", x1: 79, y1: 234, x2: 114, y2: 261),
        KeyInfo(index: 17, name: "lalt", label: "Alt", x1: 122, y1: 234, x2: 157, y2: 261),
        KeyInfo(index: 35, name: "space", label: "Space", x1: 174, y1: 234, x2: 400, y2: 261),
        KeyInfo(index: 53, name: "fn", label: "Fn", x1: 414, y1: 234, x2: 449, y2: 261),
        KeyInfo(index: 59, name: "rctrl", label: "RCtrl", x1: 463, y1: 234, x2: 497, y2: 261),
        KeyInfo(index: 77, name: "left", label: "←", x1: 529, y1: 234, x2: 554, y2: 261),
        KeyInfo(index: 83, name: "down", label: "↓", x1: 568, y1: 234, x2: 593, y2: 261),
        KeyInfo(index: 89, name: "right", label: "→", x1: 605, y1: 234, x2: 630, y2: 261),
        KeyInfo(index: 84, name: "knob", label: "Knob", x1: 0, y1: 0, x2: 0, y2: 0),
    ]
    public static let byName: [String: KeyInfo] = Dictionary(uniqueKeysWithValues: keys.map { ($0.name, $0) })
    public static let byIndex: [Int: KeyInfo] = Dictionary(uniqueKeysWithValues: keys.map { ($0.index, $0) })
}
