import SwiftUI

@main
struct AulaHubApp: App {
    @StateObject private var model = HubModel()

    var body: some Scene {
        WindowGroup("AULA Hub") {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if CommandLine.arguments.contains("--demo") { model.connect(demo: true) }
                }
        }
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
