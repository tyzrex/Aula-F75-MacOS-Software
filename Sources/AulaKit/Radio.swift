import Foundation
import IOKit
import IOKit.hid

/// The 2.4G dongle / Bluetooth configuration protocol: 20-byte packets on HID report 0x13.
///
/// ```
/// [0] 0x13   [1] command (read = write | 0x40)   [2] packet count (bit 7 = error)
/// [3] packet index   [4] (sub << 4) | payload length (≤ 14)   [5..18] payload   [19] sum[0..18]
/// ```
///
/// Only reads and live lighting are ever sent over the radio. Writing settings over the
/// radio is refused on purpose: packets get lost, and a radio write is known to have left
/// an F75 unable to type until its firmware was reflashed.
public enum Radio {
    public static let reportID: UInt8 = 0x13
    public static let packetLength = 20
    public static let chunk = 14

    public static let readFlag: UInt8 = 0x40
    public static let cmdKeymap: UInt8 = 0x01
    public static let cmdCustom: UInt8 = 0x02
    public static let cmdLED: UInt8 = 0x04
    public static let cmdPalette: UInt8 = 0x09
    public static let cmdProfile: UInt8 = 0x0A
    public static let cmdLive: UInt8 = 0x88
    public static let liveSubKeys: UInt8 = 1
    public static let liveMax = 200
    /// Closer together than this and the keyboard drops live packets.
    public static let liveGap: TimeInterval = 0.005

    /// Commands that may be read. Anything else is refused before it reaches the keyboard.
    public static let readable: Set<UInt8> = [cmdKeymap, cmdCustom, cmdLED, cmdPalette, cmdProfile]

    public static func checksum(_ b: [UInt8]) -> UInt8 {
        UInt8(truncatingIfNeeded: b.prefix(19).reduce(0) { $0 &+ Int($1) })
    }

    public static func packet(cmd: UInt8, total: Int, index: Int, sub: UInt8, chunk data: [UInt8]) -> [UInt8] {
        precondition(data.count <= chunk, "a packet carries at most 14 payload bytes")
        var b = [UInt8](repeating: 0, count: packetLength)
        b[0] = reportID; b[1] = cmd; b[2] = UInt8(total); b[3] = UInt8(index)
        b[4] = (sub << 4) | UInt8(data.count)
        b.replaceSubrange(5..<5 + data.count, with: data)
        b[19] = checksum(b)
        return b
    }

    public static func readRequest(cmd: UInt8, sub: UInt8 = 0) -> [UInt8] {
        packet(cmd: cmd | readFlag, total: 1, index: 0, sub: sub, chunk: [])
    }

    public static func splitPackets(cmd: UInt8, sub: UInt8, data: [UInt8]) -> [[UInt8]] {
        var chunks = stride(from: 0, to: data.count, by: chunk).map { Array(data[$0..<min($0 + chunk, data.count)]) }
        if chunks.isEmpty { chunks = [[]] }
        return chunks.enumerated().map { packet(cmd: cmd, total: chunks.count, index: $0.offset, sub: sub, chunk: $0.element) }
    }

    public struct Reply: Equatable {
        public var cmd: UInt8, total: Int, index: Int, error: Bool, data: [UInt8]
        public init(cmd: UInt8, total: Int, index: Int, error: Bool, data: [UInt8]) {
            self.cmd = cmd; self.total = total; self.index = index; self.error = error; self.data = data
        }
    }

    /// Decode a report from the keyboard; nil when it isn't a valid configuration packet.
    public static func parse(_ r: [UInt8]) -> Reply? {
        guard r.count >= packetLength, r[0] == reportID, checksum(r) == r[19] else { return nil }
        let n = min(Int(r[4] & 0x0F), chunk)
        return Reply(cmd: r[1], total: Int(r[2] & 0x7F), index: Int(r[3]), error: r[2] & 0x80 != 0, data: Array(r[5..<5 + n]))
    }

    // MARK: live frames

    /// Encode per-key colors as `R G B count index…` groups, at most `liveMax` bytes.
    /// Keys that aren't listed are dark. Similar colors are merged until the frame fits.
    public static func liveGroups(_ colors: [Int: RGB], limit: Int = liveMax) -> [UInt8] {
        let lit = colors.filter { ($0.value.r | $0.value.g | $0.value.b) != 0 && (0..<Wire.liveKeys).contains($0.key) }
        for shift in 0...7 {
            var buckets: [[UInt8]: (sum: (Int, Int, Int), keys: [Int])] = [:]
            for (index, c) in lit.sorted(by: { $0.key < $1.key }) {
                let key = [c.r >> UInt8(shift), c.g >> UInt8(shift), c.b >> UInt8(shift)]
                var e = buckets[key] ?? ((0, 0, 0), [])
                e.sum = (e.sum.0 + Int(c.r), e.sum.1 + Int(c.g), e.sum.2 + Int(c.b)); e.keys.append(index)
                buckets[key] = e
            }
            var out: [UInt8] = []
            for (_, e) in buckets.sorted(by: { $0.value.keys[0] < $1.value.keys[0] }) {
                let n = e.keys.count
                var keys = e.keys
                while !keys.isEmpty {   // a group's count is one byte
                    let part = Array(keys.prefix(255)); keys.removeFirst(part.count)
                    out += [UInt8(e.sum.0 / n), UInt8(e.sum.1 / n), UInt8(e.sum.2 / n), UInt8(part.count)] + part.map { UInt8($0) }
                }
            }
            if out.count <= limit || shift == 7 { return Array(out.prefix(limit)) }
        }
        return []
    }

    public static func liveFrame(_ colors: [Int: RGB]) -> [[UInt8]] {
        splitPackets(cmd: cmdLive, sub: liveSubKeys, data: liveGroups(colors))
    }
}

/// A channel carrying 20-byte configuration packets.
public protocol PacketChannel: AnyObject {
    func write(_ packet: [UInt8]) throws
    /// The next report from the keyboard, or nil after `timeout` seconds.
    func receive(timeout: TimeInterval) -> [UInt8]?
    /// Throw away anything received but not yet read.
    func drain()
}

/// The radio configuration interface (usage page 0xFF02, report 0x13) through IOKit.
public final class RadioChannel: PacketChannel, @unchecked Sendable {
    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "aula.radio.input")
    private let lock = NSCondition()
    private var inbox: [[UInt8]] = []
    private var buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize = 64
    private var opened = false

    init(device: IOHIDDevice) {
        self.device = device
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    func open() throws {
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else {
            throw AulaError.openFailed(r == kIOReturnNotPermitted
                ? "macOS blocked access. Allow this app under System Settings → Privacy & Security → Input Monitoring, then restart it."
                : String(format: "IOKit error 0x%08x", r))
        }
        opened = true
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, _, _, _, id, report, length in
            guard let context else { return }
            Unmanaged<RadioChannel>.fromOpaque(context).takeUnretainedValue().received(id: UInt8(truncatingIfNeeded: id), report: report, length: length)
        }, ctx)
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceActivate(device)
    }

    deinit {
        if opened {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
            IOHIDDeviceCancel(device)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        buffer.deallocate()
    }

    private func received(id: UInt8, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        var bytes = Array(UnsafeBufferPointer(start: report, count: length))
        // Depending on the stack the report id is or isn't part of the buffer.
        if bytes.first != Radio.reportID || bytes.count < Radio.packetLength { bytes.insert(id, at: 0) }
        guard bytes.first == Radio.reportID else { return }
        lock.lock(); inbox.append(bytes); if inbox.count > 256 { inbox.removeFirst(128) }; lock.signal(); lock.unlock()
    }

    public func write(_ packet: [UInt8]) throws {
        let r = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(packet[0]), $0.baseAddress!, packet.count)
        }
        guard r == kIOReturnSuccess else {
            throw AulaError.noReply(r == kIOReturnNotPermitted
                ? "macOS denied access — grant Input Monitoring permission."
                : String(format: "sending to the keyboard failed (IOKit 0x%08x)", r))
        }
    }

    public func receive(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        lock.lock(); defer { lock.unlock() }
        while inbox.isEmpty {
            if !lock.wait(until: deadline) { break }
        }
        return inbox.isEmpty ? nil : inbox.removeFirst()
    }

    public func drain() { lock.lock(); inbox.removeAll(); lock.unlock() }
}

public extension HIDDiscovery {
    /// Open the radio configuration interface of a keyboard on the dongle or Bluetooth.
    static func openRadio(only: Connection? = nil) throws -> (RadioChannel, DeviceInfo) {
        let radio = enumerate().filter { $0.info.vendorID == USBIDs.dongleVID && (only == nil || $0.info.connection == only) }
        guard !radio.isEmpty else { throw AulaError.notFound }
        // The configuration collection is vendor defined: 0xFF02 on the dongle.
        let pick = radio.first { $0.usagePage == 0xFF02 } ?? radio.first { $0.usagePage >= 0xFF00 }
        guard let c = pick else {
            throw AulaError.refused("the keyboard's wireless configuration interface isn't visible to macOS")
        }
        let ch = RadioChannel(device: c.device)
        try ch.open()
        return (ch, c.info)
    }
}

public extension HIDDiscovery {
    /// Which kinds of connection macOS can currently see (without opening anything).
    static func present() -> Set<Connection> { Set(enumerate().map(\.info.connection)) }
}
