import SwiftUI
import DefectDashCore

struct DefectDashApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("DefectDash", id: "main") {
            ContentView()
                .environment(model)
                .task { model.start() }
        }
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            MenuBarMenu()
                .environment(model)
        } label: {
            Label("\(model.needsYouCount)", systemImage: "ladybug")
                .labelStyle(.titleAndIcon)
        }
    }
}

struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Needs you: \(model.needsYouCount)")
        if let at = model.lastRefreshed {
            Text("Refreshed \(Format.shortAge(at)) ago")
        }
        Divider()
        Button("Refresh") { Task { await model.refresh() } }
            .disabled(model.isRefreshing)
        Button("Open DefectDash") {
            openWindow(id: "main")
            NSApplication.shared.activate()
        }
        Button("Settings…") {
            openWindow(id: "main")
            NSApplication.shared.activate()
            model.settingsRequests += 1
        }
        Divider()
        Button("Quit DefectDash") { NSApplication.shared.terminate(nil) }
    }
}
