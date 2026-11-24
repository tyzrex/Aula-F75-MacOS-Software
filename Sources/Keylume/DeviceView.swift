import SwiftUI
import KeylumeKit

struct DeviceView: View {
    @EnvironmentObject var model: HubModel
    @Local private var side = 0
    @Local private var knob = 0
    @Local private var os = 0
    @Local private var winLock = false
    @Local private var sleep = 60

    private var changed: Bool {
        guard let l = model.led else { return false }
        return l.sideMode != side || l.knobMode != knob || l.osMode != os || l.winLock != winLock || l.sleep != sleep
    }
    private var editable: Bool { model.canWrite && !model.busy }

    var body: some View {
        Form {
            Section("Keyboard") {
                LabeledContent("Device", value: model.deviceName)
                if let c = model.connection { LabeledContent("Connection") { Label(c.title, systemImage: c.symbol) } }
                if let f = model.firmware { LabeledContent("Firmware", value: f) }
                if let b = model.battery { LabeledContent("Battery", value: "\(b.level)%\(b.charging ? " (charging)" : "")\(b.full ? " (full)" : "")") }
            }
            Section {
                Picker("Mode", selection: $os) {
                    Text("Windows").tag(0); Text("Mac").tag(2); Text("Android").tag(1)
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $winLock) { Text("Lock the \(os == 2 ? "Command" : "Windows") key") }
                Text(os == 2
                     ? "Mac mode (Fn+E): the keyboard uses its Mac key table — Win sends ⌘ Command and Alt sends ⌥ Option. Legends in this app switch to Mac symbols."
                     : "Windows mode (Fn+W) uses the Windows key table. Android mode is Fn+Q.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Operating system") }
            Section("Hardware") {
                Picker("Side light", selection: $side) { ForEach(0..<Names.sideModes.count, id: \.self) { Text(Names.sideModes[$0].capitalized).tag($0) } }
                Picker("Knob", selection: $knob) {
                    Text("Media (volume / mute)").tag(0); Text("Lighting (brightness / next effect)").tag(1)
                }
                Picker("Sleep after", selection: $sleep) {
                    ForEach(Names.sleepChoices, id: \.self) { Text(Names.sleepText($0)).tag($0) }
                    if !Names.sleepChoices.contains(sleep) && sleep != 0 { Text(Names.sleepText(sleep)).tag(sleep) }
                    if sleep == 0 { Text("never (not allowed)").tag(0) }
                }
                Text("Sleep applies when running wirelessly. “Never” is refused — it drains the battery with the lights on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Apply settings") {
                        let (s, k, o, w, z) = (side, knob, os, winLock, sleep)
                        model.perform("Settings applied") { kb in
                            try kb.updateLED { cfg in
                                cfg.sideMode = s; cfg.knobMode = k; cfg.osMode = o; cfg.winLock = w
                                try cfg.setSleep(z)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent).disabled(!changed || !editable || sleep == 0)
                    Button("Revert", action: load).disabled(!changed)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!model.canWrite && !model.isDemo)
        .onAppear(perform: load)
        .onChange(of: model.led) { _ in load() }
    }

    private func load() {
        guard let l = model.led else { return }
        side = l.sideMode; knob = l.knobMode; os = l.osMode; winLock = l.winLock; sleep = l.sleep
    }
}

struct BackupsView: View {
    @EnvironmentObject var model: HubModel
    @Local private var files: [URL] = Backup.list()
    @Local private var restoring: URL?
    @Local private var includeKeymap = false

    var body: some View {
        Screen("Backups", subtitle: "Snapshots of lighting, palettes, per-key colors and key tables") {
            Card {
                HStack {
                    Button { create() } label: { Label("Create backup now", systemImage: "externaldrive.badge.plus") }
                        .buttonStyle(.borderedProminent).disabled(model.busy)
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: Backup.directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(Backup.directory)
                    }
                    Spacer()
                    Toggle("Also restore key mappings", isOn: $includeKeymap).toggleStyle(.checkbox).disabled(!model.canWrite)
                }
                if files.isEmpty {
                    Text("No backups yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    VStack(spacing: 0) {
                        ForEach(files, id: \.self) { url in
                            row(url)
                            if url != files.last { Divider() }
                        }
                    }
                }
                Text("Restoring needs the USB cable. A backup holds lighting, effect palettes, per-key colors and the key tables the keyboard allows reading.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { files = Backup.list() }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Restore") {
                if let url = restoring {
                    let km = includeKeymap
                    model.perform("Backup restored") { kb in try Backup.load(url).restore(to: kb, includeKeymap: km) }
                }
                restoring = nil
            }
            Button("Cancel", role: .cancel) { restoring = nil }
        } message: { Text("This overwrites the keyboard's current lighting\(includeKeymap ? ", palettes and key mappings" : " and palettes").") }
    }

    private func create() {
        model.perform("Backup saved", refreshAfter: false) { kb in _ = try Backup.capture(from: kb).save() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { files = Backup.list() }
    }

    private func row(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                if let b = try? Backup.load(url) {
                    Text("\(b.device) · \(b.created.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Restore…") { restoring = url }.disabled(!model.canWrite || model.busy)
        }
        .padding(.vertical, 8)
    }
}
