import SwiftUI
import AulaKit

struct PerKeyView: View {
    @EnvironmentObject var model: HubModel
    @Local private var draft: [Int: RGB] = [:]
    @Local private var paint = Color.cyan
    @Local private var themeName: String?
    @Local private var dirty = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 14) {
                KeyboardCanvas(colors: draft, label: { $0.label },
                               onTap: { paintKey($0) }, onDrag: { paintKey($0) })
                    .frame(maxHeight: 320)
                HStack(spacing: 12) {
                    ColorPicker("Brush", selection: $paint, supportsOpacity: false)
                    Button("Fill all") { draft = Themes.solid(RGB(paint)); mark() }
                    Button("All off") { draft = Themes.solid(.black); mark() }
                    Spacer()
                    Button("Reload from keyboard") { draft = model.custom; dirty = false; themeName = nil }
                    Button("Apply to keyboard") {
                        let raw = Custom.encode(draft)
                        model.perform("Per-key colors applied") { kb in
                            try kb.writeCustom(raw)
                            try kb.setEffect(Effects.customHW)
                        }
                        dirty = false
                    }
                    .buttonStyle(.borderedProminent).disabled(model.busy)
                }
                Text("Click or drag over keys to paint them. Applying switches the keyboard to the Custom effect.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
            Divider()
            themeList.frame(width: 260)
        }
        .onAppear { if draft.isEmpty { draft = model.custom } }
        .onChange(of: model.custom) { c in if !dirty { draft = c } }
    }

    private func mark() { dirty = true; themeName = nil }

    private func paintKey(_ k: KeyInfo) {
        draft[k.index] = RGB(paint); mark()
    }

    private var themeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Themes").font(.headline).padding([.top, .horizontal], 14).padding(.bottom, 8)
            List(Themes.all, selection: Binding(get: { themeName }, set: { n in
                themeName = n
                if let n, let t = Themes.named(n) { draft = t.render(); dirty = true }
            })) { t in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(stops: t.stops.map { .init(color: $0.1.color, location: $0.0) }, startPoint: .leading, endPoint: .trailing))
                        .frame(width: 46, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.name.capitalized).font(.callout)
                        Text(t.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.tag(t.name)
            }
        }
    }
}
