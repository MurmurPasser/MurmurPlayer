import KSPlayer
import SwiftUI

@main
struct MurmurPlayerApp: App {
    @StateObject private var servers = ServerStore.shared
    @StateObject private var history = PlaybackHistory.shared
    @StateObject private var router = PlaybackRouter.shared

    init() {
        PlayerSettings.applyGlobalDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(servers)
                .environmentObject(history)
                .environmentObject(router)
                .onOpenURL { url in
                    router.openExternal(url)
                }
        }
    }
}
