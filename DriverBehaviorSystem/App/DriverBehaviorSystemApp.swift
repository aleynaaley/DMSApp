import SwiftUI

@main
struct DriverBehaviorSystemApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    await store.loadProfiles()
                }
        }
    }
}
