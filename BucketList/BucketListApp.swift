import SwiftUI
import UserNotifications

@main
struct BucketListApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                        // Engagement record + app_foreground, and ship whatever
                        // the extensions queued while the app was away.
                        Analytics.appDidBecomeActive(items: store.items)
                    } else if phase == .background {
                        // Nudges are laid out weeks ahead, each naming an item —
                        // re-plan on the way out so one just marked "やった" (or
                        // deleted) in this session is never suggested later.
                        NotificationPlanner.sync(tweaks: store.tweaks, items: store.items)
                    }
                }
        }
    }
}

// MARK: - AppDelegate
// The two UIKit hooks the SwiftUI lifecycle doesn't expose: starting the
// analytics SDK before anything could log, and hearing about notification taps.

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Analytics.start()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // A nudge was tapped (the app launches or foregrounds as before — this only
    // records which kind led the user back). Foreground presentation is left
    // to the system default (not shown while the app is open), unchanged.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        Analytics.track(.nudgeOpen, ["kind": .string(Analytics.nudgeKind(fromIdentifier: id))])
        completionHandler()
    }
}
