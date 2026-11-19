import Foundation
import AulaKit

// Minimal test runner (no XCTest needed). Exit code 1 if anything fails.
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0
func expect(_ cond: @autoclosure () throws -> Bool, _ msg: String = "", line: Int = #line) rethrows {
    checks += 1
    if !(try cond()) { failures += 1; print("  ✗ line \(line) \(msg)") }
}
func throwsError(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
func test(_ name: String, _ body: () throws -> Void) {
    let before = failures
    do { try body() } catch { failures += 1; print("  ✗ threw \(error)") }
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

test("request framing") {
    let r = Wire.request(cmd: 0x84, sub: 0, length: 128)
    expect(r.count == 520)
    expect(Array(r.prefix(8)) == [6, 0x84, 0, 0, 1, 0, 128, 0])
    expect(Array(Wire.request(cmd: 0x83, sub: 1, length: 504).prefix(8)) == [6, 0x83, 1, 0, 1, 0, 0xF8, 1])
}
test("write report") {
    let r = try Wire.writeReport(cmd: Wire.writeCustom, data: [1, 2, 3])
    expect(Array(r.prefix(11)) == [6, 6, 0, 0, 1, 0, 3, 0, 1, 2, 3])
    expect(throwsError { _ = try Wire.writeReport(cmd: 4, data: [UInt8](repeating: 0, count: 513)) })
    let k = try Wire.writeReport(cmd: 3, sub: 5, data: [UInt8](repeating: 1, count: 512), declaredLength: 504)
    expect(Array(k.prefix(8)) == [6, 3, 5, 0, 1, 0, 0xF8, 1])
}
test("keymap sub byte matches the official app") {
    expect(Wire.keymapSub(layer: 0, system: 0) == 0)
    expect(Wire.keymapSub(layer: 1, system: 0) == 1)
    expect(Wire.keymapSub(layer: 1, system: 1) == 5)
}
test("reply matching") {
    var rep = Wire.request(cmd: 0x84, sub: 0, length: 4); rep[8] = 9
    expect(Wire.reply(rep, cmd: 0x84, sub: 0, length: 4) == [9, 0, 0, 0])
    expect(Wire.reply(rep, cmd: 0x83, sub: 0, length: 4) == nil)
    expect(Wire.reply(rep, cmd: 0x84, sub: 1, length: 4) == nil)
}
test("live report") {
    let r = Wire.liveReport(colors: [0: RGB(1, 2, 3), 121: RGB(9, 8, 7), 122: RGB(5, 5, 5)])
    expect(Array(r.prefix(8)) == [6, 8, 0, 0, 1, 0, 0x7A, 1])
    expect(Array(r[8..<11]) == [1, 2, 3])
    expect(Array(r[8 + 363..<8 + 366]) == [9, 8, 7])
    expect(r[8 + 366] == 0)
}
test("LED slots") {
    let (kb, _) = AulaKeyboard.demo()
    var cfg = try kb.readLED()
    expect(cfg.effect == 1)
    try cfg.setSlot(2, EffectSlot(brightness: 7, speed: 3, color: 5))
    expect(cfg.slot(2) == EffectSlot(brightness: 7, speed: 3, color: 5))
    expect(cfg.raw[LEDConfig.slotsOffset + 2] == 7 && cfg.raw[LEDConfig.slotsOffset + 3] == 0x35)
    expect(throwsError { try cfg.setSlot(2, EffectSlot(brightness: 10, speed: 0, color: 0)) })
    expect(throwsError { try cfg.setSleep(45) })
    expect(throwsError { try cfg.setSleep(1230) })
}
test("palette helpers") {
    var raw = [UInt8](repeating: 0, count: Wire.paletteLength)
    raw = try Palette.setting(raw, hw: 2, color: 3, to: RGB(10, 20, 30))
    expect(Palette.color(raw, hw: 2, color: 3) == RGB(10, 20, 30))
    expect(Array(raw[2 * 21 + 9..<2 * 21 + 12]) == [10, 20, 30])
    expect(throwsError { _ = try Palette.setting(raw, hw: 23, color: 0, to: .black) })
    raw = try Palette.reset(raw, hw: 2)
    expect(Palette.color(raw, hw: 2, color: 3) == RGB(255, 255, 0))
}
test("per-key planar encoding") {
    let raw = Custom.encode([5: RGB(1, 2, 3)])
    expect(raw.count == 378)
    expect([raw[5], raw[131], raw[257]] == [1, 2, 3])
    expect(Custom.decode(raw)[5] == RGB(1, 2, 3))
}
test("keymap entries") {
    expect(KeyEntry.key(hid: 4, modifiers: 2).bytes == [0, 2, 0, 4])
    expect(KeyEntry.consumer(0xE9).bytes == [2, 0, 0, 0xE9])
    expect(Keymap.target(named: "mute") == .consumer(0xE2))
    expect(Keymap.target(named: "a") == .key(hid: 4))
    expect(Keymap.target(named: "lshift")?.bytes == [0, 2, 0, 0])
    expect(Keymap.index(of: "esc") == 0)
    expect(Keymap.index(of: "#53") == 53)
    expect(Keymap.index(of: "nonsense") == nil)
    expect(KeyEntry.key(hid: 4).description == "A")
}
test("layout and themes") {
    expect(Layout.keys.count == Set(Layout.keys.map { $0.index }).count)
    expect(Layout.keys.allSatisfy { $0.index < Layout.matrixLength })
    for t in Themes.all {
        expect(t.render().count > 70, t.name)
        expect(t.accents.keys.allSatisfy { Keymap.index(of: $0) != nil }, "\(t.name) accents")
    }
}
test("animations") {
    let (kb, _) = AulaKeyboard.demo()
    var cfg = try kb.readLED()
    for e in Effects.all where e.hw != Effects.customHW {
        try cfg.setSlot(e.hw, EffectSlot(brightness: 9, speed: 2, color: 1))
        cfg.effect = e.hw
        expect((EffectPreview.frame(cfg, t: 3.3)?.count ?? 0) > 70, e.name)
    }
    for a in LiveAnimation.allCases { expect(a.frame(t: 1.7, color: RGB(255, 0, 0), theme: nil).count > 70, a.rawValue) }
}
test("effect write round trip") {
    let (kb, ch) = AulaKeyboard.demo()
    try kb.setEffect(6, brightness: 9, speed: 4, color: 2)
    expect(ch.led[LEDConfig.effectOffset] == 6 && ch.led[LEDConfig.effectHighOffset] == 0 && ch.led[LEDConfig.slotsOffset + 10] == 9 && ch.led[LEDConfig.slotsOffset + 11] == 0x42)
}
test("effect is 16-bit: high byte is cleared / set (official Hub)") {
    let (kb, ch) = AulaKeyboard.demo()
    ch.led[LEDConfig.effectHighOffset] = 1; ch.led[LEDConfig.effectOffset] = 0x12   // this keyboard's stock state (mode 274)
    try kb.setEffect(2, brightness: 7)
    expect(ch.led[LEDConfig.effectHighOffset] == 0 && ch.led[LEDConfig.effectOffset] == 2, "normal effect clears byte 9")
    try kb.setEffect(Effects.customHW)
    expect(ch.led[LEDConfig.effectHighOffset] == 1 && ch.led[LEDConfig.effectOffset] == 0x15, "custom = 277 = 0x0115")
    try expect(kb.readLED().effect == 277)
}
test("unchanged LED write sends nothing") {
    let (kb, ch) = AulaKeyboard.demo()
    try kb.writeLED(try kb.readLED())
    expect(!ch.log.contains(Wire.writeLED))
}
test("refuses unknown LED bytes") {
    let (kb, ch) = AulaKeyboard.demo()
    var raw = try kb.readLED().raw; raw[40] = 0x77
    expect(throwsError { try kb.writeLED(try LEDConfig(raw: raw)) })
    expect(!ch.log.contains(Wire.writeLED))
}
test("refuses sleep never") {
    let (kb, ch) = AulaKeyboard.demo()
    var raw = try kb.readLED().raw; raw[LEDConfig.sleepOffset] = 0
    expect(throwsError { try kb.writeLED(try LEDConfig(raw: raw)) })
    expect(!ch.log.contains(Wire.writeLED))
}
test("detects a dropped write") {
    let (kb, ch) = AulaKeyboard.demo()
    ch.dropWrites = true
    do { try kb.setEffect(2); expect(false, "no error") } catch AulaError.verifyFailed { } catch { expect(false, "\(error)") }
}
test("palette write keeps tail and re-applies LED") {
    let (kb, ch) = AulaKeyboard.demo()
    let tail = Array(ch.palettePage[490...])
    var p = try kb.readPalette()
    p = try Palette.setting(p, hw: 1, color: 0, to: RGB(1, 2, 3))
    try kb.writePalette(p)
    expect(Palette.color(Array(ch.palettePage.prefix(490)), hw: 1, color: 0) == RGB(1, 2, 3))
    expect(Array(ch.palettePage[490...]) == tail)
    expect(ch.log.filter { $0 == Wire.writePalette || $0 == Wire.writeLED } == [Wire.writePalette, Wire.writeLED])
}
test("per-key write") {
    let (kb, ch) = AulaKeyboard.demo()
    try kb.writeCustom(Custom.encode(Themes.solid(RGB(9, 9, 9))))
    expect(Custom.decode(ch.custom)[0] == RGB(9, 9, 9))
    expect(throwsError { try kb.writeCustom([1, 2, 3]) })
}
test("keymap write (official layout)") {
    let (kb, ch) = AulaKeyboard.demo()
    var km = try kb.readKeymap()
    km = Keymap.setting(km, 0, to: .key(hid: 0x05))
    try kb.writeKeymap(km)
    try expect(Keymap.entry(try kb.readKeymap(), 0) == .key(hid: 0x05))
    expect(Array(ch.keymaps[0][504..<512]) == [0, 0, 0, 0, 0, 0, 0x5A, 0xA5], "trailer")
    expect(ch.keymaps[4][3] != 0x05, "Mac table untouched")
    try kb.writeKeymap(km, layer: 1, system: 1)
    expect(Keymap.entry(ch.keymaps[5], 0) == .key(hid: 0x05), "sub = 5 for Fn/Mac")
}
test("device info and battery") {
    let (kb, _) = AulaKeyboard.demo()
    try expect(kb.readInfo().uuid == "0x0300000000cd")
    try expect(kb.readBattery() == AulaKeyboard.Battery(level: 80, charging: true, full: false))
}
test("live frame header") {
    let (kb, ch) = AulaKeyboard.demo()
    try kb.sendLive([3: RGB(1, 1, 1)])
    expect(Array(ch.liveFrames[0].prefix(8)) == Wire.liveHeader)
}
test("never sends forbidden commands") {
    let (kb, ch) = AulaKeyboard.demo()
    _ = try Backup.capture(from: kb)
    try kb.setEffect(3)
    expect(Set(ch.log).isDisjoint(with: Wire.forbidden))
}
test("backup / restore") {
    let (kb, ch) = AulaKeyboard.demo()
    let b = try Backup.capture(from: kb)
    try kb.writeCustom(Custom.encode(Themes.solid(RGB(7, 7, 7))))
    try kb.setEffect(13)
    try b.restore(to: kb)
    expect(Custom.decode(ch.custom)[0] == RGB(0, 0, 0))
    expect(ch.led[LEDConfig.effectOffset] == 1)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("aula-test-backup.json")
    try b.save(to: url)
    try expect(Backup.load(url).led == b.led)
}

test("radio packets: framing and checksum") {
    let p = Radio.packet(cmd: 0x44, total: 3, index: 1, sub: 2, chunk: [1, 2, 3])
    expect(p.count == 20 && p[0] == 0x13 && p[4] == 0x23 && p[5] == 1)
    expect(Radio.parse(p) == Radio.Reply(cmd: 0x44, total: 3, index: 1, error: false, data: [1, 2, 3]))
    var bad = p; bad[7] ^= 1
    expect(Radio.parse(bad) == nil, "bad checksum")
    expect(Radio.readRequest(cmd: 0x04, sub: 1)[1] == 0x44)
    expect(Radio.splitPackets(cmd: 0x01, sub: 0, data: [UInt8](repeating: 7, count: 30)).count == 3)
}
test("radio: reads match the keyboard") {
    let (kb, ch) = AulaKeyboard.demoRadio()
    try expect(kb.readLED().raw == ch.board.led)
    try expect(kb.readPalette() == Array(ch.board.palettePage.prefix(Wire.paletteLength)))
    try expect(kb.readCustom() == ch.board.custom)
    try expect(kb.readKeymap(layer: 1) == Array(ch.board.keymaps[1].prefix(Wire.keymapLength)))
    expect(throwsError { try kb.readKeymap(layer: 0, system: 1) }, "Mac table isn't exposed")
    try expect(kb.readBattery().level == 100)
    expect(ch.unexpected.isEmpty)
}
test("radio: Bluetooth packet loss is retried") {
    let (kb, ch) = AulaKeyboard.demoRadio(connection: .bluetooth)
    ch.lossyAttempts = 3
    try expect(kb.readLED().raw == ch.board.led)
    expect(ch.requests.count >= 2, "had to ask again")
}
test("radio: Bluetooth only reads small blocks") {
    let (kb, ch) = AulaKeyboard.demoRadio(connection: .bluetooth)
    try expect(kb.readLED().raw == ch.board.led)
    try expect(kb.readBattery().level == 100)
    expect(throwsError { try kb.readKeymap() } && throwsError { try kb.readPalette() } && throwsError { try kb.readCustom() })
    expect(throwsError { try Backup.capture(from: kb) }, "a full backup needs the dongle or cable")
}
test("radio: settings are never written") {
    let (kb, ch) = AulaKeyboard.demoRadio()
    expect(throwsError { try kb.setEffect(3) })
    expect(throwsError { try kb.writeCustom(Custom.encode(Themes.solid(RGB(9, 9, 9)))) })
    expect(throwsError { try kb.writeKeymap(try kb.readKeymap()) })
    expect(throwsError { try kb.writePalette(try kb.readPalette()) })
    expect(ch.unexpected.isEmpty && ch.board.led == MockChannel().led)
    expect(Set(ch.requests).isSubset(of: Set(Radio.readable.map { $0 | Radio.readFlag })), "only reads sent")
}
test("radio: live frames fit and use the live command") {
    var colors: [Int: RGB] = [:]
    for i in 0..<82 { colors[i] = RGB(i * 3, 255 - i * 3, (i * 37) % 256) }
    let groups = Radio.liveGroups(colors)
    expect(groups.count <= Radio.liveMax, "frame within 200 bytes")
    var lit = 0, i = 0
    while i < groups.count { let n = Int(groups[i + 3]); lit += n; i += 4 + n }
    expect(i == groups.count && lit == 82, "every lit key listed once")
    let (kb, ch) = AulaKeyboard.demoRadio()
    try kb.sendLive(colors)
    expect(!ch.livePackets.isEmpty && ch.livePackets.allSatisfy { $0[1] == 0x88 && Radio.parse($0) != nil })
    let (bt, _) = AulaKeyboard.demoRadio(connection: .bluetooth)
    expect(throwsError { try bt.sendLive(colors) }, "no live over Bluetooth")
}
test("radio: backup works without the Mac table") {
    let (kb, ch) = AulaKeyboard.demoRadio()
    let b = try Backup.capture(from: kb)
    expect(b.keymapBaseMac == nil && b.led == Backup.hex(ch.board.led))
    expect(throwsError { try b.restore(to: kb) }, "restoring needs the cable")
}
test("connection kinds") {
    let wired = DeviceInfo(name: "x", vendorID: USBIDs.wiredVID, productID: USBIDs.wiredPID, transport: "")
    let dongle = DeviceInfo(name: "x", vendorID: USBIDs.dongleVID, productID: USBIDs.donglePID, transport: "")
    let bt = DeviceInfo(name: "x", vendorID: USBIDs.dongleVID, productID: USBIDs.bluetoothPID, transport: "")
    expect(wired.connection == .wired && dongle.connection == .dongle && bt.connection == .bluetooth)
    expect(wired.connection.canWrite && !dongle.connection.canWrite && dongle.connection.canLive && !bt.connection.canLive)
}

test("legends: Windows and Mac") {
    let win = Layout.byName["lwin"]!, alt = Layout.byName["lalt"]!, bs = Layout.byName["backspace"]!
    expect(Legends.physical(win, flavor: .windows) == Legend("Win"))
    expect(Legends.physical(win, flavor: .mac) == Legend("⌘", "cmd"))
    expect(Legends.physical(alt, flavor: .mac).main == "⌥")
    expect(Legends.physical(bs, flavor: .mac).main == "⌫")
    expect(Flavor(osMode: 2) == .mac && Flavor(osMode: 0) == .windows && Flavor(osMode: 1) == .windows)
    expect(Flavor.mac.keymapSystem == 1 && Flavor.windows.keymapSystem == 0)
    let ctrlC = KeyEntry.key(hid: 0x06, modifiers: 0x01)
    expect(Legends.entry(ctrlC, flavor: .windows).main == "Ctrl+C")
    expect(Legends.entry(KeyEntry.key(hid: 0x06, modifiers: 0x08), flavor: .mac).main == "⌘C")
    expect(Legends.entry(KeyEntry([0, 0x08, 0, 0]), flavor: .mac).main == "⌘")
    expect(Legends.entry(.disabled, flavor: .mac).main == "—")
    expect(Legends.entry(KeyEntry([7, 0, 0, 0x1A]), flavor: .windows) == Legend("Mac", "mode"), "Fn+E is Mac mode")
    expect(Legends.entry(KeyEntry([8, 3, 1, 0]), flavor: .windows).main == "Bright +")
    expect(Legends.entry(.consumer(0xE2), flavor: .mac).main == "Mute")
}
test("per-key apply selects custom first, then resends the table") {
    let (kb, ch) = AulaKeyboard.demo()
    let table = Custom.encode(Themes.solid(RGB(5, 6, 7)))
    try kb.showCustom(table)
    expect(ch.led[LEDConfig.effectOffset] == 0x15 && ch.led[LEDConfig.effectHighOffset] == 1, "custom effect 277 selected")
    expect(ch.custom == table)
    try kb.showCustom(table)   // unchanged table is still sent again
    expect(ch.log.filter { $0 == Wire.writeCustom }.count == 2, "table re-sent even when unchanged")
    let lastLED = ch.log.lastIndex(of: Wire.writeLED) ?? -1
    let firstCustom = ch.log.firstIndex(of: Wire.writeCustom) ?? -1
    expect(firstCustom > lastLED || ch.log.firstIndex(of: Wire.writeLED)! < firstCustom, "effect first")
}

print("\n\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
