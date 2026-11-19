import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

/// A HID feature-report channel to the keyboard's configuration interface.
public protocol FeatureChannel: AnyObject {
    /// Send a feature report; `bytes[0]` is the report id.
    func setFeature(_ bytes: [UInt8]) throws
    /// Fetch a feature report; the result starts with the report id.
    func getFeature(id: UInt8, length: Int) throws -> [UInt8]
}

public struct DeviceInfo: Sendable, Equatable {
    public var name: String
    public var vendorID: Int
    public var productID: Int
    public var transport: String
    public var isDemo: Bool = false

    public init(name: String, vendorID: Int, productID: Int, transport: String, isDemo: Bool = false) {
        self.name = name; self.vendorID = vendorID; self.productID = productID; self.transport = transport; self.isDemo = isDemo
    }

    /// How the keyboard is connected, derived from its USB ids.
    public var connection: Connection {
        if vendorID == USBIDs.wiredVID { return .wired }
        return productID == USBIDs.donglePID ? .dongle : .bluetooth
    }
}

public enum Connection: String, Sendable, CaseIterable {
    case wired, dongle, bluetooth

    public var title: String {
        switch self { case .wired: "USB cable"; case .dongle: "2.4G dongle"; case .bluetooth: "Bluetooth" }
    }
    public var symbol: String {
        switch self { case .wired: "cable.connector"; case .dongle: "dot.radiowaves.left.and.right"; case .bluetooth: "wave.3.right" }
    }
    /// Settings (lighting, remaps, palettes) are only ever written over the cable.
    public var canWrite: Bool { self == .wired }
    /// Real-time lighting frames work on the cable and the dongle.
    public var canLive: Bool { self != .bluetooth }
}

public enum USBIDs {
    public static let wiredVID = 0x258A
    public static let wiredPID = 0x010C
    public static let dongleVID = 0x3554
    public static let donglePID = 0xFA09
    public static let bluetoothPID = 0xFA07
}

public final class HIDChannel: FeatureChannel {
    let device: IOHIDDevice
    private var opened = false

    init(device: IOHIDDevice) { self.device = device }

    func open() throws {
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else {
            let hint = r == kIOReturnNotPermitted
                ? "macOS blocked access. Allow this app (or your terminal) under System Settings → Privacy & Security → Input Monitoring, then restart it."
                : (r == kIOReturnExclusiveAccess ? "another program has the keyboard open — quit the official AULA software." : String(format: "IOKit error 0x%08x", r))
            throw AulaError.openFailed(hint)
        }
        opened = true
    }

    deinit { if opened { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) } }

    public func setFeature(_ bytes: [UInt8]) throws {
        let r = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(bytes[0]), $0.baseAddress!, bytes.count)
        }
        guard r == kIOReturnSuccess else {
            throw AulaError.noReply(r == kIOReturnNotPermitted
                ? "macOS denied the write — grant Input Monitoring permission."
                : String(format: "sending to the keyboard failed (IOKit 0x%08x)", r))
        }
    }

    public func getFeature(id: UInt8, length: Int) throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: length)
        buf[0] = id
        var len = CFIndex(length)
        let r = buf.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), $0.baseAddress!, &len)
        }
        guard r == kIOReturnSuccess else {
            throw AulaError.noReply(String(format: "reading from the keyboard failed (IOKit 0x%08x)", r))
        }
        return Array(buf[0..<Int(len)])
    }
}

public enum HIDDiscovery {
    private static func int(_ d: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? 0
    }
    private static func str(_ d: IOHIDDevice, _ key: String) -> String {
        (IOHIDDeviceGetProperty(d, key as CFString) as? String) ?? ""
    }

    public struct Candidate {
        public let device: IOHIDDevice
        public let info: DeviceInfo
        public let usagePage: Int
        public let maxFeature: Int
    }

    public static func enumerate() -> [Candidate] {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Int]] = [
            [kIOHIDVendorIDKey: USBIDs.wiredVID, kIOHIDProductIDKey: USBIDs.wiredPID],
            [kIOHIDVendorIDKey: USBIDs.dongleVID, kIOHIDProductIDKey: USBIDs.donglePID],
            [kIOHIDVendorIDKey: USBIDs.dongleVID, kIOHIDProductIDKey: USBIDs.bluetoothPID],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)
        guard let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { return [] }
        return set.map { d in
            let vid = int(d, kIOHIDVendorIDKey), pid = int(d, kIOHIDProductIDKey)
            let transport = vid == USBIDs.wiredVID ? "USB cable" : (pid == USBIDs.donglePID ? "2.4G dongle" : "Bluetooth")
            let name = str(d, kIOHIDProductKey)
            return Candidate(device: d,
                             info: DeviceInfo(name: name.isEmpty ? "AULA F75" : name, vendorID: vid, productID: pid, transport: transport),
                             usagePage: int(d, kIOHIDPrimaryUsagePageKey),
                             maxFeature: int(d, kIOHIDMaxFeatureReportSizeKey))
        }
    }

    /// Open the configuration interface of a keyboard on the cable.
    public static func openWired() throws -> (HIDChannel, DeviceInfo) {
        let all = enumerate()
        let wired = all.filter { $0.info.vendorID == USBIDs.wiredVID && $0.info.productID == USBIDs.wiredPID }
        guard !wired.isEmpty else {
            throw AulaError.notFound
        }
        // The config collection is vendor defined (0xFF00) and carries a 520 byte feature report.
        let pick = wired.first { $0.usagePage == 0xFF00 && $0.maxFeature >= Wire.reportLength - 1 }
            ?? wired.first { $0.maxFeature >= Wire.reportLength - 1 }
            ?? wired.first { $0.usagePage == 0xFF00 }
        guard let c = pick else { throw AulaError.notFound }
        let ch = HIDChannel(device: c.device)
        try ch.open()
        return (ch, c.info)
    }
}

/// True while any key on the Mac keyboard is held down. A write sent while a key is pressed can leave it stuck.
public func anyKeyHeld() -> Bool {
    for code in 0..<128 where CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code)) { return true }
    return false
}
