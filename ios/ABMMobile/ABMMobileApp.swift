import SwiftUI

@main struct ABMMobileApp: App {
    @StateObject private var client = CompanionClient()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            DashboardView(client: client)
                .tint(.yellow)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, value in
                    // Never leave a controller armed while the app is backgrounded.
                    if value == .background { client.disconnect("App entered the background. Pair again to resume control.") }
                }
        }
    }
}
