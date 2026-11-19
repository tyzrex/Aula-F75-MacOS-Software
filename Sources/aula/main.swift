import Foundation
import AulaKit

let usage = """
aula — AULA F75 control over the USB cable

  aula devices                          list AULA keyboards macOS can see
  aula info                             lighting, side light, knob, OS mode, sleep, firmware
  aula effects                          list lighting effects
  aula effect <name> [-b 0-9] [-s 0-4] [-c color]
  aula colors | themes                  list color names / per-key themes
  aula theme <name>                     paint a per-key theme (switches to the custom effect)
  aula fill <#rrggbb>                   one color on every key
  aula key-color <key> <#rrggbb>        paint one key (custom effect)
  aula palette <effect> <color> <#rrggbb> | palette-reset <effect>
  aula live <animation> [seconds] [#rrggbb]   stream an animation (cable only); `aula live list`
  aula keymap [--fn] [--mac]            show the keymap
  aula remap <key> <target> [--fn] [--mac]    e.g. remap capslock lctrl | remap f5 mute | remap #53 none
  aula side-light off|fill|breathing|static
  aula knob media|lighting
  aula os windows|android|mac
  aula win-lock on|off
  aula sleep <minutes>                  30 s steps, max 20, never is refused
  aula battery
  aula backup [file] | restore <file> [--keymap] | backups

options: --demo   use a simulated keyboard (no hardware needed)

"""

var args = Array(CommandLine.arguments.dropFirst())
let demo = args.contains("--demo")
args.removeAll { $0 == "--demo" }
let flagFn = args.contains("--fn"), flagMac = args.contains("--mac"), flagKeymap = args.contains("--keymap")
args.removeAll { ["--fn", "--mac", "--keymap"].contains($0) }

func fail(_ msg: String) -> Never { FileHandle.standardError.write(Data(("aula: " + msg + "\n").utf8)); exit(1) }

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...i + 1); return v
}

func connect() -> AulaKeyboard {
    if demo { return AulaKeyboard.demo().0 }
    do { return try AulaKeyboard.connect() } catch { fail(error.localizedDescription) }
}

func rgb(_ s: String) -> RGB {
    guard let c = RGB(hex: s) else { fail("color must be 6 hex digits like #ff8800: \(s)") }
    return c
}
func colorIndex(_ s: String) -> Int {
    if let i = Names.colors.firstIndex(of: s.lowercased()) { return i }
    if let i = Int(s), (0...7).contains(i) { return i }
    fail("color must be one of \(Names.colors.joined(separator: ", ")) or 0-7")
}
func pick(_ list: [String], _ s: String?, _ what: String) -> Int {
    guard let s, let i = list.firstIndex(of: s.lowercased()) else { fail("\(what) must be one of: \(list.joined(separator: ", "))") }
    return i
}

func run() throws {
    guard let cmd = args.first else { print(usage); return }
    args.removeFirst()
    switch cmd {
    case "help", "-h", "--help": print(usage)

    case "devices":
        if demo { print("AULA F75 (demo)  simulated"); return }
        let all = HIDDiscovery.enumerate()
        if all.isEmpty { print("No AULA keyboard found.") }
        for c in all {
            print(String(format: "%@  %04x:%04x  %@  usagePage 0x%04x  maxFeature %d", c.info.name, c.info.vendorID, c.info.productID, c.info.transport, c.usagePage, c.maxFeature))
        }

    case "effects":
        for e in Effects.all { print(String(format: "%3d  %-14@ speed:%@ color:%@", e.hw, e.name as NSString, e.hasSpeed ? "yes" : "no ", e.hasColor ? "yes" : "no")) }
    case "colors": print(Names.colors.enumerated().map { "\($0.offset) \($0.element)" }.joined(separator: "\n"))
    case "themes": for t in Themes.all { print("\(t.name.padding(toLength: 14, withPad: " ", startingAt: 0)) \(t.summary)") }
    case "live" where args.first == "list": for a in LiveAnimation.allCases { print(a.rawValue) }

    case "info":
        let kb = connect()
        let cfg = try kb.readLED()
        print("device:     \(kb.info.name) (\(kb.info.transport))")
        if let i = try? kb.readInfo() { print("firmware:   uuid \(i.uuid) version \(i.version)") }
        let e = Effects.byHW(cfg.effect)
        print("effect:     \(e?.name ?? "unknown (\(cfg.effect))")")
        if let s = cfg.slot(cfg.effect), let e, e.hw != Effects.customHW {
            print("            brightness \(s.brightness)/9, speed \(s.speed)/4, color \(Names.colors[min(s.color, 7)])")
        }
        print("side light: \(Names.sideModes[min(cfg.sideMode, 3)])")
        print("knob:       \(Names.knobModes[min(cfg.knobMode, 1)])")
        print("os mode:    \(Names.osModes[min(cfg.osMode, 2)])")
        print("win lock:   \(cfg.winLock ? "on" : "off")")
        print("sleep:      \(Names.sleepText(cfg.sleep))")

    case "effect":
        guard let name = args.first, let e = Effects.named(name) else { fail("unknown effect; see `aula effects`") }
        args.removeFirst()
        let b = option("-b").flatMap(Int.init), s = option("-s").flatMap(Int.init), c = option("-c").map(colorIndex)
        try connect().setEffect(e.hw, brightness: b, speed: s, color: c)
        print("effect → \(e.name)")

    case "theme":
        guard let n = args.first, let t = Themes.named(n) else { fail("unknown theme; see `aula themes`") }
        let kb = connect()
        try kb.writeCustom(Custom.encode(t.render()))
        try kb.setEffect(Effects.customHW)
        print("theme → \(t.name)")

    case "fill":
        guard let h = args.first else { fail("usage: aula fill #rrggbb") }
        let kb = connect()
        try kb.writeCustom(Custom.encode(Themes.solid(rgb(h))))
        try kb.setEffect(Effects.customHW)

    case "key-color":
        guard args.count >= 2, let idx = Keymap.index(of: args[0]) else { fail("usage: aula key-color <key> <#rrggbb>") }
        let kb = connect()
        var colors = Custom.decode(try kb.readCustom())
        colors[idx] = rgb(args[1])
        try kb.writeCustom(Custom.encode(colors))
        try kb.setEffect(Effects.customHW)

    case "palette":
        guard args.count == 3, let e = Effects.named(args[0]) else { fail("usage: aula palette <effect> <color 0-6> #rrggbb") }
        let kb = connect()
        try kb.writePalette(try Palette.setting(try kb.readPalette(), hw: e.hw, color: colorIndex(args[1]), to: rgb(args[2])))
    case "palette-reset":
        guard let n = args.first, let e = Effects.named(n) else { fail("usage: aula palette-reset <effect>") }
        let kb = connect()
        try kb.writePalette(try Palette.reset(try kb.readPalette(), hw: e.hw))

    case "live":
        guard let name = args.first, let anim = LiveAnimation(rawValue: name) else { fail("unknown animation; see `aula live list`") }
        let secs = args.dropFirst().first.flatMap(Double.init) ?? 10
        let color = args.dropFirst(2).first.map(rgb) ?? RGB(0, 160, 255)
        let kb = connect()
        let start = Date()
        print("streaming \(anim.title) for \(Int(secs)) s…")
        while Date().timeIntervalSince(start) < secs {
            try kb.sendLive(anim.frame(t: Date().timeIntervalSince(start), color: color, theme: nil))
        }

    case "keymap":
        let kb = connect()
        let km = try kb.readKeymap(layer: flagFn ? 1 : 0, system: flagMac ? 1 : 0)
        for k in Layout.keys.sorted(by: { $0.index < $1.index }) {
            print(String(format: "%3d  %-12@ %@", k.index, k.name as NSString, Keymap.entry(km, k.index).description))
        }

    case "remap":
        guard args.count == 2, let idx = Keymap.index(of: args[0]) else { fail("usage: aula remap <key> <target> [--fn] [--mac]") }
        guard let target = Keymap.target(named: args[1]) else { fail("unknown target '\(args[1])'. Try a letter, f5, lctrl, mute, volume-up, none …") }
        let kb = connect()
        let layer = flagFn ? 1 : 0, system = flagMac ? 1 : 0
        let backup = try Backup.capture(from: kb).save(name: "before-remap")
        print("backup saved: \(backup.path)")
        let km = try kb.readKeymap(layer: layer, system: system)
        try kb.writeKeymap(Keymap.setting(km, idx, to: target), layer: layer, system: system)
        print("\(args[0]) → \(target.description)  (\(flagFn ? "Fn" : "base") layer, \(flagMac ? "Mac" : "Windows") table)")

    case "side-light": try connect().updateLED { $0.sideMode = pick(Names.sideModes, args.first, "mode") }
    case "knob": try connect().updateLED { $0.knobMode = pick(Names.knobModes, args.first, "mode") }
    case "os": try connect().updateLED { $0.osMode = pick(Names.osModes, args.first, "mode") }
    case "win-lock": try connect().updateLED { $0.winLock = args.first == "on" }
    case "sleep":
        guard let m = args.first.flatMap(Double.init) else { fail("usage: aula sleep <minutes>") }
        try connect().updateLED { try $0.setSleep(Int(m * 60)) }

    case "battery":
        let b = try connect().readBattery()
        print("\(b.level)%\(b.charging ? " charging" : "")\(b.full ? " full" : "")")

    case "backup":
        let b = try Backup.capture(from: connect())
        let url = try b.save(to: args.first.map { URL(fileURLWithPath: $0) })
        print("saved \(url.path)")
    case "restore":
        guard let f = args.first else { fail("usage: aula restore <file> [--keymap]") }
        try Backup.load(URL(fileURLWithPath: f)).restore(to: connect(), includeKeymap: flagKeymap)
        print("restored")
    case "backups": for u in Backup.list() { print(u.path) }

    default: fail("unknown command '\(cmd)'. Run `aula help`.")
    }
}

do { try run() } catch { fail(error.localizedDescription) }
