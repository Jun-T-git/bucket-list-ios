import Foundation
#if ANALYTICS_FIREBASE
import FirebaseCore
import FirebaseAnalytics
#endif

// MARK: - Analytics (usage measurement)
//
// The single door to the analytics backend (Firebase Analytics). Nothing else
// in the app imports the SDK: call sites say `Analytics.track(.itemDone, …)`
// and this file decides what happens. Three rules keep it honest with the
// design principles (§8 privacy / the KPI = 「やった」に変わった数):
//   - Only usage *events* leave the device. Never a title, memo, URL, tag
//     label, or anything typed by the user — parameters are enum-like strings,
//     counts and buckets (see `Event` for the whole vocabulary).
//   - The user can switch it off (設定 → プライバシー → 利用状況の送信). Off means
//     off: the SDK stops collecting and the pending queue is discarded.
//   - Only the host app links the SDK (`ANALYTICS_FIREBASE` compilation
//     condition on the BucketList target). The extensions append to a queue in
//     the App Group and the host ships it on its next foreground. The quick
//     `swiftc -typecheck` path also compiles without the SDK.
// DEBUG builds never send anything unless launched with ANALYTICS_DEBUG=1
// (pair with the `-FIRDebugEnabled` argument to watch DebugView).

enum Analytics {

    // MARK: vocabulary

    // Event names are stable identifiers — renaming one splits its history in
    // the dashboard. Reserved Firebase names (session_start, first_open,
    // notification_open, …) are avoided on purpose.
    enum Event: String, CaseIterable {
        case appForeground = "app_foreground"      // every return to foreground (+ engagement)
        case onboardingComplete = "onboarding_complete"
        case screenView = "screen_view"            // Firebase's standard screen event
        case itemAdd = "item_add"
        case itemUpdate = "item_update"
        case itemDone = "item_done"
        case itemUndone = "item_undone"
        case itemDelete = "item_delete"
        case itemLinkOpen = "item_link_open"
        case undo = "undo"
        case captureResult = "capture_result"      // URL → candidate outcome
        case captureApply = "capture_apply"        // user adopted the candidate (app)
        case suggestionTap = "suggestion_tap"      // home timing banner
        case suggestionDismiss = "suggestion_dismiss"
        case widgetTap = "widget_tap"
        case nudgeOpen = "nudge_open"              // local notification tapped
        case filterChange = "filter_change"
        case sortChange = "sort_change"
        case bulkAction = "bulk_action"
        case customTagAdd = "custom_tag_add"
        case goalChange = "goal_change"
        case settingChange = "setting_change"
    }

    // Parameter values are either a small integer or a fixed vocabulary string.
    // Codable so the extension queue can carry them.
    enum Value: Codable, Equatable {
        case int(Int)
        case string(String)

        init(_ i: Int) { self = .int(i) }
        init(_ s: String) { self = .string(s) }
        init(_ b: Bool) { self = .int(b ? 1 : 0) }

        var raw: Any {
            switch self {
            case .int(let i): return i
            case .string(let s): return s
            }
        }
    }

    typealias Params = [String: Value]

    // MARK: switches

    // Mirrors Tweaks.analyticsEnabled. Read on every track() so a flip in 設定
    // takes effect immediately, in the host and (via the shared suite) in the
    // extensions.
    static var isEnabled: Bool {
        Storage.loadTweaks()?.analyticsEnabled ?? true
    }

    // True when this process may send at all (build/environment gate — the
    // user's toggle is checked separately).
    private static var isSendingAllowed: Bool {
        if Screenshots.isOn { return false }
        #if DEBUG
        return ProcessInfo.processInfo.environment["ANALYTICS_DEBUG"] == "1"
        #else
        return true
        #endif
    }

    private static var configured = false

    // MARK: host lifecycle

    // Host app only, from application(_:didFinishLaunchingWithOptions:). Needs
    // a real GoogleService-Info.plist in the bundle (the repo ships a placeholder
    // so the build never breaks); with the placeholder, or none, the app runs
    // with analytics silently off — nothing to crash on a fresh checkout.
    static func start() {
        #if ANALYTICS_FIREBASE
        guard isSendingAllowed,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.googleAppID.hasPrefix("1:")   // real IDs look like 1:123:ios:abc
        else { return }
        FirebaseApp.configure(options: options)
        configured = true
        // Info.plist sets FirebaseDataCollectionDefaultEnabled=false, so nothing
        // (not even first_open) is collected until the user's choice is applied.
        setEnabled(isEnabled)
        #endif
    }

    // Apply the user's choice. Off means off: discard anything the extensions
    // queued, stop the SDK, and drop its app-instance id and unsent data too.
    static func setEnabled(_ on: Bool) {
        if !on { Storage.clearAnalyticsQueue() }
        #if ANALYTICS_FIREBASE
        guard configured else { return }
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(on)
        if !on { FirebaseAnalytics.Analytics.resetAnalyticsData() }
        #endif
    }

    // Host app, on every scenePhase == .active: advance the engagement record
    // (open streak etc.), emit app_foreground, refresh the user properties
    // that segment heavy/light users, and drain the extension queue.
    static func appDidBecomeActive(items: [BucketItem]) {
        guard isEnabled else { return }
        let (engagement, _) = Engagement.advanced(Storage.loadEngagement(), today: Clock.today)
        Storage.saveEngagement(engagement)

        let done = items.filter(\.done).count
        let doneThisYear = items.filter {
            $0.done && ($0.doneAt.map { Clock.calendar.component(.year, from: $0) } == Clock.year)
        }.count
        track(.appForeground, [
            "streak_days": Value(engagement.streak),
            "open_days": Value(engagement.openDays),
            "days_since_first": Value(engagement.daysSinceFirst(today: Clock.today)),
            "item_count": Value(items.count),
            "done_count": Value(done),
            "done_this_year": Value(doneThisYear),
        ])
        setUserProperty("items_bucket", Engagement.bucket(items.count))
        setUserProperty("done_bucket", Engagement.bucket(done))
        setUserProperty("streak_bucket", Engagement.bucket(engagement.streak))
        flushQueue()
    }

    // MARK: tracking

    static func track(_ event: Event, _ params: Params = [:]) {
        guard isEnabled else { return }
        #if ANALYTICS_FIREBASE
        guard configured else { return }
        log(event.rawValue, params)
        #else
        // Extensions (and the SDK-less typecheck build): queue for the host.
        Storage.appendAnalyticsQueue(QueuedEvent(name: event.rawValue, params: params))
        #endif
    }

    static func screen(_ name: String) {
        track(.screenView, ["screen_name": Value(name)])
    }

    // MARK: shaped events (the vocabulary call sites share)

    // A new wish was saved. `source` = app | share. `fromCapture` = the URL
    // reading filled the form (vs. typed by hand).
    static func itemAdded(priority: Priority, seasons: [SeasonTag], tagCount: Int,
                          hasURL: Bool, source: String, fromCapture: Bool) {
        track(.itemAdd, [
            "source": Value(source),
            "has_url": Value(hasURL),
            "from_capture": Value(fromCapture),
            "priority": Value(priority.rawValue),
            "season": Value(seasonLabel(seasons)),
            "tag_count": Value(tagCount),
        ])
    }

    // The KPI moment. `source` = list | detail | bulk. `days_open` tells how
    // long an "いつか" sat before it became a "やった".
    static func itemDone(_ item: BucketItem, source: String) {
        var p: Params = [
            "source": Value(source),
            "priority": Value(item.priority.rawValue),
            "season": Value(seasonLabel(item.seasons)),
            "has_url": Value(item.url != nil),
        ]
        if let d = daysOpen(item) { p["days_open"] = Value(d) }
        track(.itemDone, p)
    }

    // Mail-style bulk edit. `kind` = tag_add | tag_remove | priority | done | undone.
    static func bulk(_ kind: String, count: Int) {
        track(.bulkAction, ["kind": Value(kind), "count": Value(count)])
    }

    // URL reading finished. `outcome` = ok | low_confidence | failed | invalid.
    static func captureResult(_ outcome: String, source: String) {
        track(.captureResult, ["outcome": Value(outcome), "source": Value(source)])
    }

    // One setting_change per toggle that actually flipped (yearGoal has its
    // own goal_change; userName is never sent).
    static func settingsChanged(from old: Tweaks, to new: Tweaks) {
        let toggles: [(String, Bool, Bool)] = [
            ("season_nudge", old.seasonNudge, new.seasonNudge),
            ("weekend_nudge", old.weekendNudge, new.weekendNudge),
            ("month_end_nudge", old.monthEndNudge, new.monthEndNudge),
            ("auto_classify", old.autoClassify, new.autoClassify),
            ("analytics", old.analyticsEnabled, new.analyticsEnabled),
        ]
        for (key, was, now) in toggles where was != now {
            track(.settingChange, ["key": Value(key), "value": Value(now)])
        }
    }

    // Filter/sort observers: derive the axis that changed so the event says
    // *which* control was used, not just "something changed".
    static func filterChanged(from old: Filters, to new: Filters) {
        guard old != new else { return }
        let axis: String
        if new.isEmpty && !old.isEmpty { axis = "clear" }
        else if old.priority != new.priority { axis = "priority" }
        else if old.seasons != new.seasons { axis = "season" }
        else if old.tags != new.tags { axis = "tag" }
        else { axis = "status" }
        track(.filterChange, ["axis": Value(axis), "active_count": Value(new.activeCount)])
    }

    static func sortChanged(mode: SortMode, ascending: Bool) {
        track(.sortChange, ["mode": Value(mode.rawValue), "ascending": Value(ascending)])
    }

    // Notification identifiers are "nudge.<kind>[.n]" (NotificationPlanner).
    static func nudgeKind(fromIdentifier id: String) -> String {
        let parts = id.split(separator: ".")
        guard parts.count >= 2, parts[0] == "nudge" else { return "other" }
        switch parts[1] {
        case "season": return "season"
        case "weekend": return "weekend"
        case "monthEnd": return "month_end"
        default: return "other"
        }
    }

    // A single season label for an item: any / spring / … / mixed.
    static func seasonLabel(_ seasons: [SeasonTag]) -> String {
        let s = seasons.isEmpty ? [.any] : seasons
        guard s.count == 1 else { return "mixed" }
        return s[0].storageKey
    }

    // Whole days between an item's save date and today (nil if unparsable).
    static func daysOpen(_ item: BucketItem, today: Date = Clock.today) -> Int? {
        guard let saved = BucketItem.parseSavedAt(item.savedAt) else { return nil }
        let cal = Clock.calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: saved),
                                  to: cal.startOfDay(for: today)).day
    }

    // MARK: SDK bridge (host only)

    private static func setUserProperty(_ name: String, _ value: String) {
        #if ANALYTICS_FIREBASE
        guard configured else { return }
        FirebaseAnalytics.Analytics.setUserProperty(value, forName: name)
        #endif
    }

    private static func log(_ name: String, _ params: Params) {
        #if ANALYTICS_FIREBASE
        FirebaseAnalytics.Analytics.logEvent(name, parameters: params.mapValues(\.raw))
        #endif
    }

    // Ship whatever the extensions queued while the app was away. Events are
    // logged with the flush time, not the original time — a share-sheet save
    // shows up at the next app open, which is close enough for daily rollups.
    private static func flushQueue() {
        #if ANALYTICS_FIREBASE
        guard configured else { return }
        let queued = Storage.drainAnalyticsQueue()
        for e in queued { log(e.name, e.params) }
        #endif
    }

    // MARK: queue record

    struct QueuedEvent: Codable, Equatable {
        var name: String
        var params: Params
    }
}

// MARK: - Engagement (pure)
// The "did they keep coming back?" record, kept on device and attached to
// app_foreground. Firebase has DAU/retention of its own; the streak is the one
// number it can't derive, so we compute it here.

struct Engagement: Codable, Equatable {
    var firstOpen: Date? = nil
    var lastOpen: Date? = nil
    var streak: Int = 0       // consecutive calendar days with an open, incl. today
    var openDays: Int = 0     // distinct calendar days with an open, lifetime

    // Tolerant decode — a missing field never resets the record.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstOpen = try? c.decode(Date.self, forKey: .firstOpen)
        lastOpen = try? c.decode(Date.self, forKey: .lastOpen)
        streak = (try? c.decode(Int.self, forKey: .streak)) ?? 0
        openDays = (try? c.decode(Int.self, forKey: .openDays)) ?? 0
    }

    // Advance the record for an open at `today`. Returns the new record and
    // whether this is the first open of that calendar day.
    static func advanced(_ e: Engagement, today: Date,
                         calendar: Calendar = Clock.calendar) -> (Engagement, newDay: Bool) {
        var next = e
        if next.firstOpen == nil { next.firstOpen = today }
        guard let last = e.lastOpen else {
            next.lastOpen = today; next.streak = 1; next.openDays = 1
            return (next, true)
        }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                          to: calendar.startOfDay(for: today)).day ?? 0
        if gap <= 0 { return (next, false) }         // same day (or clock went back)
        next.lastOpen = today
        next.openDays += 1
        next.streak = gap == 1 ? max(next.streak, 0) + 1 : 1
        return (next, true)
    }

    func daysSinceFirst(today: Date, calendar: Calendar = Clock.calendar) -> Int {
        guard let first = firstOpen else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                              to: calendar.startOfDay(for: today)).day ?? 0)
    }

    // Coarse size classes for user properties — enough to split light / heavy
    // users in the dashboard without leaking exact list sizes.
    static func bucket(_ n: Int) -> String {
        switch n {
        case ..<1: return "0"
        case 1...4: return "1-4"
        case 5...9: return "5-9"
        case 10...29: return "10-29"
        default: return "30+"
        }
    }
}

// MARK: - Storage: engagement record + extension event queue (App Group suite)

extension Storage {
    private static let kEngagement = "bucket-list-v2.engagement"
    private static let kAnalyticsQueue = "bucket-list-v2.analyticsQueue"
    // Extensions can queue only so much before the host next opens; beyond
    // this the oldest entries are dropped rather than growing UserDefaults.
    static let analyticsQueueLimit = 500

    static func loadEngagement() -> Engagement {
        guard let data = defaults.data(forKey: kEngagement) else { return Engagement() }
        return (try? JSONDecoder().decode(Engagement.self, from: data)) ?? Engagement()
    }
    static func saveEngagement(_ e: Engagement) {
        guard let data = try? JSONEncoder().encode(e) else { return }
        defaults.set(data, forKey: kEngagement)
    }

    static func loadAnalyticsQueue() -> [Analytics.QueuedEvent] {
        guard let data = defaults.data(forKey: kAnalyticsQueue) else { return [] }
        return (try? JSONDecoder().decode([Analytics.QueuedEvent].self, from: data)) ?? []
    }
    static func appendAnalyticsQueue(_ e: Analytics.QueuedEvent) {
        var q = loadAnalyticsQueue()
        q.append(e)
        if q.count > analyticsQueueLimit { q.removeFirst(q.count - analyticsQueueLimit) }
        guard let data = try? JSONEncoder().encode(q) else { return }
        defaults.set(data, forKey: kAnalyticsQueue)
    }
    static func drainAnalyticsQueue() -> [Analytics.QueuedEvent] {
        let q = loadAnalyticsQueue()
        defaults.removeObject(forKey: kAnalyticsQueue)
        return q
    }
    static func clearAnalyticsQueue() {
        defaults.removeObject(forKey: kAnalyticsQueue)
    }
}

// MARK: - Screen names

extension AppStore.Tab {
    var analyticsName: String {
        switch self {
        case .home: return "home"
        case .records: return "report"
        case .settings: return "settings"
        }
    }
}
