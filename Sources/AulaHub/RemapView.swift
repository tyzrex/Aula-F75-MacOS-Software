import SwiftUI
import AulaKit

struct RemapView: View {
    @EnvironmentObject var model: HubModel
    @Local private var layer = 0
    @Local private var system = 0
    @Local private var selected: KeyInfo?
    @Local private var pending: [Int: KeyEntry] = [:]
    @Local private var confirming = false

    private var id: KeymapID { KeymapID(layer: layer, system: system) }
    private var base: [UInt8]? { model.keymaps[id] }

    private func entry(_ k: KeyInfo) -> KeyEntry? {
        if let p = pending[k.index] { return p }
        guard let base else { return nil }
        return Keymap.entry(base, k.index)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Layer", selection: $layer) { Text("Base").tag(0); Text("Fn").tag(1) }.pickerStyle(.segmented).frame(width: 180)
                Picker("Table", selection: $system) { Text("Windows").tag(0); Text("Mac").tag(1) }.pickerStyle(.segmented).frame(width: 200)
                Spacer()
                Text("Windows/Mac tables are the two key tables the keyboard keeps (Fn+W / Fn+E select the OS mode).")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 320, alignment: .trailing)
            }
            KeyboardCanvas(colors: [:], selection: selected.map { [$0.index] } ?? [],
                           label: { k in entry(k).map(shortLabel) ?? k.label },
                           highlighted: Set(pending.keys), onTap: { selected = $0 })
                .frame(maxHeight: 300)
                .environment(\.colorScheme, .dark)

            if let k = selected, let e = entry(k) {
                GroupBox {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("\(k.label) (matrix #\(k.index))").font(.headline)
                            Text("Currently: \(e.description)  [\(e.hex)]").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        targetMenu(for: k)
                        Button("Undo") { pending[k.index] = nil }.disabled(pending[k.index] == nil)
                    }.padding(6)
                }
            } else {
                Text("Select a key to change what it types.").foregroundStyle(.secondary)
            }

            HStack {
                Button("Write \(pending.count) change\(pending.count == 1 ? "" : "s") to keyboard") { confirming = true }
                    .buttonStyle(.borderedProminent).disabled(pending.isEmpty || model.busy)
                Button("Discard") { pending = [:] }.disabled(pending.isEmpty)
                Text("A full backup is saved automatically before every keymap write, and the write is read back and checked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .onChange(of: layer) { _ in pending = [:] }
        .onChange(of: system) { _ in pending = [:] }
        .confirmationDialog("Write keymap changes?", isPresented: $confirming) {
            Button("Write") { write() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This changes what keys type on the \(layer == 0 ? "base" : "Fn") layer, \(system == 0 ? "Windows" : "Mac") table. A backup is saved first.") }
    }

    private func shortLabel(_ e: KeyEntry) -> String {
        let d = e.description
        return d.count > 8 ? String(d.prefix(7)) + "…" : d
    }

    private func write() {
        guard var km = base else { return }
        for (i, e) in pending { km = Keymap.setting(km, i, to: e) }
        let l = layer, s = system, final = km
        pending = [:]
        model.perform("Keymap written") { kb in
            _ = try Backup.capture(from: kb).save(name: "before-remap")
            try kb.writeKeymap(final, layer: l, system: s)
        }
    }

    private func targetMenu(for k: KeyInfo) -> some View {
        Menu {
            Button("Disabled (no action)") { pending[k.index] = .disabled }
            Menu("Letters") { ForEach("abcdefghijklmnopqrstuvwxyz".map(String.init), id: \.self) { item($0, k) } }
            Menu("Numbers") { ForEach((1...9).map(String.init) + ["0"], id: \.self) { item($0, k) } }
            Menu("Function keys") { ForEach((1...12).map { "f\($0)" }, id: \.self) { item($0, k) } }
            Menu("Modifiers") { ForEach(Keymap.modifiers.keys.sorted(), id: \.self) { item($0, k) } }
            Menu("Media") { ForEach(Keymap.consumer.keys.sorted(), id: \.self) { item($0, k) } }
            Menu("Navigation & editing") {
                ForEach(["enter", "esc", "backspace", "tab", "space", "capslock", "insert", "delete", "home", "end", "pgup", "pgdn", "up", "down", "left", "right", "printscreen", "scrolllock", "pause", "menu"], id: \.self) { item($0, k) }
            }
            Menu("Symbols") {
                ForEach(["minus", "equal", "lbracket", "rbracket", "backslash", "semicolon", "quote", "grave", "comma", "period", "slash"], id: \.self) { item($0, k) }
            }
        } label: {
            Text("Change to…")
        }
        .menuStyle(.borderedButton).fixedSize()
    }

    private func item(_ name: String, _ k: KeyInfo) -> some View {
        Button(Keymap.display(name)) { if let t = Keymap.target(named: name) { pending[k.index] = t } }
    }
}
