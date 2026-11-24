import SwiftUI
import KeylumeKit

struct PerKeyView: View {
    @EnvironmentObject var model: HubModel
    @Local private var draft: [Int: RGB] = [:]
    @Local private var paint = Color.cyan
    @Local private var themeName: String?
    @Local private var dirty = false
    @Local private var undoStack: [[Int: RGB]] = []
    @Local private var redoStack: [[Int: RGB]] = []
    @Local private var lastPush = Date.distantPast

    private var editable: Bool { model.canWrite && !model.busy }

    var body: some View {
        Screen("Per-Key RGB", subtitle: "Paint every key. Stored on the keyboard as the Custom effect.") {
            Card {
                KeyboardCanvas(colors: draft, flavor: model.flavor, onTap: { paintKey($0) }, onDrag: { paintKey($0) })
                    .frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    ColorPicker("Brush", selection: $paint, supportsOpacity: false)
                    Button("Fill all") { checkpoint(force: true); draft = Themes.solid(RGB(paint)); mark() }
                    Button("All off") { checkpoint(force: true); draft = Themes.solid(.black); mark() }
                    Spacer()
                    Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .keyboardShortcut("z", modifiers: .command).disabled(undoStack.isEmpty).help("Undo (⌘Z)")
                    Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(redoStack.isEmpty).help("Redo (⇧⌘Z)")
                    Button("Reload") { draft = model.custom; dirty = false; themeName = nil }.disabled(!dirty)
                    Button {
                        let raw = Custom.encode(draft)
                        model.perform("Per-key colors applied") { kb in try kb.showCustom(raw) }
                        dirty = false
                    } label: { Label("Apply to keyboard", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).disabled(!editable)
                }
                Text("Click or drag over keys to paint them. Applying switches the keyboard to the Custom effect; it goes dark for a moment while it repaints.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Card("Themes", subtitle: "A starting point — you can keep painting afterwards", systemImage: "paintpalette") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(Themes.all) { t in themeTile(t) }
                }
            }
        }
        .onAppear { if draft.isEmpty { draft = model.custom } }
        .onChange(of: model.custom) { c in if !dirty { draft = c } }
    }

    private func mark() { dirty = true; themeName = nil }

    /// Remember the picture before a change. A drag over many keys counts as one change.
    private func checkpoint(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastPush) > 0.6 else { lastPush = Date(); return }
        undoStack.append(draft); if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []; lastPush = Date()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(draft); draft = previous; dirty = true; themeName = nil
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(draft); draft = next; dirty = true; themeName = nil
    }

    private func paintKey(_ k: KeyInfo) {
        checkpoint()
        draft[k.index] = RGB(paint); mark()
    }

    private func themeTile(_ t: Theme) -> some View {
        Button {
            checkpoint(force: true); themeName = t.name; draft = t.render(); dirty = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(stops: t.stops.map { .init(color: $0.1.color, location: $0.0) }, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 26)
                Text(t.name.capitalized).font(.callout.weight(.medium))
                Text(t.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(themeName == t.name ? 0.10 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(themeName == t.name ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: themeName == t.name ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}
