import SwiftUI
import AulaKit

struct LightingView: View {
    @EnvironmentObject var model: HubModel
    @Local private var effect = 1
    @Local private var slot = EffectSlot(brightness: 5, speed: 2, color: 6)
    @Local private var draftPalette: [UInt8] = []
    @Local private var loaded = false

    private var current: Effect? { Effects.byHW(effect) }

    private var draftLED: LEDConfig? {
        guard var cfg = model.led else { return nil }
        cfg.effect = effect
        try? cfg.setSlot(effect, slot)
        return cfg
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                effectGrid
                controls
                if let e = current, e.hasColor { paletteEditor(e) }
            }
            .padding(20)
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

    private var preview: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let colors: [Int: RGB] = {
                if effect == Effects.customHW { return model.custom }
                guard let cfg = draftLED else { return [:] }
                return EffectPreview.frame(cfg, t: t, palette: draftPalette.isEmpty ? nil : draftPalette) ?? [:]
            }()
            KeyboardCanvas(colors: colors, label: { _ in "" })
        }
        .frame(maxHeight: 300)
        .overlay(alignment: .topTrailing) {
            Text("Preview is approximate").font(.caption2).foregroundStyle(.secondary).padding(6)
        }
    }

    private var effectGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effect").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(Effects.all) { e in
                    Button { effect = e.hw } label: {
                        Text(e.title).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(effect == e.hw ? .accentColor : nil)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(effect == e.hw ? Color.accentColor : .clear, lineWidth: 2))
                }
            }
            if effect == Effects.customHW {
                Text("“Custom” shows the per-key colors from the Per-Key RGB page.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if effect != Effects.customHW {
                    HStack {
                        Text("Brightness").frame(width: 90, alignment: .leading)
                        Slider(value: Binding(get: { Double(slot.brightness) }, set: { slot.brightness = Int($0.rounded()) }), in: 0...9, step: 1)
                        Text("\(slot.brightness)").monospacedDigit().frame(width: 24)
                    }
                    if current?.hasSpeed == true {
                        HStack {
                            Text("Speed").frame(width: 90, alignment: .leading)
                            Slider(value: Binding(get: { Double(slot.speed) }, set: { slot.speed = Int($0.rounded()) }), in: 0...4, step: 1)
                            Text("\(slot.speed)").monospacedDigit().frame(width: 24)
                        }
                    }
                    if current?.hasColor == true {
                        HStack {
                            Text("Color").frame(width: 90, alignment: .leading)
                            ForEach(0..<8, id: \.self) { i in swatch(i) }
                            Spacer()
                        }
                    }
                }
                HStack {
                    Button("Apply to keyboard") {
                        let hw = effect, s = slot
                        model.perform("Effect applied") { kb in
                            try kb.updateLED { cfg in
                                cfg.effect = hw
                                if cfg.slot(hw) != nil, hw != Effects.customHW { try cfg.setSlot(hw, s) }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent).disabled(model.busy)
                    Text("The keyboard blinks once when the lighting is written.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(6)
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
            .overlay(Circle().stroke(slot.color == i ? Color.white : Color.gray.opacity(0.5), lineWidth: slot.color == i ? 3 : 1))
        }
        .buttonStyle(.plain).help(Names.colors[i])
    }

    private func paletteEditor(_ e: Effect) -> some View {
        GroupBox("Palette for “\(e.title)” — what the 7 color choices actually are") {
            VStack(alignment: .leading, spacing: 10) {
                if e.hw >= Palette.count {
                    Text("This effect has no palette.").foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 14) {
                        ForEach(0..<Palette.colors, id: \.self) { i in
                            VStack(spacing: 4) {
                                ColorPicker("", selection: Binding(
                                    get: { (Palette.color(draftPalette, hw: e.hw, color: i) ?? Palette.factory[i]).color },
                                    set: { c in if let p = try? Palette.setting(draftPalette, hw: e.hw, color: i, to: RGB(c)) { draftPalette = p } }
                                ), supportsOpacity: false).labelsHidden()
                                Text(Names.colors[i]).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Button("Write palette") {
                            let p = draftPalette
                            model.perform("Palette written") { kb in try kb.writePalette(p) }
                        }.disabled(model.busy || draftPalette.isEmpty || draftPalette == model.palette)
                        Button("Reset to factory") {
                            if let p = try? Palette.reset(draftPalette, hw: e.hw) { draftPalette = p }
                        }
                        Button("Revert") { if let p = model.palette { draftPalette = p } }.disabled(draftPalette == model.palette)
                    }
                }
            }.padding(6)
        }
    }
}
