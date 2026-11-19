import SwiftUI
import AulaKit

enum Page: String, CaseIterable, Identifiable {
    case lighting = "Lighting", perKey = "Per-Key RGB", live = "Live Animations", remap = "Key Remap", device = "Device", backups = "Backups"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .lighting: return "lightbulb.led"
        case .perKey: return "paintpalette"
        case .live: return "sparkles"
        case .remap: return "keyboard"
        case .device: return "slider.horizontal.3"
        case .backups: return "externaldrive"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: HubModel
    @Local private var page: Page = .lighting

    var body: some View {
        Group {
            if model.isConnected {
                NavigationSplitView {
                    List(Page.allCases, selection: $page) { p in
                        Label(p.rawValue, systemImage: p.icon).tag(p)
                    }
                    .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
                    .safeAreaInset(edge: .bottom) { SidebarFooter() }
                } detail: {
                    VStack(spacing: 0) {
                        switch page {
                        case .lighting: LightingView()
                        case .perKey: PerKeyView()
                        case .live: LiveView()
                        case .remap: RemapView()
                        case .device: DeviceView()
                        case .backups: BackupsView()
                        }
                        if let n = model.notice { NoticeBar(notice: n) }
                    }
                }
            } else {
                ConnectView()
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}

struct SidebarFooter: View {
    @EnvironmentObject var model: HubModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Circle().fill(model.keyboard?.info.isDemo == true ? Color.orange : Color.green).frame(width: 8, height: 8)
                Text(model.deviceName).font(.callout).lineLimit(1)
            }
            if let b = model.battery {
                Text("Battery \(b.level)%\(b.charging ? " ⚡︎" : "")").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Refresh") { Task { await model.refresh() } }
                Button("Disconnect") { model.disconnect() }
            }.controlSize(.small)
        }
        .padding([.horizontal, .bottom], 12)
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
    }
}

struct ConnectView: View {
    @EnvironmentObject var model: HubModel
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard").font(.system(size: 54)).foregroundStyle(.secondary)
            Text("AULA Hub").font(.largeTitle.bold())
            Text("Plug the F75 in with its USB cable, quit the official AULA software, then connect.\nThe 2.4G dongle and Bluetooth can't be configured — only the cable.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack {
                Button { model.connect() } label: { Label(model.connecting ? "Connecting…" : "Connect keyboard", systemImage: "cable.connector") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.connecting)
                Button("Try the demo keyboard") { model.connect(demo: true) }.controlSize(.large)
            }
            if let e = model.connectError {
                VStack(spacing: 8) {
                    Text(e).foregroundStyle(.orange).multilineTextAlignment(.center).textSelection(.enabled)
                    Button("Open Input Monitoring settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }.controlSize(.small)
                }.frame(maxWidth: 520)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
