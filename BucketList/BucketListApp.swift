import SwiftUI

@main
struct BucketListApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var pro = ProStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(pro)
                .onAppear {
                    // Begin observing StoreKit transactions and resolve the Pro
                    // entitlement (mirrored into the App Group for the extension).
                    pro.start()
                    // Keep scheduled nudges in step with settings — and refresh
                    // the item each nudge names. No permission prompt here; that
                    // only happens when the user flips a toggle in 設定.
                    NotificationPlanner.sync(tweaks: store.tweaks, items: store.items)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Pick up items captured via the Share Extension while the
                    // app was backgrounded — re-read the shared store on
                    // return to the foreground, then re-sync so notifications
                    // reflect the latest list.
                    if phase == .active {
                        store.reload()
                        NotificationPlanner.sync(tweaks: store.tweaks, items: store.items)
                    }
                }
        }
    }
}
