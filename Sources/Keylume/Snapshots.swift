import SwiftUI
import KeylumeKit

/// Renders each page to a PNG without a window server round trip: `Keylume --demo --snapshot <dir>`.
/// Used to check the interface from the command line.
@MainActor
enum Snapshots {
    static func run(into dir: String) {
        let model = HubModel()
        model.connect(demo: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let pages: [(String, AnyView)] = [
                ("overview", AnyView(OverviewView())), ("lighting", AnyView(LightingView())), ("perkey", AnyView(PerKeyView())),
                ("live", AnyView(LiveView())), ("remap", AnyView(RemapView())), ("device", AnyView(DeviceView())), ("backups", AnyView(BackupsView())),
            ]
            for (name, view) in pages { render(view, model: model, to: "\(dir)/\(name).png") }
            render(AnyView(ConnectView()), model: HubModel(), to: "\(dir)/connect.png", height: 760)
            render(AnyView(Card { KeyboardCanvas(colors: Themes.named("synthwave")?.render() ?? [:], flavor: .windows) }.padding()), model: model, to: "\(dir)/lit.png", height: 420)
            // Mac mode legends
            model.setOSMode(2)
            try? await Task.sleep(nanoseconds: 800_000_000)
            render(AnyView(OverviewView()), model: model, to: "\(dir)/overview-mac.png")
            render(AnyView(RemapView()), model: model, to: "\(dir)/remap-mac.png")
            exit(0)
        }
    }

    private static func render(_ view: AnyView, model: HubModel, to path: String, height: CGFloat = 1100) {
        let content = view.environmentObject(model).environment(\.flatLayout, true)
            .frame(width: 880, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
        let r = ImageRenderer(content: content)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("snapshot failed: \(path)"); return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
