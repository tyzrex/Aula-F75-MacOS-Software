import SwiftUI
import AulaKit

struct LiveView: View {
    @EnvironmentObject var model: HubModel
    @Local private var anim: LiveAnimation = .rainbowWave
    @Local private var color = Color(red: 0, green: 0.63, blue: 1)
    @Local private var brightness = 1.0
    @Local private var themeName = Themes.all[0].name

    private var theme: Theme? { Themes.named(themeName) }

    var body: some View {
        Screen("Live Animations", subtitle: "Animated lighting rendered on this Mac and streamed to the keyboard") {
            if !model.canLive {
                Banner(systemImage: "wave.3.right", text: "Live lighting isn't available over \(model.connection?.title ?? "this connection"). Use the USB cable or the 2.4G dongle.")
            } else if model.connection == .dongle {
                Banner(systemImage: "info.circle", text: "Over the dongle, live frames show while the keyboard's lighting is set to Custom. Pick “Custom” on the keyboard (Fn + \\ cycles effects) or set it over the cable once.", tint: .blue)
            }
            Card {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    KeyboardCanvas(colors: anim.frame(t: tl.date.timeIntervalSinceReferenceDate, color: RGB(color), theme: theme, brightness: brightness),
                                   flavor: model.flavor)
                }
                .frame(maxWidth: .infinity)
            }
            Card("Animation", systemImage: "sparkles") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                    ForEach(LiveAnimation.allCases) { a in
                        Tile(title: a.title, systemImage: a.symbol, selected: anim == a, badge: nil) { anim = a; if model.liveRunning != nil { start() } }
                    }
                }
                ColorPicker("Accent color", selection: $color, supportsOpacity: false)
                SettingRow(title: "Brightness") { Slider(value: $brightness, in: 0.1...1) }
                if anim == .themeFlow {
                    Picker("Theme", selection: $themeName) { ForEach(Themes.all) { Text($0.name.capitalized).tag($0.name) } }
                }
                HStack {
                    if model.liveRunning == nil {
                        Button { start() } label: { Label("Stream to keyboard", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).disabled(model.busy || !model.canLive)
                    } else {
                        Button { model.stopLive() } label: { Label("Stop", systemImage: "stop.fill") }
                            .buttonStyle(.borderedProminent).tint(.red)
                        Text("Streaming \(model.liveRunning?.title ?? "")…").foregroundStyle(.secondary)
                    }
                }
                Text("Nothing is saved on the keyboard — about 2 seconds after you stop (or quit the app) it returns to its own effect.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: color) { _ in if model.liveRunning != nil { start() } }
        .onChange(of: brightness) { _ in if model.liveRunning != nil { start() } }
        .onChange(of: themeName) { _ in if model.liveRunning != nil { start() } }
    }

    private func start() { model.startLive(anim, color: RGB(color), theme: theme, brightness: brightness) }
}
