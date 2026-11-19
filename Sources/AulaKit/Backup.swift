import Foundation

/// A snapshot of everything the hub can read from the keyboard.
public struct Backup: Codable, Sendable {
    public var created: Date
    public var device: String
    public var led: String
    public var palette: String
    public var custom: String
    public var keymapBase: String
    public var keymapFn: String
    public var keymapBaseMac: String?
    public var keymapFnMac: String?
    public var version: Int = 1

    public static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
    static func bytes(_ s: String) throws -> [UInt8] {
        guard s.count % 2 == 0 else { throw AulaError.protocolError("corrupt backup") }
        var out: [UInt8] = []; var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let v = UInt8(s[i..<j], radix: 16) else { throw AulaError.protocolError("corrupt backup") }
            out.append(v); i = j
        }
        return out
    }

    public static func capture(from kb: AulaKeyboard) throws -> Backup {
        Backup(created: Date(), device: kb.info.name,
               led: hex(try kb.readLED().raw), palette: hex(try kb.readPalette()), custom: hex(try kb.readCustom()),
               keymapBase: hex(try kb.readKeymap(layer: 0)), keymapFn: hex(try kb.readKeymap(layer: 1)),
               keymapBaseMac: try? hex(kb.readKeymap(layer: 0, system: 1)), keymapFnMac: try? hex(kb.readKeymap(layer: 1, system: 1)))
    }

    /// Write lighting, palettes and per-key colors back, and optionally the keymaps.
    public func restore(to kb: AulaKeyboard, includeKeymap: Bool = false) throws {
        let ledRaw = try Self.bytes(led)
        var cfg = try LEDConfig(raw: ledRaw)
        if cfg.sleep == 0 { try cfg.setSleep(60) }
        try kb.writePalette(try Self.bytes(palette))
        try kb.writeCustom(try Self.bytes(custom))
        try kb.writeLED(cfg)
        if includeKeymap {
            try kb.writeKeymap(try Self.bytes(keymapBase), layer: 0)
            try kb.writeKeymap(try Self.bytes(keymapFn), layer: 1)
            if let m = keymapBaseMac { try kb.writeKeymap(try Self.bytes(m), layer: 0, system: 1) }
            if let m = keymapFnMac { try kb.writeKeymap(try Self.bytes(m), layer: 1, system: 1) }
        }
    }

    // MARK: files

    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AulaHub/backups", isDirectory: true)
    }

    @discardableResult
    public func save(to url: URL? = nil, name: String? = nil) throws -> URL {
        let dir = Self.directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: created).replacingOccurrences(of: ":", with: "-")
        let target = url ?? dir.appendingPathComponent((name ?? "backup-\(stamp)") + ".json")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: target, options: .atomic)
        return target
    }

    public static func load(_ url: URL) throws -> Backup {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Backup.self, from: Data(contentsOf: url))
    }

    public static func list() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }
}
