import SwiftUI
import AulaKit

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Keyboard", lighting = "Lighting", perKey = "Per-Key RGB", live = "Live Animations"
    case remap = "Key Remap", device = "Settings", backups = "Backups"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "keyboard"
        case .lighting: return "lightbulb.led"
        case .perKey: return "paintpalette"
        case .live: return "sparkles"
        case .remap: return "command"
        case .device: return "slider.horizontal.3"
        case .backups: return "externaldrive"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .overview: return "1"; case .lighting: return "2"; case .perKey: return "3"; case .live: return "4"
        case .remap: return "5"; case .device: return "6"; case .backups: return "7"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: HubModel
    @AppStorage("selectedPane") private var paneName = Pane.overview.rawValue

    private var pane: Pane { Pane(rawValue: paneName) ?? .overview }
    private var selection: Binding<Pane?> { Binding(get: { pane }, set: { if let p = $0 { paneName = p.rawValue } }) }

    var body: some View {
        Group {
            if model.isConnected {
                NavigationSplitView {
                    List(selection: selection) {
                        Section("Device") { row(.overview) }
                        Section("Customize") { row(.lighting); row(.perKey); row(.live) }
                        Section("Keys") { row(.remap) }
                        Section("Manage") { row(.device); row(.backups) }
                    }
                    .listStyle(.sidebar)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
                    .safeAreaInset(edge: .bottom) { SidebarFooter() }
                } detail: {
                    VStack(spacing: 0) {
                        if !model.canWrite && !model.isDemo { ReadOnlyBar() }
                        switch pane {
                        case .overview: OverviewView()
                        case .lighting: LightingView()
                        case .perKey: PerKeyView()
                        case .live: LiveView()
                        case .remap: RemapView()
                        case .device: DeviceView()
                        case .backups: BackupsView()
                        }
                        if let n = model.notice { NoticeBar(notice: n) }
                    }
                    .navigationTitle(pane.rawValue)
                    .navigationSubtitle(model.deviceName)
                    .toolbar { HubToolbar() }
                }
            } else {
                ConnectView()
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .animation(.easeInOut(duration: 0.2), value: model.notice?.id)
    }

    private func row(_ p: Pane) -> some View {
        Label(p.rawValue, systemImage: p.icon).tag(p)
    }
}

// MARK: - Toolbar

struct HubToolbar: ToolbarContent {
    @EnvironmentObject var model: HubModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Mode", selection: Binding(get: { model.osMode }, set: { model.setOSMode($0) })) {
                Label("Windows", systemImage: "rectangle.grid.2x2").tag(0)
                Label("Mac", systemImage: "apple.logo").tag(2)
                Label("Android", systemImage: "candybarphone").tag(1)
            }
            .pickerStyle(.menu)
            .disabled(!model.canWrite || model.busy)
            .help(model.canWrite ? "Keyboard mode (the same as Fn+W, Fn+E, Fn+Q)" : "Changing the mode needs the USB cable")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Read the keyboard again")
        }
    }
}

struct SidebarFooter: View {
    @EnvironmentObject var model: HubModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: model.connection?.symbol ?? "keyboard")
                    .foregroundStyle(model.isDemo ? .orange : .green).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.deviceName).font(.callout.weight(.medium)).lineLimit(1)
                    Text(model.isDemo ? "Simulated" : (model.connection?.title ?? "")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let b = model.battery { BatteryBadge(battery: b) }
            }
            Button("Disconnect") { model.disconnect() }.controlSize(.small).buttonStyle(.link)
        }
        .padding([.horizontal, .bottom], 12)
    }
}

struct BatteryBadge: View {
    let battery: AulaKeyboard.Battery
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(battery.level <= 15 && !battery.charging ? .red : .secondary)
            Text("\(battery.level)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .help(battery.charging ? "Charging" : "Battery")
    }
    private var symbol: String {
        if battery.charging { return "battery.100.bolt" }
        switch battery.level { case ..<13: return "battery.0"; case ..<38: return "battery.25"; case ..<63: return "battery.50"; case ..<88: return "battery.75"; default: return "battery.100" }
    }
}

struct ReadOnlyBar: View {
    @EnvironmentObject var model: HubModel
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").foregroundStyle(.orange)
            Text("Read-only over \(model.connection?.title ?? "radio"). Plug in the USB cable to change settings — wireless writes can corrupt the keyboard, so they're never sent.")
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct NoticeBar: View {
    let notice: Notice
    var body: some View {
        HStack {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? .yellow : .green)
            Text(notice.text).lineLimit(3).textSelection(.enabled)
            Spacer()
        }
        .padding(10).background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Connect screen

struct ConnectView: View {
    @EnvironmentObject var model: HubModel

    var body: some View {
        VStack(spacing: 22) {
            KeyboardCanvas(flavor: .windows, showLegends: true)
                .frame(maxWidth: 560)
                .opacity(model.present.isEmpty ? 0.8 : 1)
            VStack(spacing: 6) {
                Text("AULA Hub").font(.system(size: 30, weight: .bold, design: .rounded))
                Text(headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                ForEach(Connection.allCases, id: \.self) { c in connectRow(c) }
            }
            .frame(maxWidth: 420)

            if let e = model.connectError {
                VStack(spacing: 8) {
                    Text(e).foregroundStyle(.orange).multilineTextAlignment(.center).textSelection(.enabled)
                    Button("Open Input Monitoring settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }.controlSize(.small)
                }.frame(maxWidth: 520)
            }
            Button("Try the demo keyboard") { model.connect(demo: true) }.buttonStyle(.link)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headline: String {
        if model.connecting { return "Connecting…" }
        if model.present.contains(.wired) { return "Your keyboard is plugged in." }
        if model.present.isEmpty { return "Plug the F75 in with its USB cable, or turn on 2.4G / Bluetooth.\nQuit the official AULA software first." }
        return "Your keyboard is on the radio. Settings need the cable."
    }

    private func connectRow(_ c: Connection) -> some View {
        let seen = model.present.contains(c)
        return HStack(spacing: 12) {
            Image(systemName: c.symbol).frame(width: 22).foregroundStyle(seen ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title).font(.callout.weight(.medium))
                Text(c.capability).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if seen { Pill(text: "Detected", tint: .green) }
            Button(model.connecting ? "…" : "Connect") { model.connect(only: c) }
                .disabled(model.connecting || !seen)
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}
