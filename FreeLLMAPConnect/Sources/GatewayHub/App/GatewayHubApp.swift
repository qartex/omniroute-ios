import SwiftUI

@main
struct GatewayHubApp: App {
    @State private var store = GatewayStore()

    var body: some Scene {
        WindowGroup {
            GatewayRootView()
                .environment(store)
        }
    }
}
