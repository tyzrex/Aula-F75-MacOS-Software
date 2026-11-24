import SwiftUI
import KeylumeKit

struct RemapView: View {
    @EnvironmentObject var model: HubModel
    @Local private var layer = 0
    @Local private var system = 0
    @Local private var followed = false
    @Local private var selected: KeyInfo?
    @Local private var pending: [Int: KeyEntry] = [:]
    @Local private var confirming = false

    private var id: KeymapID { KeymapID(layer: layer, system: system) }
    private var base: [UInt8]? { model.keymaps[id] }
    private var flavor: Flavor { system == 1 ? .mac : .windows }
    private var editable: Bool { model.canWrite && !model.busy }

    private func entry(_ k: KeyInfo) -> KeyEntry? {
        if let p = pending[k.index] { return p }
        guard let base else { return nil }
        return Keymap.entry(base, k.index)
    }

    var body: some View {
        Screen("Key Remap", subtitle: "Change what each key types. The keyboard keeps separate Windows and Mac tables.") {
            Card {
                HStack(spacing: 14) {
                    Picker("Layer", selection: $layer) { Text("Base").tag(0); Text("Fn layer").tag(1) }
                        .pickerStyle(.segmented).frame(width: 190)
                    Picker("Table", selection: $system) { Text("Windows").tag(0); Text("Mac").tag(1) }
                        .pickerStyle(.segmented).frame(width: 200)
                    Spacer()
                    if model.osMode == 2 && system == 1 || model.osMode != 2 && system == 0 {
                        Pill(text: "Active table", systemImage: "checkmark.circle.fill", tint: .green)
                    }
                }
                if base == nil {
                    Banner(systemImage: "exclamationmark.triangle", text: "This table can't be read over \(model.connection?.title ?? "this connection"). Connect the USB cable to see the Mac table.")
                } else {
                    KeyboardCanvas(flavor: flavor, selection: selected.map { [$0.index] } ?? [], highlighted: Set(pending.keys),
                                   legend: { k in entry(k).map { Legends.entry($0, flavor: flavor) } ?? Legends.physical(k, flavor: flavor) },
                                   onTap: { selected = $0 })
                        .frame(maxWidth: .infinity)
                }
            }

            inspector

            if layer == 0 { presets }

            HStack {
                Button { confirming = true } label: { Label("Write \(pending.count) change\(pending.count == 1 ? "" : "s")", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent).disabled(pending.isEmpty || !editable)
                Button("Discard") { pending = [:] }.disabled(pending.isEmpty)
                Text("A full backup is saved automatically before every keymap write, and the write is read back and checked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { if !followed { system = model.osMode == 2 ? 1 : 0; followed = true } }
        .onChange(of: layer) { _ in pending = [:] }
        .onChange(of: system) { _ in pending = [:] }
        .confirmationDialog("Write keymap changes?", isPresented: $confirming) {
            Button("Write") { write() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This changes what keys type on the \(layer == 0 ? "base" : "Fn") layer, \(system == 0 ? "Windows" : "Mac") table. A backup is saved first.") }
    }

    @ViewBuilder private var inspector: some View {
        Card("Selected key", systemImage: "cursorarrow.click") {
            if let k = selected, let e = entry(k) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(Legends.physical(k, flavor: flavor).main) · \(k.name)").font(.headline)
                        Text("Does: \(e.description)").foregroundStyle(.secondary)
                        Text("matrix #\(k.index)  [\(e.hex)]").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    targetMenu(for: k).disabled(!editable)
                    Button("Undo") { pending[k.index] = nil }.disabled(pending[k.index] == nil)
                }
            } else {
                Text("Click a key above to change what it types.").foregroundStyle(.secondary)
            }
        }
    }

    private var presets: some View {
        Card("Quick changes", subtitle: "Applied to the pending list — nothing is written until you confirm", systemImage: "wand.and.stars") {
            HStack(spacing: 10) {
                Button { swapAltWin() } label: { Label("Mac modifier order (⌥ ⌘)", systemImage: "arrow.left.arrow.right") }
                    .help("Swap Alt and Win so the keys read Ctrl ⌥ ⌘, like a Mac keyboard")
                Button { capsAs("lctrl") } label: { Label("Caps Lock → Control", systemImage: "control") }
                Button { capsAs("esc") } label: { Label("Caps Lock → Escape", systemImage: "escape") }
                Spacer()
            }
            .disabled(base == nil || !editable)
        }
    }

    private func swapAltWin() {
        guard let alt = Layout.byName["lalt"], let win = Layout.byName["lwin"], let a = entry(alt), let w = entry(win) else { return }
        pending[alt.index] = w; pending[win.index] = a
    }

    private func capsAs(_ name: String) {
        guard let caps = Layout.byName["capslock"], let t = Keymap.target(named: name) else { return }
        pending[caps.index] = t
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
            Label("Change to…", systemImage: "pencil")
        }
        .menuStyle(.borderedButton).fixedSize()
    }

    private func item(_ name: String, _ k: KeyInfo) -> some View {
        Button(system == 1 ? macName(name) : Keymap.display(name)) { if let t = Keymap.target(named: name) { pending[k.index] = t } }
    }

    private func macName(_ name: String) -> String {
        switch name {
        case "lwin": return "L Command ⌘"; case "rwin": return "R Command ⌘"
        case "lalt": return "L Option ⌥"; case "ralt": return "R Option ⌥"
        case "lctrl": return "L Control ⌃"; case "rctrl": return "R Control ⌃"
        default: return Keymap.display(name)
        }
    }
}
