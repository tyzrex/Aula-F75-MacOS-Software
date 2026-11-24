import SwiftUI
import KeylumeKit

@main
struct KeylumeApp: App {
    @StateObject private var model = HubModel()
    @AppStorage(Prefs.menuBar) private var showInMenuBar = true

    var body: some Scene {
        WindowGroup("Keylume") {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    model.start()
                    if CommandLine.arguments.contains("--demo") { model.connect(demo: true) }
                    if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
                        Snapshots.run(into: CommandLine.arguments[i + 1])
                    }
                }
        }
        .defaultSize(width: 1120, height: 760)
        .commands { HubCommands(model: model) }

        MenuBarExtra("Keylume", systemImage: "keyboard", isInserted: $showInMenuBar) {
            MenuBarContent().environmentObject(model)
        }

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

struct HubCommands: Commands {
    @ObservedObject var model: HubModel
    @AppStorage("selectedPane") private var paneName = Pane.overview.rawValue

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .appInfo) {
            Button("About Keylume") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationName: "Keylume",
                    .credits: NSAttributedString(string: "An unofficial configuration app for the AULA F75.\nLighting, per-key RGB, key remapping and backups over USB; viewing and live lighting over 2.4G and Bluetooth.\n\nNot affiliated with AULA. See NOTICE for credits.",
                                                 attributes: [.font: NSFont.systemFont(ofSize: 11)]),
                ])
            }
        }
        CommandGroup(replacing: .help) {
            Button("Copy Diagnostics") { Diagnostics.copy(model) }
            Link("Keylume on GitHub", destination: URL(string: "https://github.com/tyzrex/Aula-F75-MacOS-Software")!)
        }
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(Pane.allCases) { p in
                Button(p.rawValue) { paneName = p.rawValue }.keyboardShortcut(p.shortcut, modifiers: .command)
                    .disabled(!model.isConnected)
            }
        }
        CommandMenu("Keyboard") {
            Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r", modifiers: .command).disabled(!model.isConnected)
            Button("Create Backup") {
                model.perform("Backup saved", refreshAfter: false) { kb in _ = try Backup.capture(from: kb).save() }
            }.keyboardShortcut("b", modifiers: [.command, .shift]).disabled(!model.isConnected)
            Divider()
            Menu("Mode") {
                Button("Windows") { model.setOSMode(0) }.keyboardShortcut("w", modifiers: [.command, .control])
                Button("Mac") { model.setOSMode(2) }.keyboardShortcut("m", modifiers: [.command, .control])
                Button("Android") { model.setOSMode(1) }.keyboardShortcut("a", modifiers: [.command, .control])
            }.disabled(!model.canWrite)
            Menu("Effect") {
                ForEach(Effects.all) { e in
                    Button(e.title) { model.perform("Effect: \(e.title)") { kb in try kb.setEffect(e.hw) } }
                }
            }.disabled(!model.canWrite)
            Divider()
            if model.isConnected {
                Button("Disconnect") { model.disconnect() }
            } else {
                Button("Connect") { model.connect() }.keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: HubModel
    @AppStorage(Prefs.autoConnect) private var autoConnect = true
    @AppStorage(Prefs.legends) private var legends = LegendPreference.auto.rawValue
    @AppStorage(Prefs.menuBar) private var menuBar = true

    var body: some View {
        Form {
            Section("Connection") {
                Toggle("Connect automatically when the keyboard is plugged in", isOn: $autoConnect)
                Text("Only the USB cable connects by itself. The dongle and Bluetooth are contacted only when you press Connect.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Toggle("Show Keylume in the menu bar", isOn: $menuBar)
            }
            Section("Support") {
                Button("Copy diagnostics") { Diagnostics.copy(model) }
                Text("Copies versions and the keyboard's state for a bug report.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Key legends") {
                Picker("Show keys as", selection: $legends) {
                    ForEach(LegendPreference.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text("“Follow keyboard mode” shows ⌘ ⌥ ⌃ ⇧ while the keyboard is in Mac mode.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 460)
        .onChange(of: legends) { _ in model.objectWillChange.send() }
    }
}

/// Quick controls in the menu bar: mode, effect, battery.
struct MenuBarContent: View {
    @EnvironmentObject var model: HubModel

    var body: some View {
        if model.isConnected {
            Text(model.deviceName)
            if let c = model.connection { Text(c.title) }
            if let b = model.battery { Text("Battery \(b.level)%") }
            Divider()
            Menu("Mode") {
                Button("Windows") { model.setOSMode(0) }
                Button("Mac") { model.setOSMode(2) }
                Button("Android") { model.setOSMode(1) }
            }.disabled(!model.canWrite)
            Menu("Effect") {
                ForEach(Effects.all) { e in
                    Button(e.title) { model.perform("Effect: \(e.title)") { kb in try kb.setEffect(e.hw) } }
                }
            }.disabled(!model.canWrite)
        } else {
            Text("No keyboard connected")
            Button("Connect") { model.connect() }
        }
        Divider()
        Button("Open Keylume") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        Button("Quit Keylume") { NSApp.terminate(nil) }
    }
}
