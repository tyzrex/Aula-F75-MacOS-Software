import SwiftUI
import AulaKit

struct Notice: Identifiable { let id = UUID(); let text: String; let isError: Bool }

struct KeymapID: Hashable { var layer: Int; var system: Int }

/// How key legends are written: follow the keyboard's OS mode, or force one style.
enum LegendPreference: String, CaseIterable, Identifiable {
    case auto, windows, mac
    var id: String { rawValue }
    var title: String { switch self { case .auto: "Follow keyboard mode"; case .windows: "Windows"; case .mac: "Mac" } }
}

enum Prefs {
    static let autoConnect = "autoConnect"
    static let legends = "legendPreference"
    static let liveBrightness = "liveBrightness"
    static func register() { UserDefaults.standard.register(defaults: [autoConnect: true, legends: LegendPreference.auto.rawValue]) }
}

@MainActor
final class HubModel: ObservableObject {
    @Published var keyboard: AulaKeyboard?
    @Published var connecting = false
    @Published var busy = false
    @Published var notice: Notice?
    @Published var connectError: String?
    /// What macOS can currently see (cable, dongle, Bluetooth), refreshed every couple of seconds.
    @Published var present: Set<Connection> = []

    @Published var led: LEDConfig?
    @Published var palette: [UInt8]?
    @Published var custom: [Int: RGB] = [:]
    @Published var keymaps: [KeymapID: [UInt8]] = [:]
    @Published var battery: AulaKeyboard.Battery?
    @Published var firmware: String?
    @Published var liveRunning: LiveAnimation?

    private let io = DispatchQueue(label: "aula.io")
    private var liveTask: Task<Void, Never>?
    private var watcher: Timer?
    private var missedPolls = 0
    private var attemptedAuto: Set<Connection> = []

    var isConnected: Bool { keyboard != nil }
    var deviceName: String { keyboard?.info.name ?? "No keyboard" }
    var connection: Connection? { keyboard?.connection }
    var isDemo: Bool { keyboard?.info.isDemo == true }
    /// Settings are only written over the cable (and in demo mode).
    var canWrite: Bool { keyboard?.connection.canWrite ?? false }
    var canLive: Bool { keyboard?.connection.canLive ?? false }

    /// The OS mode stored on the keyboard (0 Windows, 1 Android, 2 Mac).
    var osMode: Int { led?.osMode ?? 0 }

    var legendPreference: LegendPreference {
        LegendPreference(rawValue: UserDefaults.standard.string(forKey: Prefs.legends) ?? "") ?? .auto
    }
    /// Legend style for keycaps: from the preference, or from the keyboard's own OS mode.
    var flavor: Flavor {
        switch legendPreference {
        case .auto: return Flavor(osMode: osMode)
        case .windows: return .windows
        case .mac: return .mac
        }
    }

    // MARK: connection

    func start() {
        Prefs.register()
        watcher?.invalidate()
        watcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        Task { await poll() }
    }

    /// Watch for the keyboard being plugged in or removed.
    private func poll() async {
        let now = await onIOQuiet { HIDDiscovery.present() }
        if now != present { present = now }
        if let kb = keyboard, !kb.info.isDemo {
            if now.contains(kb.connection) || connecting { missedPolls = 0 }
            else {
                missedPolls += 1
                if missedPolls >= 2 { disconnect(); notice = Notice(text: "The keyboard was disconnected.", isError: true) }
            }
            // Plugging the cable in while on the radio: switch to the cable.
            if kb.connection != .wired, now.contains(.wired), UserDefaults.standard.bool(forKey: Prefs.autoConnect) { connect(only: .wired) }
            return
        }
        // Only the cable is connected automatically; radio traffic is sent only when asked for.
        if keyboard == nil, !connecting, UserDefaults.standard.bool(forKey: Prefs.autoConnect) {
            if now.contains(.wired), !attemptedAuto.contains(.wired) {
                attemptedAuto.insert(.wired)
                connect(only: .wired)
            }
            if !now.contains(.wired) { attemptedAuto.remove(.wired) }
        }
    }

    func connect(demo: Bool = false, only: Connection? = nil) {
        guard !connecting else { return }
        connecting = true; connectError = nil
        Task {
            do {
                let kb: AulaKeyboard = try await onIO { demo ? AulaKeyboard.demo().0 : try AulaKeyboard.connect(only: only) }
                stopLive()
                keyboard = kb
                missedPolls = 0
                await refresh()
            } catch {
                keyboard = nil
                connectError = error.localizedDescription
            }
            connecting = false
        }
    }

    func disconnect() {
        stopLive()
        keyboard = nil; led = nil; palette = nil; custom = [:]; keymaps = [:]; battery = nil; firmware = nil
    }

    // MARK: reading

    func refresh() async {
        guard let kb = keyboard else { return }
        struct Snapshot: Sendable {
            var led: LEDConfig; var palette: [UInt8]?; var custom: [UInt8]?; var maps: [KeymapID: [UInt8]]
            var battery: AulaKeyboard.Battery?; var firmware: String?
        }
        do {
            let snap: Snapshot = try await onIO {
                let led = try kb.readLED()
                var maps: [KeymapID: [UInt8]] = [:]
                for layer in 0...1 { for system in 0...1 {
                    if let m = try? kb.readKeymap(layer: layer, system: system) { maps[KeymapID(layer: layer, system: system)] = m }
                } }
                let info = try? kb.readInfo()
                return Snapshot(led: led, palette: try? kb.readPalette(), custom: try? kb.readCustom(), maps: maps,
                                battery: try? kb.readBattery(), firmware: info.map { "uuid \($0.uuid) · version \($0.version)" })
            }
            led = snap.led; palette = snap.palette; custom = snap.custom.map(Custom.decode) ?? [:]; keymaps = snap.maps
            battery = snap.battery; firmware = snap.firmware
        } catch {
            show(error)
        }
    }

    // MARK: writing

    /// Run a write on the keyboard, then re-read its state. Stops a running live animation first.
    func perform(_ title: String, refreshAfter: Bool = true, _ op: @escaping @Sendable (AulaKeyboard) throws -> Void) {
        guard let kb = keyboard, !busy else { return }
        stopLive()
        busy = true
        Task {
            do {
                try await onIO { try op(kb) }
                notice = Notice(text: title, isError: false)
                if refreshAfter { await refresh() }
            } catch {
                show(error)
                await refresh()
            }
            busy = false
            let n = notice
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if notice?.id == n?.id { notice = nil }
        }
    }

    /// Switch the keyboard's OS mode (same as Fn+W / Fn+Q / Fn+E).
    func setOSMode(_ mode: Int) {
        guard canWrite, mode != osMode else { return }
        let name = ["Windows", "Android", "Mac"][min(max(mode, 0), 2)]
        perform("\(name) mode") { kb in try kb.updateLED { $0.osMode = mode } }
    }

    // MARK: live animations

    func startLive(_ anim: LiveAnimation, color: RGB, theme: Theme?, brightness: Double) {
        guard let kb = keyboard, kb.connection.canLive else { return }
        stopLive()
        liveRunning = anim
        liveTask = Task.detached(priority: .userInitiated) { [weak self] in
            let start = Date()
            do {
                while !Task.isCancelled {
                    try kb.sendLive(anim.frame(t: Date().timeIntervalSince(start), color: color, theme: theme, brightness: brightness))
                }
            } catch {
                await self?.liveFailed(error)
            }
        }
    }

    func stopLive() {
        liveTask?.cancel(); liveTask = nil; liveRunning = nil
    }

    private func liveFailed(_ error: Error) { liveRunning = nil; show(error) }

    func show(_ error: Error) { notice = Notice(text: error.localizedDescription, isError: true) }

    private func onIO<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            io.async { cont.resume(with: Result { try body() }) }
        }
    }

    /// Discovery doesn't touch the keyboard, so it uses its own queue and never waits behind a write.
    private func onIOQuiet<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async { cont.resume(returning: body()) }
        }
    }
}
