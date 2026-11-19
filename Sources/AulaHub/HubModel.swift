import SwiftUI
import AulaKit

struct Notice: Identifiable { let id = UUID(); let text: String; let isError: Bool }

struct KeymapID: Hashable { var layer: Int; var system: Int }

@MainActor
final class HubModel: ObservableObject {
    @Published var keyboard: AulaKeyboard?
    @Published var connecting = false
    @Published var busy = false
    @Published var notice: Notice?
    @Published var connectError: String?

    @Published var led: LEDConfig?
    @Published var palette: [UInt8]?
    @Published var custom: [Int: RGB] = [:]
    @Published var keymaps: [KeymapID: [UInt8]] = [:]
    @Published var battery: AulaKeyboard.Battery?
    @Published var firmware: String?
    @Published var liveRunning: LiveAnimation?

    private let io = DispatchQueue(label: "aula.io")
    private var liveTask: Task<Void, Never>?

    var isConnected: Bool { keyboard != nil }
    var deviceName: String { keyboard?.info.name ?? "No keyboard" }

    // MARK: connection

    func connect(demo: Bool = false) {
        guard !connecting else { return }
        connecting = true; connectError = nil
        Task {
            do {
                let kb: AulaKeyboard = try await onIO { demo ? AulaKeyboard.demo().0 : try AulaKeyboard.connect() }
                keyboard = kb
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
            var led: LEDConfig; var palette: [UInt8]; var custom: [UInt8]; var maps: [KeymapID: [UInt8]]
            var battery: AulaKeyboard.Battery?; var firmware: String?
        }
        do {
            let snap: Snapshot = try await onIO {
                var maps: [KeymapID: [UInt8]] = [:]
                for layer in 0...1 { for system in 0...1 {
                    if let m = try? kb.readKeymap(layer: layer, system: system) { maps[KeymapID(layer: layer, system: system)] = m }
                } }
                let info = try? kb.readInfo()
                return Snapshot(led: try kb.readLED(), palette: try kb.readPalette(), custom: try kb.readCustom(), maps: maps,
                                battery: try? kb.readBattery(), firmware: info.map { "uuid \($0.uuid) · version \($0.version)" })
            }
            led = snap.led; palette = snap.palette; custom = Custom.decode(snap.custom); keymaps = snap.maps
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

    // MARK: live animations

    func startLive(_ anim: LiveAnimation, color: RGB, theme: Theme?, brightness: Double) {
        guard let kb = keyboard else { return }
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
}
