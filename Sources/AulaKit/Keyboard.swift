import Foundation

/// High level access to a keyboard. On the cable everything works and every write is verified by
/// reading back. Over the 2.4G dongle and Bluetooth the keyboard can be read (and, on the dongle,
/// driven with live lighting); settings are never written over the radio.
public final class AulaKeyboard: @unchecked Sendable {
    public let info: DeviceInfo
    private let channel: FeatureChannel?
    private let radio: PacketChannel?
    private let radioQuiet: TimeInterval
    private let lock = NSRecursiveLock()
    private let keysHeld: () -> Bool
    private let sleeper: (TimeInterval) -> Void
    private var lastLive = Date.distantPast
    private var lastWrite = Date.distantPast
    public static let liveMinInterval: TimeInterval = 0.05  // 20 frames/s at most

    public init(channel: FeatureChannel, info: DeviceInfo, keysHeld: @escaping () -> Bool = anyKeyHeld,
                sleeper: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.channel = channel; self.radio = nil; self.radioQuiet = 0
        self.info = info; self.keysHeld = keysHeld; self.sleeper = sleeper
    }

    /// A keyboard on the 2.4G dongle or Bluetooth.
    public init(radio: PacketChannel, info: DeviceInfo, keysHeld: @escaping () -> Bool = anyKeyHeld,
                quiet: TimeInterval = 0.4, sleeper: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.channel = nil; self.radio = radio; self.radioQuiet = quiet
        self.info = info; self.keysHeld = keysHeld; self.sleeper = sleeper
    }

    /// The cable wins; with the switch on 2.4G or Bluetooth the radio interface is used.
    public static func connect() throws -> AulaKeyboard {
        do {
            let (ch, info) = try HIDDiscovery.openWired()
            return AulaKeyboard(channel: ch, info: info)
        } catch AulaError.notFound {
            let (ch, info) = try HIDDiscovery.openRadio()
            return AulaKeyboard(radio: ch, info: info)
        }
    }

    public var connection: Connection { info.connection }

    private func requireWired() throws {
        guard info.connection.canWrite else {
            throw AulaError.refused("settings are only written over the USB cable, never over \(info.connection.title). Plug the keyboard in to change them (reading, backups and live lighting still work wirelessly).")
        }
    }

    private func sync<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }

    // MARK: low level

    private func waitKeysReleased() throws {
        var waited = 0.0
        while keysHeld() {
            if waited > 3 { throw AulaError.refused("a key is held down; release it and try again") }
            sleeper(0.02); waited += 0.02
        }
    }

    private var cable: FeatureChannel {
        get throws {
            guard let channel else { throw AulaError.refused("this is not a cable connection") }
            return channel
        }
    }

    private func wiredGet(cmd: UInt8, sub: UInt8 = 0, asked: Int, length: Int, magicAt: Int? = nil, magic: [UInt8] = Wire.ledMagic) throws -> [UInt8] {
        guard !Wire.forbidden.contains(cmd) else { throw AulaError.refused(String(format: "command 0x%02x is never sent", cmd)) }
        for _ in 0..<3 {
            try waitKeysReleased()
            try cable.setFeature(Wire.request(cmd: cmd, sub: sub, length: asked))
            sleeper(0.02)
            let rep = try cable.getFeature(id: Wire.reportID, length: Wire.reportLength)
            // While busy the firmware can answer with a truncated, mostly zero block.
            if let data = Wire.reply(rep, cmd: cmd, sub: sub, length: length),
               magicAt == nil || Array(data[magicAt!..<magicAt! + 2]) == magic {
                return data
            }
            sleeper(0.1)
        }
        throw AulaError.noReply(String(format: "no matching reply to 0x%02x from the keyboard; try again", cmd))
    }

    private func wiredPut(cmd: UInt8, sub: UInt8 = 0, data: [UInt8], declaredLength: Int? = nil, readBack: () throws -> [UInt8]) throws {
        guard [Wire.writeLED, Wire.writePalette, Wire.writeCustom, Wire.writeKeymap].contains(cmd) else {
            throw AulaError.refused(String(format: "0x%02x is not a known write command", cmd))
        }
        try waitKeysReleased()
        try cable.setFeature(try Wire.writeReport(cmd: cmd, sub: sub, data: data, declaredLength: declaredLength))
        lastWrite = Date()
        sleeper(Wire.settle)
        let back: [UInt8]
        do { back = try readBack() } catch {
            throw AulaError.verifyFailed(String(format: "write 0x%02x was sent but couldn't be checked (%@); read the keyboard again to see its state", cmd, error.localizedDescription))
        }
        if back != data { throw AulaError.verifyFailed(String(format: "the keyboard didn't keep write 0x%02x (the read-back differs)", cmd)) }
    }

    // MARK: reads

    public func readLED() throws -> LEDConfig {
        try sync {
            if radio != nil { return try LEDConfig(raw: radioGet(cmd: Radio.cmdLED, length: Wire.ledLength, magicAt: Wire.ledLength - 2)) }
            return try LEDConfig(raw: wiredGet(cmd: Wire.readLED, asked: Wire.ledLength, length: Wire.ledLength, magicAt: Wire.ledLength - 2))
        }
    }

    public func readCustom() throws -> [UInt8] {
        try sync {
            if radio != nil { return try radioGet(cmd: Radio.cmdCustom, length: Wire.customLength) }
            return try wiredGet(cmd: Wire.readCustom, asked: Wire.customLength, length: Wire.customLength)
        }
    }

    /// The 512-byte palette page; the first 490 bytes are the palettes.
    private func readPalettePage() throws -> [UInt8] {
        try wiredGet(cmd: Wire.readPalette, asked: Wire.pageLength, length: Wire.pageLength, magicAt: Wire.paletteMagicOffset)
    }

    public func readPalette() throws -> [UInt8] {
        try sync {
            if radio != nil { return try radioGet(cmd: Radio.cmdPalette, length: Wire.paletteLength) }
            return Array(try readPalettePage().prefix(Wire.paletteLength))
        }
    }

    /// 126 entries × 4 bytes. `layer` 0 = base, 1 = Fn; `system` 0 = Windows table, 1 = Mac table.
    public func readKeymap(layer: Int = 0, system: Int = 0) throws -> [UInt8] {
        guard (0...3).contains(layer), (0...1).contains(system) else { throw AulaError.refused("layer must be 0-3, system 0-1") }
        return try sync {
            if radio != nil {
                // The radio protocol only exposes the Windows table, layers 0 and 1.
                guard system == 0, layer <= 1 else { throw AulaError.refused("only the base and Fn layers of the Windows table can be read over \(info.connection.title); connect the cable for the Mac table") }
                return try radioGet(cmd: Radio.cmdKeymap, sub: UInt8(layer), length: Wire.keymapLength)
            }
            return try wiredGet(cmd: Wire.readKeymap, sub: Wire.keymapSub(layer: layer, system: system), asked: Wire.keymapLength, length: Wire.keymapLength)
        }
    }

    /// Firmware identity as the official app reads it: 6-byte UUID, 2-byte version.
    public func readInfo() throws -> (uuid: String, version: String) {
        try sync {
            guard radio == nil else { throw AulaError.refused("firmware info can only be read over the USB cable") }
            let d = try wiredGet(cmd: Wire.readInfo, sub: 1, asked: 10, length: 10)
            let hex = { (b: ArraySlice<UInt8>) in b.map { String(format: "%02x", $0) }.joined() }
            return ("0x" + hex(d[0..<6]), "0x" + hex(d[6..<8]))
        }
    }

    public struct Battery: Sendable, Equatable {
        public var level: Int, charging: Bool, full: Bool
        public init(level: Int, charging: Bool, full: Bool) { self.level = level; self.charging = charging; self.full = full }
    }

    public func readBattery() throws -> Battery {
        try sync {
            if radio != nil {
                // The profile reply is `64 01` when full; the first byte is the charge in percent.
                let d = try radioGet(cmd: Radio.cmdProfile, length: 1)
                return Battery(level: min(Int(d[0]), 100), charging: false, full: false)
            }
            let d = try wiredGet(cmd: Wire.readBattery, asked: 2, length: 2)
            return Battery(level: Int(d[0]), charging: (d[1] >> 4) & 0x0F == 1, full: d[1] & 0x0F == 1)
        }
    }

    // MARK: writes

    /// Write the LED block changing only bytes whose meaning is known; reads it back.
    public func writeLED(_ cfg: LEDConfig) throws {
        try requireWired()
        let raw = cfg.raw
        guard raw.count == Wire.ledLength, Array(raw.suffix(2)) == Wire.ledMagic else {
            throw AulaError.refused("the LED block is damaged (it has to end in 5a a5)")
        }
        // A keyboard that never sleeps drains its battery with the lights on.
        guard cfg.sleep != 0 else { throw AulaError.refused("sleep 'never' is not allowed; pick a sleep time") }
        try sync {
            let current = try readLED().raw
            var allowed = LEDConfig.writable
            if let o = LEDConfig.slotOffset(cfg.effect) { allowed.insert(o); allowed.insert(o + 1) }
            let changed = (0..<Wire.ledLength).filter { raw[$0] != current[$0] }
            let unknown = changed.filter { !allowed.contains($0) }
            guard unknown.isEmpty else { throw AulaError.refused("the write would change LED bytes \(unknown), whose meaning is unknown") }
            if !changed.isEmpty {
                try wiredPut(cmd: Wire.writeLED, data: raw) { try self.readLED().raw }
            }
        }
    }

    /// Edit the LED block in place: read, mutate, write.
    @discardableResult
    public func updateLED(_ body: (inout LEDConfig) throws -> Void) throws -> LEDConfig {
        try sync {
            var cfg = try readLED()
            try body(&cfg)
            try writeLED(cfg)
            return cfg
        }
    }

    public func writePalette(_ palette: [UInt8]) throws {
        try requireWired()
        guard palette.count == Wire.paletteLength else { throw AulaError.refused("effect palettes must be \(Wire.paletteLength) bytes") }
        try sync {
            let page = try readPalettePage()
            let new = palette + page[Wire.paletteLength...]
            if Array(new) == page { return }
            let led = try readLED().raw
            try wiredPut(cmd: Wire.writePalette, data: Array(new)) { try self.readPalettePage() }
            // The official app re-sends the unchanged LED block to apply the palette.
            try wiredPut(cmd: Wire.writeLED, data: led) { try self.readLED().raw }
        }
    }

    public func writeCustom(_ raw: [UInt8], force: Bool = false) throws {
        try requireWired()
        guard raw.count == Wire.customLength else { throw AulaError.refused("per-key color table must be \(Wire.customLength) bytes") }
        try sync {
            if !force, raw == (try readCustom()) { return }
            try wiredPut(cmd: Wire.writeCustom, data: raw) { try self.readCustom() }
        }
    }

    /// Write a keymap table, exactly like the official Aula Hub: header `03 sub 00 01 00 f8 01`, then
    /// the 504 key bytes, six zero bytes and `5a a5`. Read back and compared.
    public func writeKeymap(_ keymap: [UInt8], layer: Int = 0, system: Int = 0) throws {
        try requireWired()
        guard keymap.count == Wire.keymapLength, (0...3).contains(layer), (0...1).contains(system) else { throw AulaError.refused("bad keymap") }
        try sync {
            let sub = Wire.keymapSub(layer: layer, system: system)
            let current = try readKeymap(layer: layer, system: system)
            guard current.contains(where: { $0 != 0 }) else {
                throw AulaError.refused("the keyboard returned an empty keymap; not writing over it")
            }
            if keymap == current { return }
            let page = keymap + [UInt8](repeating: 0, count: Wire.keymapPage - Wire.keymapLength - 2) + Wire.ledMagic
            try wiredPut(cmd: Wire.writeKeymap, sub: sub, data: page, declaredLength: Wire.keymapLength) {
                let back = try self.readKeymap(layer: layer, system: system)
                return back == keymap ? page : back   // compare the key bytes; the trailer isn't read back
            }
        }
    }

    // MARK: live frames

    /// Show colors right now; nothing is stored. The keyboard goes back to its own effect ~2 s after the last frame.
    public func sendLive(_ colors: [Int: RGB]) throws {
        if radio != nil { return try sendRadioLive(colors) }
        let wait = lastLive.addingTimeInterval(Self.liveMinInterval).timeIntervalSinceNow
        if wait > 0 { sleeper(wait) }
        lastLive = Date()
        let report = Wire.liveReport(colors: colors)
        guard Array(report.prefix(Wire.headerLength)) == Wire.liveHeader else { throw AulaError.refused("wrong header for a live frame") }
        try sync { try cable.setFeature(report) }
    }

    // MARK: radio (2.4G dongle / Bluetooth)

    /// Wait until no key has been held for `radioQuiet` seconds. While the keyboard answers configuration
    /// traffic it can drop the release of a key pressed at that moment, which would then auto-repeat.
    private func waitQuiet() throws {
        let start = Date()
        var quietSince = Date()
        while true {
            if keysHeld() { quietSince = Date() }
            if Date().timeIntervalSince(quietSince) >= radioQuiet { return }
            if Date().timeIntervalSince(start) > 5 { throw AulaError.refused("a key is held down; release it and try again") }
            sleeper(0.02)
        }
    }

    /// Send a read request and reassemble the reply by packet index. Packets get lost (over Bluetooth
    /// roughly every other one), and the keyboard always resends the whole reply, so the request is
    /// repeated and parts are collected across attempts.
    private func radioGet(cmd: UInt8, sub: UInt8 = 0, length: Int, magicAt: Int? = nil) throws -> [UInt8] {
        guard let radio else { throw AulaError.refused("this is not a radio connection") }
        guard Radio.readable.contains(cmd) else { throw AulaError.refused(String(format: "0x%02x is not a known read command", cmd)) }
        let bluetooth = info.connection == .bluetooth
        var parts: [Int: [UInt8]] = [:]
        var total: Int?
        for _ in 0..<(bluetooth ? 15 : 4) {
            try waitQuiet()
            radio.drain()
            if bluetooth { sleeper(Double.random(in: 0...0.05)) }   // shift the burst against the radio's slots
            try radio.write(Radio.readRequest(cmd: cmd, sub: sub))
            let deadline = Date().addingTimeInterval(2)
            var last: Date?
            while Date() < deadline {
                if let last, Date().timeIntervalSince(last) > 0.25 { break }   // this burst is over
                guard let raw = radio.receive(timeout: 0.05), let rep = Radio.parse(raw), rep.cmd == cmd | Radio.readFlag else { continue }
                if rep.error { throw AulaError.protocolError(String(format: "the keyboard rejected read 0x%02x", cmd | Radio.readFlag)) }
                last = Date(); total = rep.total
                if rep.index < rep.total { parts[rep.index] = rep.data }
                if rep.total > 0, parts.count == rep.total {
                    let data = (0..<rep.total).flatMap { parts[$0] ?? [] }
                    guard data.count >= length else { throw AulaError.protocolError("short reply to 0x\(String(cmd, radix: 16)): \(data.count) of \(length) bytes") }
                    let out = Array(data.prefix(length))
                    if let m = magicAt, Array(out[m..<m + 2]) != Wire.ledMagic { parts.removeAll(); break }
                    return out
                }
            }
        }
        throw AulaError.noReply(total == nil
            ? "the keyboard didn't answer. It may be asleep: press any key to wake it, then try again"
            : "the wireless link kept dropping packets; move closer or use the cable")
    }

    /// One live frame over the dongle: groups of keys sharing a color, sent as packets 5 ms apart.
    /// The keyboard shows the custom effect's frames; ~2 s without frames it returns to its own effect.
    private func sendRadioLive(_ colors: [Int: RGB]) throws {
        guard info.connection.canLive else { throw AulaError.refused("live lighting isn't supported over Bluetooth; use the dongle or the cable") }
        guard let radio else { return }
        let packets = Radio.liveFrame(colors)
        let wait = lastLive.addingTimeInterval(Double(packets.count) * Radio.liveGap + 0.03).timeIntervalSinceNow
        if wait > 0 { sleeper(wait) }
        try sync {
            for p in packets {
                guard p[1] == Radio.cmdLive else { throw AulaError.refused("only live frames may be written over the radio") }
                try radio.write(p)
                sleeper(Radio.liveGap)
            }
            lastLive = Date()
        }
    }

    // MARK: convenience

    public func setEffect(_ hw: Int, brightness: Int? = nil, speed: Int? = nil, color: Int? = nil) throws {
        guard Effects.byHW(hw) != nil else { throw AulaError.refused("unknown effect \(hw)") }
        try updateLED { cfg in
            cfg.effect = hw
            if var s = cfg.slot(hw) {
                if let brightness { s.brightness = brightness }
                if let speed { s.speed = speed }
                if let color { s.color = color }
                try cfg.setSlot(hw, s)
            }
        }
    }
}
