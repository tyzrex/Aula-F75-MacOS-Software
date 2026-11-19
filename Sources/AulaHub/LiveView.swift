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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    KeyboardCanvas(colors: anim.frame(t: tl.date.timeIntervalSinceReferenceDate, color: RGB(color), theme: theme, brightness: brightness),
                                   label: { _ in "" })
                }
                .frame(maxHeight: 300)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    ForEach(LiveAnimation.allCases) { a in
                        Button { anim = a; if model.liveRunning != nil { start() } } label: { Text(a.title).frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(anim == a ? Color.accentColor : .clear, lineWidth: 2))
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        ColorPicker("Accent color", selection: $color, supportsOpacity: false)
                        HStack { Text("Brightness").frame(width: 90, alignment: .leading); Slider(value: $brightness, in: 0.1...1) }
                        if anim == .themeFlow {
                            Picker("Theme", selection: $themeName) { ForEach(Themes.all) { Text($0.name.capitalized).tag($0.name) } }
                        }
                        HStack {
                            if model.liveRunning == nil {
                                Button("Stream to keyboard") { start() }.buttonStyle(.borderedProminent).disabled(model.busy)
                            } else {
                                Button("Stop") { model.stopLive() }.buttonStyle(.borderedProminent).tint(.red)
                                Text("Streaming \(model.liveRunning?.title ?? "")…").foregroundStyle(.secondary)
                            }
                        }
                        Text("Frames are rendered on this Mac and sent 20×/s. Nothing is saved on the keyboard — about 2 seconds after you stop (or quit the app) it returns to its own effect.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(6)
                }
            }
            .padding(20)
        }
        .onChange(of: color) { _ in if model.liveRunning != nil { start() } }
        .onChange(of: brightness) { _ in if model.liveRunning != nil { start() } }
        .onChange(of: themeName) { _ in if model.liveRunning != nil { start() } }
    }

    private func start() { model.startLive(anim, color: RGB(color), theme: theme, brightness: brightness) }
}
