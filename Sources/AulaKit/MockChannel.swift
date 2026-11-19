import Foundation

/// A simulated keyboard that speaks the wired protocol. Used by the self-test and the app's demo mode.
public final class MockChannel: FeatureChannel, @unchecked Sendable {
    public var led: [UInt8]
    public var palettePage: [UInt8]
    public var custom: [UInt8]
    public var keymaps: [[UInt8]]   // 512-byte pages, indexed by sub (layer | system<<2)
    public private(set) var log: [UInt8] = []          // every command byte received
    public private(set) var liveFrames: [[UInt8]] = []
    /// Simulate a firmware that ignores writes.
    public var dropWrites = false
    private var pending: [UInt8]?

    public init() {
        var l = [UInt8](repeating: 0, count: Wire.ledLength)
        l[LEDConfig.effectOffset] = 1
        l[LEDConfig.sleepOffset] = 2
        l[Wire.ledLength - 2] = 0x5A; l[Wire.ledLength - 1] = 0xA5
        for hw in 1...LEDConfig.slotCount { let o = LEDConfig.slotsOffset + 2 * (hw - 1); l[o] = 5; l[o + 1] = 0x20 | 6 }
        led = l
        var p = [UInt8](repeating: 0, count: Wire.pageLength)
        for hw in 0..<Palette.count { for (i, c) in Palette.factory.enumerated() {
            let o = hw * 21 + i * 3; p[o] = c.r; p[o + 1] = c.g; p[o + 2] = c.b } }
        p[Wire.paletteMagicOffset] = 0x5A; p[Wire.paletteMagicOffset + 1] = 0xA5
        palettePage = p
        custom = [UInt8](repeating: 0, count: Wire.customLength)
        var base = [UInt8](repeating: 0, count: Wire.pageLength)
        for k in Layout.keys {
            if let h = Keymap.hid[k.name] { base[4 * k.index + 3] = UInt8(h) }
            else if let m = Keymap.modifiers[k.name] { base[4 * k.index + 1] = UInt8(m) }
            else { base[4 * k.index + 3] = 0x01 }
        }
        base[510] = 0x5A; base[511] = 0xA5
        var fn = base
        for i in 0..<Wire.keymapLength { fn[i] = 0 }
        for (name, usage) in [("f1", 0xB6), ("f2", 0xCD), ("f3", 0xB5), ("f4", 0xE2), ("f5", 0xEA), ("f6", 0xE9)] {
            if let k = Layout.byName[name] { fn[4 * k.index + 0] = 2; fn[4 * k.index + 2] = UInt8(usage >> 8); fn[4 * k.index + 3] = UInt8(usage & 0xFF) }
        }
        keymaps = [base, fn, fn, fn, base, fn, fn, fn]
    }

    public func setFeature(_ bytes: [UInt8]) throws {
        guard bytes.count == Wire.reportLength, bytes[0] == Wire.reportID else { throw AulaError.protocolError("mock: bad report") }
        let cmd = bytes[1], sub = bytes[2]
        log.append(cmd)
        let len = Int(bytes[6]) | Int(bytes[7]) << 8
        let data = Array(bytes[Wire.headerLength..<Wire.headerLength + (cmd == Wire.writeKeymap ? 512 : min(len, 512))])
        var reply = [UInt8](repeating: 0, count: Wire.reportLength)
        reply[0..<Wire.headerLength] = bytes[0..<Wire.headerLength]
        func put(_ d: [UInt8]) { reply.replaceSubrange(Wire.headerLength..<Wire.headerLength + d.count, with: d) }
        switch cmd {
        case Wire.readLED: put(led); pending = reply
        case Wire.readPalette: put(palettePage); pending = reply
        case Wire.readCustom: put(custom); pending = reply
        case Wire.readKeymap: put(keymaps[Int(sub) & 7]); pending = reply
        case Wire.readInfo: put([3, 0, 0, 0, 0, 0xCD, 1, 2, 0, 0]); pending = reply
        case Wire.readBattery: put([80, 0x10]); pending = reply
        case Wire.writeLED: if !dropWrites { led = data }
        case Wire.writePalette: if !dropWrites { palettePage = data }
        case Wire.writeCustom: if !dropWrites { custom = data }
        case Wire.writeKeymap: if !dropWrites { keymaps[Int(sub) & 7] = data }
        case Wire.live: liveFrames.append(bytes)
        default: throw AulaError.protocolError(String(format: "mock: unexpected command 0x%02x", cmd))
        }
    }

    public func getFeature(id: UInt8, length: Int) throws -> [UInt8] {
        guard let p = pending else { return [UInt8](repeating: 0, count: length) }
        return p
    }
}

public extension AulaKeyboard {
    /// A simulated keyboard (demo mode) and its channel for inspection.
    static func demo() -> (AulaKeyboard, MockChannel) {
        let ch = MockChannel()
        let kb = AulaKeyboard(channel: ch,
                              info: DeviceInfo(name: "AULA F75 (demo)", vendorID: USBIDs.wiredVID, productID: USBIDs.wiredPID, transport: "simulated", isDemo: true),
                              keysHeld: { false }, sleeper: { _ in })
        return (kb, ch)
    }
}
