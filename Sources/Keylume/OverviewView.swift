import SwiftUI
import KeylumeKit

/// The current lighting drawn on the keyboard, animated like the real effect (an approximation).
struct LEDPreview: View {
    var led: LEDConfig?
    var palette: [UInt8]?
    var custom: [Int: RGB]
    var flavor: Flavor
    var showLegends = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            KeyboardCanvas(colors: colors(t), flavor: flavor, showLegends: showLegends)
        }
    }

    private func colors(_ t: Double) -> [Int: RGB] {
        guard let led else { return [:] }
        if led.effect == Effects.customHW { return custom }
        return EffectPreview.frame(led, t: t, palette: (palette?.isEmpty ?? true) ? nil : palette) ?? [:]
    }
}

struct OverviewView: View {
    @EnvironmentObject var model: HubModel
    @Local private var brightness = 5.0

    private var effect: Effect? { model.led.flatMap { Effects.byHW($0.effect) } }

    var body: some View {
        Screen("Your F75", subtitle: effectLine) {
            Card {
                LEDPreview(led: model.led, palette: model.palette, custom: model.custom, flavor: model.flavor)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    if let c = model.connection { Pill(text: c.title, systemImage: c.symbol, tint: c.canWrite ? .green : .orange) }
                    Pill(text: ["Windows", "Android", "Mac"][min(model.osMode, 2)] + " mode", systemImage: model.osMode == 2 ? "apple.logo" : "rectangle.grid.2x2", tint: .accentColor)
                    if let b = model.battery { BatteryBadge(battery: b) }
                    if let f = model.firmware { Pill(text: f, systemImage: "cpu") }
                    Spacer()
                    Text("Preview is approximate").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                modeCard
                brightnessCard
                effectCard
                hardwareCard
            }
        }
        .onAppear(perform: syncBrightness)
        .onChange(of: model.led) { _ in syncBrightness() }
    }

    private var effectLine: String {
        guard let e = effect else { return "Reading the keyboard…" }
        return "Lighting: \(e.title)"
    }

    private func syncBrightness() {
        if let l = model.led, let s = l.slot(l.effect) { brightness = Double(s.brightness) }
    }

    private var modeCard: some View {
        Card("Keyboard mode", subtitle: "Same as Fn+W, Fn+E and Fn+Q on the keyboard", systemImage: "apple.logo", stretch: true) {
            Picker("Mode", selection: Binding(get: { model.osMode }, set: { model.setOSMode($0) })) {
                Text("Windows").tag(0); Text("Mac").tag(2); Text("Android").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().disabled(!model.canWrite || model.busy)
            Text(model.osMode == 2
                 ? "Mac mode: the keyboard uses its Mac key table. The Win key is ⌘ Command and Alt is ⌥ Option."
                 : "Windows mode uses the standard Windows key table. Switch to Mac mode if this keyboard is on a Mac.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var brightnessCard: some View {
        Card("Brightness", subtitle: effect.map { "For \($0.title)" }, systemImage: "sun.max", stretch: true) {
            let hasSlot = model.led.flatMap { $0.slot($0.effect) } != nil && effect?.hw != Effects.customHW
            HStack {
                Image(systemName: "sun.min").foregroundStyle(.secondary)
                Slider(value: $brightness, in: 0...9, step: 1) { editing in
                    if !editing { applyBrightness() }
                }
                .disabled(!hasSlot || !model.canWrite || model.busy)
                Image(systemName: "sun.max").foregroundStyle(.secondary)
            }
            if !hasSlot { Text("The custom effect uses the colors you painted.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func applyBrightness() {
        guard let l = model.led, var s = l.slot(l.effect), Int(brightness) != s.brightness else { return }
        s.brightness = Int(brightness)
        let hw = l.effect, slot = s
        model.perform("Brightness \(slot.brightness)") { kb in try kb.updateLED { try $0.setSlot(hw, slot) } }
    }

    private var effectCard: some View {
        Card("Effect", subtitle: "Pick a built-in effect", systemImage: "lightbulb.led", stretch: true) {
            Picker("Effect", selection: Binding(get: { model.led?.effect ?? 1 }, set: { hw in
                model.perform("Effect: \(Effects.byHW(hw)?.title ?? "")") { kb in try kb.setEffect(hw) }
            })) {
                ForEach(Effects.all) { e in Label(e.title, systemImage: e.symbol).tag(e.hw) }
            }
            .labelsHidden().disabled(!model.canWrite || model.busy)
            Text("More controls — speed, color, palettes — are on the Lighting page.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var hardwareCard: some View {
        Card("Side light & knob", systemImage: "dial.medium", stretch: true) {
            HStack {
                Text("Side light").frame(width: 80, alignment: .leading)
                Picker("Side light", selection: Binding(get: { model.led?.sideMode ?? 0 }, set: { v in
                    model.perform("Side light: \(Names.sideModes[v])") { kb in try kb.updateLED { $0.sideMode = v } }
                })) { ForEach(0..<Names.sideModes.count, id: \.self) { Text(Names.sideModes[$0].capitalized).tag($0) } }
                    .labelsHidden().disabled(!model.canWrite || model.busy)
            }
            HStack {
                Text("Knob").frame(width: 80, alignment: .leading)
                Picker("Knob", selection: Binding(get: { model.led?.knobMode ?? 0 }, set: { v in
                    model.perform("Knob: \(Names.knobModes[v])") { kb in try kb.updateLED { $0.knobMode = v } }
                })) { Text("Volume").tag(0); Text("Lighting").tag(1) }
                    .pickerStyle(.segmented).labelsHidden().disabled(!model.canWrite || model.busy)
            }
        }
    }
}
