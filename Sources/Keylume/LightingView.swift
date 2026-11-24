import SwiftUI
import KeylumeKit

struct LightingView: View {
    @EnvironmentObject var model: HubModel
    @Local private var effect = 1
    @Local private var slot = EffectSlot(brightness: 5, speed: 2, color: 6)
    @Local private var draftPalette: [UInt8] = []

    private var current: Effect? { Effects.byHW(effect) }
    private var editable: Bool { model.canWrite && !model.busy }

    private var draftLED: LEDConfig? {
        guard var cfg = model.led else { return nil }
        cfg.effect = effect
        try? cfg.setSlot(effect, slot)
        return cfg
    }

    private var dirty: Bool {
        guard let l = model.led else { return false }
        if l.effect != effect { return true }
        return effect != Effects.customHW && l.slot(effect) != slot
    }

    var body: some View {
        Screen("Lighting", subtitle: "Built-in effects, stored on the keyboard") {
            Card {
                LEDPreview(led: draftLED, palette: draftPalette, custom: model.custom, flavor: model.flavor)
                    .frame(maxWidth: .infinity)
                Text("Preview is approximate — the keyboard's own firmware draws the real effect.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Card("Effect", systemImage: "lightbulb.led") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                    ForEach(Effects.all) { e in
                        Tile(title: e.title, systemImage: e.symbol, selected: effect == e.hw, badge: e.reactsToKeys ? "KEYS" : nil) { effect = e.hw }
                    }
                }
                if effect == Effects.customHW {
                    Text("“Custom” shows the per-key colors from the Per-Key RGB page.").font(.caption).foregroundStyle(.secondary)
                }
            }
            controls
            if let e = current, e.hasColor { paletteEditor(e) }
        }
        .onAppear(perform: load)
        .onChange(of: model.led) { _ in load() }
        .onChange(of: effect) { hw in if let s = model.led?.slot(hw) { slot = s } }
    }

    private func load() {
        guard let led = model.led else { return }
        effect = led.effect
        if let s = led.slot(led.effect) { slot = s }
        if let p = model.palette { draftPalette = p }
    }

    private var controls: some View {
        Card("Adjust", systemImage: "slider.horizontal.3") {
            if effect != Effects.customHW {
                SettingRow(title: "Brightness") {
                    Slider(value: Binding(get: { Double(slot.brightness) }, set: { slot.brightness = Int($0.rounded()) }), in: 0...9, step: 1)
                    Text("\(slot.brightness)").monospacedDigit().frame(width: 24)
                }
                if current?.hasSpeed == true {
                    SettingRow(title: "Speed") {
                        Slider(value: Binding(get: { Double(slot.speed) }, set: { slot.speed = Int($0.rounded()) }), in: 0...4, step: 1)
                        Text("\(slot.speed)").monospacedDigit().frame(width: 24)
                    }
                }
                if current?.hasColor == true {
                    SettingRow(title: "Color") {
                        HStack(spacing: 8) { ForEach(0..<8, id: \.self) { i in swatch(i) } }
                        Spacer(minLength: 0)
                    }
                }
            }
            HStack {
                Button {
                    let hw = effect, s = slot
                    model.perform("Effect applied") { kb in
                        try kb.updateLED { cfg in
                            cfg.effect = hw
                            if cfg.slot(hw) != nil, hw != Effects.customHW { try cfg.setSlot(hw, s) }
                        }
                    }
                } label: { Label("Apply to keyboard", systemImage: "checkmark") }
                .buttonStyle(.borderedProminent).disabled(!editable || !dirty)
                Button("Revert", action: load).disabled(!dirty)
                Text("The keyboard blinks once when the lighting is written.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func swatchColor(_ i: Int) -> Color {
        if i == 7 { return Color(.sRGB, red: 0.6, green: 0.4, blue: 0.9, opacity: 1) }
        if let p = draftPalette.isEmpty ? nil : Palette.color(draftPalette, hw: effect, color: i) { return p.color }
        return Palette.factory[i].color
    }

    private func swatch(_ i: Int) -> some View {
        Button { slot.color = i } label: {
            ZStack {
                if i == 7 {
                    Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                } else { Circle().fill(swatchColor(i)) }
            }
            .frame(width: 24, height: 24)
            .overlay(Circle().strokeBorder(slot.color == i ? Color.primary : Color.primary.opacity(0.2), lineWidth: slot.color == i ? 2.5 : 1))
            .padding(2)
        }
        .buttonStyle(.plain).help(Names.colors[i].capitalized)
    }

    private func paletteEditor(_ e: Effect) -> some View {
        Card("Palette — “\(e.title)”", subtitle: "What this effect's seven color choices really are", systemImage: "eyedropper") {
            if e.hw >= Palette.count {
                Text("This effect has no palette.").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    ForEach(0..<Palette.colors, id: \.self) { i in
                        VStack(spacing: 4) {
                            ColorPicker("", selection: Binding(
                                get: { (Palette.color(draftPalette, hw: e.hw, color: i) ?? Palette.factory[i]).color },
                                set: { c in if let p = try? Palette.setting(draftPalette, hw: e.hw, color: i, to: RGB(c)) { draftPalette = p } }
                            ), supportsOpacity: false).labelsHidden()
                            Text(Names.colors[i].capitalized).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Button("Write palette") {
                        let p = draftPalette
                        model.perform("Palette written") { kb in try kb.writePalette(p) }
                    }.disabled(!editable || draftPalette.isEmpty || draftPalette == model.palette)
                    Button("Reset to factory") {
                        if let p = try? Palette.reset(draftPalette, hw: e.hw) { draftPalette = p }
                    }
                    Button("Revert") { if let p = model.palette { draftPalette = p } }.disabled(draftPalette == model.palette)
                }
            }
        }
    }
}
