import Foundation
import SwiftUI
import Combine
import UserNotifications

// MARK: - Feature flags

enum FeatureFlags {
    // Pro / in-app purchase. Disabled for the initial free release (the Paid
    // Apps agreement / IAP product aren't set up in App Store Connect yet).
    // While false: no Paywall or purchase/restore UI is shown, StoreKit is never
    // touched, and URL auto-import is UNLIMITED for everyone (no free-quota wall
    // with no way past it). Flip to `true` once the IAP `teratech.BucketList.pro`
    // and the Paid Apps agreement are live, and the paid gating returns as-is.
    static let proEnabled = false
}

// MARK: - Screenshot mode (DEBUG only)
// Drives App Store screenshot capture: launched with SCREENSHOTS=1 the app skips
// the splash/onboarding, loads a curated demo dataset with a pinned date, and
// opens the tab named by SCREEN (home/records/settings/add). Compiled out of
// Release entirely, so it can never affect the shipped app.
enum Screenshots {
    static var isOn: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SCREENSHOTS"] == "1"
        #else
        return false
        #endif
    }
    static var screen: String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SCREEN"]
        #else
        return nil
        #endif
    }
}

// MARK: - Priority
// Three levels, weighted top → maybe → someday. Visualized as green depth.

enum Priority: String, Codable, CaseIterable, Identifiable {
    case top
    case maybe
    case someday

    var id: String { rawValue }

    var ja: String {
        switch self {
        case .top: return "高"
        case .maybe: return "中"
        case .someday: return "低"
        }
    }
    var color: Color {
        switch self {
        case .top: return Theme.Color.green700
        case .maybe: return Theme.Color.green500
        case .someday: return Theme.Color.green300
        }
    }
    var weight: Int {
        switch self {
        case .top: return 3
        case .maybe: return 2
        case .someday: return 1
        }
    }

    static let order: [Priority] = [.top, .maybe, .someday]
}

// MARK: - Season
// 4 seasons + special "any". Months stored separately as "m1"…"m12" strings.
// An item carries an array of SeasonTag values (multi-select).

enum Season: String, Codable, CaseIterable, Identifiable {
    case spring, summer, fall, winter

    var id: String { rawValue }

    var ja: String {
        switch self {
        case .spring: return "春"
        case .summer: return "夏"
        case .fall: return "秋"
        case .winter: return "冬"
        }
    }
    var months: [Int] {
        switch self {
        case .spring: return [3, 4, 5]
        case .summer: return [6, 7, 8]
        case .fall:   return [9, 10, 11]
        case .winter: return [12, 1, 2]
        }
    }
    var monthsDisplay: String {
        months.map(String.init).joined(separator: "·")
    }
    static let order: [Season] = [.spring, .summer, .fall, .winter]

    static func of(month: Int) -> Season {
        switch month {
        case 3...5:  return .spring
        case 6...8:  return .summer
        case 9...11: return .fall
        default:     return .winter
        }
    }

    // The 4 seasons in temporal order starting from `season` — used by the
    // report's "これからの季節" so "now" always leads.
    static func upcoming(from season: Season) -> [Season] {
        guard let idx = order.firstIndex(of: season) else { return order }
        return (0..<4).map { order[(idx + $0) % 4] }
    }
}

// A SeasonTag is the multi-select element used on items: a season,
// a specific month, or the "any" wildcard.
enum SeasonTag: Codable, Hashable, Identifiable {
    case season(Season)
    case month(Int)
    case any

    var id: String { storageKey }

    var storageKey: String {
        switch self {
        case .season(let s): return s.rawValue
        case .month(let n):  return "m\(n)"
        case .any:           return "any"
        }
    }
    var ja: String {
        switch self {
        case .season(let s): return s.ja
        case .month(let n):  return "\(n)月"
        case .any:           return "いつでも"
        }
    }
    var isMonth: Bool {
        if case .month = self { return true }
        return false
    }

    static func from(key: String) -> SeasonTag? {
        if key == "any" { return .any }
        if let s = Season(rawValue: key) { return .season(s) }
        if key.hasPrefix("m"), let n = Int(key.dropFirst()), (1...12).contains(n) {
            return .month(n)
        }
        return nil
    }
}

// MARK: - Tag
// 4 built-in + up to MAX_CUSTOM_TAGS user-defined.

struct TagDef: Identifiable, Codable, Equatable, Hashable {
    let key: String
    var ja: String
    let builtin: Bool
    var id: String { key }
}

enum Tags {
    static let defaults: [TagDef] = [
        TagDef(key: "food",     ja: "飲食",     builtin: true),
        TagDef(key: "travel",   ja: "旅行",     builtin: true),
        TagDef(key: "leisure",  ja: "レジャー", builtin: true),
        TagDef(key: "shopping", ja: "お買い物", builtin: true),
    ]
    static let maxCustom = 10
}

// How a tag applies across a set of selected items (bulk tag editing).
enum TagCoverage { case all, some, none }

// MARK: - Item

struct BucketItem: Identifiable, Codable, Equatable, Hashable {
    var id: Int
    var title: String
    var priority: Priority
    var seasons: [SeasonTag]
    var tags: [String]      // tag keys
    var meta: String
    var done: Bool
    var doneAt: Date?       // when it was checked off — drives the report
    var via: String?
    var url: String?
    var savedAt: String

    // Seasons with the "empty means いつでも" rule applied — an item with no
    // season tags behaves as `.any`. Filtering, sorting, counting, the report and
    // the row all read this instead of re-deriving `seasons.isEmpty ? [.any] : …`.
    var normalizedSeasons: [SeasonTag] { seasons.isEmpty ? [.any] : seasons }

    // Decode tolerantly — older payloads may lack `tags` / `doneAt`.
    enum CodingKeys: String, CodingKey {
        case id, title, priority, seasons, tags, meta, done, doneAt, via, url, savedAt
    }
    init(id: Int, title: String, priority: Priority, seasons: [SeasonTag],
         tags: [String], meta: String, done: Bool, doneAt: Date? = nil,
         via: String?, url: String?, savedAt: String) {
        self.id = id; self.title = title; self.priority = priority
        self.seasons = seasons; self.tags = tags; self.meta = meta
        self.done = done; self.doneAt = doneAt
        self.via = via; self.url = url; self.savedAt = savedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        priority = try c.decode(Priority.self, forKey: .priority)
        let seasonKeys = try c.decode([String].self, forKey: .seasons)
        seasons = seasonKeys.compactMap(SeasonTag.from(key:))
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        meta = (try? c.decode(String.self, forKey: .meta)) ?? ""
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        doneAt = try? c.decode(Date.self, forKey: .doneAt)
        via  = try? c.decode(String.self, forKey: .via)
        url  = try? c.decode(String.self, forKey: .url)
        savedAt = (try? c.decode(String.self, forKey: .savedAt)) ?? ""
        // Items checked off before doneAt existed: approximate with savedAt
        // so the report doesn't silently drop them.
        if done && doneAt == nil {
            doneAt = BucketItem.parseSavedAt(savedAt) ?? Clock.today
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(priority, forKey: .priority)
        try c.encode(seasons.map(\.storageKey), forKey: .seasons)
        try c.encode(tags, forKey: .tags)
        try c.encode(meta, forKey: .meta)
        try c.encode(done, forKey: .done)
        try c.encodeIfPresent(doneAt, forKey: .doneAt)
        try c.encodeIfPresent(via, forKey: .via)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encode(savedAt, forKey: .savedAt)
    }

    // Shared formatter for the "yyyy·MM·dd" savedAt string (mid-dot separated).
    // Built once — DateFormatter creation is expensive — and only ever read,
    // so it's safe to share across the app and the Share Extension.
    static let savedAtFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy·MM·dd"
        return df
    }()

    static func parseSavedAt(_ s: String) -> Date? {
        savedAtFormatter.date(from: s)
    }
}

// MARK: - Clock
// Live "today". The whole product is timing-based nudges, so this must be
// real time. `override` lets previews / design screenshots pin a date
// (e.g. 2026-05-22) without faking time for actual users.

enum Clock {
    static var override: Date? = nil

    static var today: Date { override ?? Date() }
    static var calendar: Calendar { Calendar.current }

    static var month: Int { calendar.component(.month, from: today) }
    static var day: Int { calendar.component(.day, from: today) }
    static var year: Int { calendar.component(.year, from: today) }
    // 1 = Sunday … 7 = Saturday (Gregorian default)
    static var weekday: Int { calendar.component(.weekday, from: today) }
    static var season: Season { Season.of(month: month) }
    static var nextMonth: Int { month == 12 ? 1 : month + 1 }
    static var nextSeason: Season { Season.of(month: nextMonth) }

    // Timing-frame cues (concept §5-③: 金曜→今週末, 月初→今月, 年末→今年).
    static var isWeekendish: Bool { weekday == 6 || weekday == 7 || weekday == 1 } // Fri/Sat/Sun
    static var isMonthStart: Bool { day <= 7 }
    static var isYearEnd: Bool { month == 12 && day >= 15 }
    // Last month of the current season — "夏が終わる前に" territory.
    static var isSeasonClosing: Bool { Season.of(month: nextMonth) != season }
}

// MARK: - Seed
// Same 11 items used in the prototype, restated with native types.

enum Seed {
    static let items: [BucketItem] = [
        .init(id: 1,  title: "代々木公園のあの蕎麦屋に行く",
              priority: .top, seasons: [.any],
              tags: ["food"], meta: "東京・渋谷",
              done: false, via: "X", url: "x.com/foodie_tk/...", savedAt: "2026·05·02"),
        .init(id: 2,  title: "友達と銭湯",
              priority: .top, seasons: [.season(.winter), .season(.fall)],
              tags: ["leisure", "c-relax"], meta: "寒くなったら",
              done: false, via: nil, url: nil, savedAt: "2026·05·09"),
        .init(id: 3,  title: "春のうちに花見",
              priority: .top, seasons: [.season(.spring), .month(4)],
              tags: ["leisure"], meta: "4月上旬",
              done: true, doneAt: BucketItem.parseSavedAt("2026·04·05"),
              via: nil, url: nil, savedAt: "2026·03·12"),
        .init(id: 4,  title: "カニを食べる",
              priority: .maybe,
              seasons: [.season(.winter), .month(11), .month(12)],
              tags: ["food", "travel"], meta: "北陸",
              done: false, via: nil, url: nil, savedAt: "2026·01·20"),
        .init(id: 5,  title: "富士山を見にドライブ",
              priority: .maybe, seasons: [.season(.summer)],
              tags: ["travel", "leisure"], meta: "晴れた日",
              done: false, via: "YouTube", url: "youtu.be/fuji-drive", savedAt: "2026·04·18"),
        .init(id: 6,  title: "一人で映画館",
              priority: .top, seasons: [.any],
              tags: ["leisure", "c-relax"], meta: "名画座",
              done: false, via: nil, url: nil, savedAt: "2026·04·30"),
        .init(id: 7,  title: "オーロラを見に行く",
              priority: .someday,
              seasons: [.season(.winter), .month(11), .month(12),
                        .month(1), .month(2), .month(3)],
              tags: ["travel"], meta: "アイスランド",
              done: false, via: "Safari",
              url: "iceland-aurora.example.com/tours", savedAt: "2025·12·04"),
        .init(id: 8,  title: "アメリカ西海岸を旅する",
              priority: .someday, seasons: [.season(.summer)],
              tags: ["travel"], meta: "長期休暇",
              done: false, via: nil, url: nil, savedAt: "2025·11·22"),
        .init(id: 9,  title: "小説を一冊書く",
              priority: .someday, seasons: [.any],
              tags: ["c-learn"], meta: "締切なし",
              done: false, via: nil, url: nil, savedAt: "2025·10·08"),
        .init(id: 10, title: "海でBBQ",
              priority: .top,
              seasons: [.season(.summer), .month(7), .month(8)],
              tags: ["food", "leisure"], meta: "夏のうちに",
              done: false, via: nil, url: nil, savedAt: "2026·05·14"),
        .init(id: 11, title: "京都の紅葉",
              priority: .maybe, seasons: [.season(.fall), .month(11)],
              tags: ["travel", "leisure"], meta: "11月中旬",
              done: false, via: "YouTube", url: "youtu.be/kyoto-momiji", savedAt: "2025·10·30"),
    ]
    static let customTags: [TagDef] = [
        TagDef(key: "c-learn", ja: "学び", builtin: false),
        TagDef(key: "c-relax", ja: "のんびり", builtin: false),
    ]

    // Pinned "today" for screenshots: a summer Friday so the home hero shows a
    // 今週末 frame and the report's 今年 = 2026 has a full history.
    static let screenshotDate: Date =
        BucketItem.parseSavedAt("2026·07·17") ?? Date()

    // Curated demo data for App Store screenshots (DEBUG screenshot mode only).
    // A lively open list plus a spread of 2026 achievements so the レポート chart
    // and pace card look real.
    static let screenshotItems: [BucketItem] = [
        // open — summer-forward for a July capture
        .init(id: 1, title: "代々木公園のあの蕎麦屋に行く", priority: .top, seasons: [.any],
              tags: ["food"], meta: "東京・渋谷", done: false,
              via: "X", url: "x.com/foodie_tk/…", savedAt: "2026·07·02"),
        .init(id: 2, title: "海でBBQ", priority: .top,
              seasons: [.season(.summer), .month(7), .month(8)],
              tags: ["food", "leisure"], meta: "夏のうちに", done: false,
              via: nil, url: nil, savedAt: "2026·06·30"),
        .init(id: 3, title: "富士山を見にドライブ", priority: .maybe, seasons: [.season(.summer)],
              tags: ["travel", "leisure"], meta: "晴れた日に", done: false,
              via: "YouTube", url: "youtu.be/fuji-drive", savedAt: "2026·06·18"),
        .init(id: 4, title: "一人で映画館", priority: .top, seasons: [.any],
              tags: ["leisure", "c-relax"], meta: "名画座", done: false,
              via: nil, url: nil, savedAt: "2026·06·10"),
        .init(id: 5, title: "京都の紅葉", priority: .maybe, seasons: [.season(.fall), .month(11)],
              tags: ["travel", "leisure"], meta: "11月中旬", done: false,
              via: "YouTube", url: "youtu.be/kyoto-momiji", savedAt: "2026·05·28"),
        .init(id: 6, title: "カニを食べる", priority: .maybe,
              seasons: [.season(.winter), .month(11), .month(12)],
              tags: ["food", "travel"], meta: "北陸", done: false,
              via: nil, url: nil, savedAt: "2026·05·14"),
        .init(id: 7, title: "友達と銭湯", priority: .top,
              seasons: [.season(.winter), .season(.fall)],
              tags: ["leisure", "c-relax"], meta: "寒くなったら", done: false,
              via: nil, url: nil, savedAt: "2026·05·09"),
        .init(id: 8, title: "オーロラを見に行く", priority: .someday,
              seasons: [.season(.winter), .month(11), .month(12), .month(1), .month(2)],
              tags: ["travel"], meta: "アイスランド", done: false,
              via: "Safari", url: "iceland-aurora.example.com/tours", savedAt: "2026·04·22"),
        .init(id: 9, title: "アメリカ西海岸を旅する", priority: .someday, seasons: [.season(.summer)],
              tags: ["travel"], meta: "長期休暇", done: false,
              via: nil, url: nil, savedAt: "2026·03·30"),
        .init(id: 10, title: "小説を一冊書く", priority: .someday, seasons: [.any],
              tags: ["c-learn"], meta: "締切なし", done: false,
              via: nil, url: nil, savedAt: "2026·02·08"),
        // done — a 2026 achievement trail for the report
        .init(id: 11, title: "江ノ島で夕日を見る", priority: .maybe,
              seasons: [.season(.summer)], tags: ["leisure", "travel"], meta: "",
              done: true, doneAt: BucketItem.parseSavedAt("2026·06·28"),
              via: nil, url: nil, savedAt: "2026·06·01"),
        .init(id: 12, title: "友達と海鮮丼", priority: .top, seasons: [.any],
              tags: ["food"], meta: "", done: true,
              doneAt: BucketItem.parseSavedAt("2026·05·10"),
              via: nil, url: nil, savedAt: "2026·04·20"),
        .init(id: 13, title: "春のうちに花見", priority: .top,
              seasons: [.season(.spring), .month(4)], tags: ["leisure"], meta: "",
              done: true, doneAt: BucketItem.parseSavedAt("2026·04·05"),
              via: nil, url: nil, savedAt: "2026·03·12"),
        .init(id: 14, title: "新しいカメラを買う", priority: .maybe, seasons: [.any],
              tags: ["shopping"], meta: "", done: true,
              doneAt: BucketItem.parseSavedAt("2026·03·22"),
              via: nil, url: nil, savedAt: "2026·02·28"),
        .init(id: 15, title: "河津桜を見にいく", priority: .maybe,
              seasons: [.season(.spring), .month(3)], tags: ["travel", "leisure"], meta: "",
              done: true, doneAt: BucketItem.parseSavedAt("2026·03·01"),
              via: nil, url: nil, savedAt: "2026·02·10"),
        .init(id: 16, title: "苺狩り", priority: .maybe, seasons: [.month(2)],
              tags: ["food", "leisure"], meta: "", done: true,
              doneAt: BucketItem.parseSavedAt("2026·02·15"),
              via: nil, url: nil, savedAt: "2026·01·25"),
        .init(id: 17, title: "初詣に行く", priority: .top, seasons: [.month(1)],
              tags: ["leisure"], meta: "", done: true,
              doneAt: BucketItem.parseSavedAt("2026·01·03"),
              via: nil, url: nil, savedAt: "2025·12·20"),
    ]
}

// MARK: - Tweaks
// Mirror the Tweaks panel — these settings live in AppStore.

struct Tweaks: Codable, Equatable {
    var seasonNudge: Bool = true
    var weekendNudge: Bool = true
    var monthEndNudge: Bool = true
    var autoClassify: Bool = true
    var yearGoal: Int = 100         // default annual goal — fallback for years without an override
    var yearGoals: [Int: Int] = [:] // per-year goal overrides (year → goal)
    var userName: String = "あなた"

    init() {}

    // Tolerant decode — fields added in later versions fall back to their
    // defaults instead of discarding the user's whole settings blob.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seasonNudge = (try? c.decode(Bool.self, forKey: .seasonNudge)) ?? true
        weekendNudge = (try? c.decode(Bool.self, forKey: .weekendNudge)) ?? true
        monthEndNudge = (try? c.decode(Bool.self, forKey: .monthEndNudge)) ?? true
        autoClassify = (try? c.decode(Bool.self, forKey: .autoClassify)) ?? true
        yearGoal = (try? c.decode(Int.self, forKey: .yearGoal)) ?? 100
        yearGoals = (try? c.decode([Int: Int].self, forKey: .yearGoals)) ?? [:]
        userName = (try? c.decode(String.self, forKey: .userName)) ?? "あなた"
    }
}

// MARK: - Filters

// Done / not-done is a filter axis like the others — empty selection shows both.
enum ItemStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case open, done
    var id: String { rawValue }
    var ja: String { self == .open ? "未達成" : "達成" }
}

// Which achievement year the report and list are scoped to. `.all` is the
// lifetime view; `.year` pins a single calendar year. Defaults to the current
// year so "達成実績" reads as this year unless the user reaches back.
enum YearScope: Equatable, Hashable {
    case all          // すべて（累計）
    case year(Int)    // 特定の年
}

struct Filters: Equatable, Codable {
    var priority: Set<Priority> = []
    var seasons: Set<SeasonTag> = []
    var tags: Set<String> = []
    var statuses: Set<ItemStatus> = []

    var activeCount: Int { priority.count + seasons.count + tags.count + statuses.count }
    var isEmpty: Bool { activeCount == 0 }

    mutating func clear() {
        priority.removeAll(); seasons.removeAll(); tags.removeAll(); statuses.removeAll()
    }
}

// The user's persisted view configuration — sort field, sort direction, and
// the active filter selection. Saved as a single blob so it survives launches.
struct ViewPrefs: Codable, Equatable {
    var sortMode: SortMode = .recommended
    var sortAscending: Bool = false
    var filters: Filters = Filters()
}

enum SortMode: String, Codable, CaseIterable, Identifiable {
    case recommended, priority, added, season, name, completed
    var id: String { rawValue }
    var ja: String {
        switch self {
        case .recommended: return "おすすめ順"
        case .priority:    return "優先度順"
        case .added:       return "追加順"
        case .season:      return "季節順"
        case .name:        return "名前順"
        case .completed:   return "達成順"
        }
    }
    // Human labels for the two directions, per mode. `.down` is the natural
    // order sort() produces; `.up` is its reverse. Concrete words ("新しい順"
    // / "古い順") read far more clearly than abstract 昇順/降順.
    var directionLabels: (down: String, up: String) {
        switch self {
        case .recommended: return ("標準", "逆順")
        case .priority:    return ("高い順", "低い順")
        case .added:       return ("新しい順", "古い順")
        case .season:      return ("近い順", "遠い順")
        case .name:        return ("あ→ん", "ん→あ")
        case .completed:   return ("達成が先", "未達成が先")
        }
    }
}

// MARK: - AppStore
// Single source of truth for items, custom tags, filters, sort, tweaks,
// transient sheet/toast state. Mirrors the React App() component.

final class AppStore: ObservableObject {

    // Persistent
    @Published var items: [BucketItem] {
        didSet { persistDocument() }
    }
    @Published var customTags: [TagDef] {
        didSet { persistDocument() }
    }

    // Set when the store on disk was present but unreadable at launch. The UI
    // surfaces a gentle notice instead of pretending the (now empty) working
    // set is the user's real data — and we avoid auto-persisting over the file.
    @Published var storageUnreadable: Bool = false
    @Published var tweaks: Tweaks {
        didSet { persistTweaks() }
    }

    // View configuration — persisted across launches as a single ViewPrefs blob.
    @Published var filters = Filters() { didSet { persistPrefs() } }
    @Published var sortMode: SortMode = .recommended { didSet { persistPrefs() } }
    @Published var sortAscending: Bool = false { didSet { persistPrefs() } }

    // Transient
    // Which achievement year the list is scoped to. Kept out of ViewPrefs on
    // purpose: it resets to the current year every launch, so it never goes
    // stale (a persisted "2025" would silently hide this year's items next
    // January). Only filters done items — open plans always show.
    @Published var achievementYear: YearScope = .year(Clock.year)
    @Published var nudgeDismissed = false
    @Published var toast: String = ""
    // Undo action attached to the most recent toast (e.g. "削除した。元に戻す").
    // Cleared when the toast times out or the action runs.
    @Published var toastUndo: (() -> Void)? = nil
    @Published var toastUndoLabel: String? = nil
    @Published var selectedTab: Tab = .home {
        didSet {
            if oldValue != selectedTab { Haptics.select() }
        }
    }

    // Drives the first-launch onboarding cover. Seeded from the persisted flag
    // in init; flipped off (and persisted) when the walkthrough finishes.
    @Published var showOnboarding: Bool = false

    enum Tab: Hashable { case home, records, settings }

    // Soft-delete buffers used to power Undo on remove(id:) / removeMany(ids:).
    private var pendingUndo: (item: BucketItem, index: Int)?
    private var pendingUndoMany: [(item: BucketItem, index: Int)]?
    private var toastToken: UUID = UUID()

    private var nextId: Int

    init() {
        // Move any pre-App-Group data into the shared suite, then into the
        // file-coordinated store, before the first read — so existing users
        // keep their list across both migrations.
        Storage.migrateFromStandardIfNeeded()
        SharedStore.migrateLegacyIfNeeded()
        var loadedItems: [BucketItem]
        var loadedTags: [TagDef]
        switch SharedStore.load() {
        case .loaded(let doc):
            loadedItems = doc.items
            loadedTags = doc.customTags
        case .absent:
            // Fresh install (or an emptied store that was never persisted): start
            // with a genuinely empty list. Seed.items is prototype/demo content and
            // must never ship to real users — a new user sees the empty state
            // ("＋ ボタンから追加できます") and the onboarding walkthrough instead.
            // (Screenshot mode below still overrides with curated demo data.)
            // Built-in tags come from Tags.defaults; no demo custom tags are seeded.
            loadedItems = []
            loadedTags = []
        case .unreadable:
            // Data exists but can't be parsed. Do NOT seed/overwrite — keep an
            // empty working set (no didSet in init, so the file stays intact for
            // recovery) and flag it so the UI can warn rather than wipe.
            loadedItems = []
            loadedTags = Seed.customTags
            self.storageUnreadable = true
        }
        // Screenshot mode (DEBUG): override with curated demo data + a pinned
        // date so App Store captures are consistent. No effect in Release.
        if Screenshots.isOn {
            Clock.override = Seed.screenshotDate
            loadedItems = Seed.screenshotItems
            loadedTags = Seed.customTags
        }
        self.items = loadedItems
        self.customTags = loadedTags
        self.tweaks = Storage.loadTweaks() ?? Tweaks()
        self.nextId = AppStore.nextId(after: loadedItems)
        // Restore the saved sort + filter configuration. Assigning in init does
        // not trigger the didSet observers, so no redundant write-back here.
        let prefs = Storage.loadPrefs() ?? ViewPrefs()
        self.filters = prefs.filters
        self.sortMode = prefs.sortMode
        self.sortAscending = prefs.sortAscending
        // Show the walkthrough on the very first launch (and any explicit replay
        // from 設定). Assigning here doesn't fire the didSet, which is fine.
        self.showOnboarding = !Storage.onboardingDone
        // Screenshot mode: skip onboarding and open the requested tab.
        if Screenshots.isOn {
            self.showOnboarding = false
            self.tweaks.yearGoal = 12   // a friendly, on-pace goal for the report

            switch Screenshots.screen {
            case "records":  self.selectedTab = .records
            case "settings": self.selectedTab = .settings
            default:         self.selectedTab = .home
            }
        }
    }

    // MARK: onboarding

    // Called when the user reaches the end of the walkthrough (or skips it).
    // Persists the flag so it never reappears on its own.
    func completeOnboarding() {
        Storage.onboardingDone = true
        showOnboarding = false
    }

    // Re-show the walkthrough on demand (設定 →「使い方をもう一度見る」).
    func replayOnboarding() {
        showOnboarding = true
    }

    // Next free id given a set of items. Used by init() and reload() so the
    // counter never collides with an id the Share Extension assigned while
    // the app was backgrounded.
    private static func nextId(after items: [BucketItem]) -> Int {
        (items.map(\.id).max() ?? 0) + 1
    }

    // Re-read the shared store and recompute the id counter. Called on
    // foreground (scenePhase .active) so items captured via the Share
    // Extension show up without an app relaunch. Only writes back through the
    // didSet observers, which re-persist identical data — harmless.
    func reload() {
        switch SharedStore.load() {
        case .loaded(let doc):
            // A successful read clears any earlier "unreadable" state.
            storageUnreadable = false
            // Skip the churn (and the didSet re-persist) when nothing changed.
            guard doc.items != items || doc.customTags != customTags else {
                if let t = Storage.loadTweaks() { tweaks = t }
                return
            }
            items = doc.items
            customTags = doc.customTags
            nextId = AppStore.nextId(after: doc.items)
        case .absent, .unreadable:
            // Nothing good to load — keep the current working set rather than
            // replacing it with empty/seed data.
            break
        }
        if let t = Storage.loadTweaks() { tweaks = t }
    }

    // MARK: derived

    // Per-year goal, falling back to the default annual goal for years the
    // user hasn't set explicitly.
    func goal(forYear y: Int) -> Int { tweaks.yearGoals[y] ?? tweaks.yearGoal }

    // Persisted via the tweaks didSet observer.
    func setGoal(_ v: Int, forYear y: Int) { tweaks.yearGoals[y] = v }

    var allTags: [TagDef] { Tags.defaults + customTags }

    func tagMeta(for key: String) -> TagDef {
        allTags.first(where: { $0.key == key })
            ?? TagDef(key: key, ja: key, builtin: false)
    }

    // MARK: mutation — items

    func toggle(id: Int) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        // Mutate a local copy and assign once so the store persists a single time.
        var next = items
        next[idx].done.toggle()
        let nowDone = next[idx].done
        if nowDone {
            // Respect an existing date — don't clobber it with today when a
            // mis-tapped item is toggled off and back on.
            if next[idx].doneAt == nil { next[idx].doneAt = Clock.today }
        }
        // Keep doneAt when un-checking so an accidental off/on round-trip
        // preserves the original date. The report only counts done items.
        items = next
        if nowDone {
            Haptics.success()
            flash(doneLine())
        } else {
            Haptics.light()
            flash("未達成に戻しました。")
        }
    }

    // MARK: mutation — selection (ephemeral, not persisted)

    @Published var selection: Set<Int> = []

    var hasSelection: Bool { !selection.isEmpty }

    func toggleSelection(_ id: Int) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        Haptics.light()
    }

    func clearSelection() { selection.removeAll() }

    // Mail-style selection mode. Leaving it clears the current selection.
    @Published var selectionMode: Bool = false

    func setSelectionMode(_ on: Bool) {
        // Animate the toggle so the selection circles slide in / out and the
        // rows shift like Mail's edit mode.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            selectionMode = on
            if !on { selection.removeAll() }
        }
    }

    // Select-all operates on the currently shown (filtered) items.
    var visibleIDs: [Int] { filtered().map(\.id) }

    var allVisibleSelected: Bool {
        let v = visibleIDs
        return !v.isEmpty && Set(v).isSubset(of: selection)
    }

    func toggleSelectAllVisible() {
        if allVisibleSelected { selection.subtract(visibleIDs) }
        else { selection.formUnion(visibleIDs) }
        Haptics.light()
    }

    // Bulk tag add/remove — per-tag, so tags not touched here stay untouched on
    // each item (e.g. removing A and adding C leaves an item's B in place).
    func addTag(_ key: String, to ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        var next = items
        for i in next.indices where ids.contains(next[i].id) {
            if !next[i].tags.contains(key) { next[i].tags.append(key) }
        }
        items = next
        Haptics.light()
    }

    func removeTag(_ key: String, from ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        var next = items
        for i in next.indices where ids.contains(next[i].id) {
            next[i].tags.removeAll { $0 == key }
        }
        items = next
        Haptics.light()
    }

    // How a tag covers the current selection: every / some / none of them.
    func tagCoverage(_ key: String, in ids: Set<Int>) -> TagCoverage {
        let sel = items.filter { ids.contains($0.id) }
        guard !sel.isEmpty else { return .none }
        let n = sel.filter { $0.tags.contains(key) }.count
        return n == 0 ? .none : (n == sel.count ? .all : .some)
    }

    // Bulk set priority (overwrites all selected).
    func setPriority(_ p: Priority, for ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        var next = items
        for i in next.indices where ids.contains(next[i].id) { next[i].priority = p }
        items = next
        Haptics.light()
        flash("優先度を変更しました。")
    }

    // The shared priority of the selection, or nil if they differ.
    func priorityCoverage(in ids: Set<Int>) -> Priority? {
        let sel = items.filter { ids.contains($0.id) }
        guard let first = sel.first else { return nil }
        return sel.allSatisfy { $0.priority == first.priority } ? first.priority : nil
    }

    // Bulk mark done / not-done. When `date` is given, all become that date;
    // otherwise an existing date is kept and a missing one defaults to today.
    func setDone(ids: Set<Int>, done: Bool, date: Date? = nil) {
        guard !ids.isEmpty else { return }
        var next = items
        for i in next.indices where ids.contains(next[i].id) {
            if done {
                next[i].done = true
                if let date { next[i].doneAt = date }
                else if next[i].doneAt == nil { next[i].doneAt = Clock.today }
            } else {
                next[i].done = false   // keep doneAt
            }
        }
        items = next   // single didSet → single persist
        Haptics.success()
        flash(done ? "\(ids.count)件を達成にしました。" : "\(ids.count)件を未達成に戻しました。")
    }

    func removeMany(ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        let n = ids.count
        // Capture each removed item with its original index so Undo can restore
        // them in place — bulk delete is otherwise irreversible (unlike single).
        let removed = items.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { (item: $0.element, index: $0.offset) }
        pendingUndoMany = removed
        items.removeAll { ids.contains($0.id) }
        Haptics.warning()
        flash("\(n)件を削除しました。", duration: 3.5,
              undoLabel: "元に戻す",
              undo: { [weak self] in
                  guard let self, let pending = self.pendingUndoMany else { return }
                  var next = self.items
                  // Re-insert ascending by original index so positions line up.
                  for entry in pending.sorted(by: { $0.index < $1.index }) {
                      next.insert(entry.item, at: min(entry.index, next.count))
                  }
                  self.items = next
                  self.pendingUndoMany = nil
                  Haptics.light()
              })
    }

    // Single-item achievement-date edit (used by the detail sheet).
    func setDoneAt(id: Int, date: Date) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var next = items
        next[idx].doneAt = date
        items = next
    }

    // Mark a single item done with an explicit achievement date — used by the
    // detail sheet where the user picks the 年月 before tapping 達成. Shares the
    // celebration copy/haptics with `toggle`.
    func markDone(id: Int, date: Date) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var next = items
        next[idx].done = true
        next[idx].doneAt = date
        items = next
        Haptics.success()
        flash(doneLine())
    }

    // Checking something off is the product's reward moment — the copy
    // celebrates the milestone instead of confirming a CRUD op.
    private func doneLine() -> String {
        let doneThisYear = items.filter {
            $0.done && ($0.doneAt.map { Clock.calendar.component(.year, from: $0) } == Clock.year)
        }.count
        return "達成しました。今年 \(doneThisYear) 件目です。"
    }

    func remove(id: Int) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items[idx]
        pendingUndo = (removed, idx)
        items.remove(at: idx)
        Haptics.warning()
        flash("削除しました。", duration: 3.5,
              undoLabel: "元に戻す",
              undo: { [weak self] in
                  guard let self else { return }
                  guard let pending = self.pendingUndo, pending.item.id == id else { return }
                  let insertAt = min(pending.index, self.items.count)
                  self.items.insert(pending.item, at: insertAt)
                  self.pendingUndo = nil
                  Haptics.light()
              })
    }

    func update(id: Int, title: String, priority: Priority,
                seasons: [SeasonTag], tags: [String], meta: String,
                url: String? = nil) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        // Edit a local copy and assign once, so the five field updates persist
        // as a single write instead of five.
        var next = items
        next[idx].title = title
        next[idx].priority = priority
        next[idx].seasons = seasons
        next[idx].tags = tags
        next[idx].meta = meta
        // URL is editable like any other field. Keep the existing provenance
        // label (e.g. "共有") when the link stays; only label a freshly-added
        // link "URL"; clear both when the link is removed.
        let trimmed = url?.trimmingCharacters(in: .whitespaces)
        if let trimmed, !trimmed.isEmpty {
            next[idx].url = trimmed
            if next[idx].via == nil { next[idx].via = "URL" }
        } else {
            next[idx].url = nil
            next[idx].via = nil
        }
        items = next
        Haptics.light()
        flash("保存しました。")
    }

    @discardableResult
    func add(title: String, priority: Priority,
             seasons: [SeasonTag], tags: [String],
             meta: String, via: String? = nil, url: String? = nil,
             autoPrio: Bool = false, autoSeasons: Bool = false) -> BucketItem {
        let id = nextId; nextId += 1
        let item = BucketItem(
            id: id, title: title, priority: priority,
            seasons: seasons.isEmpty ? [.any] : seasons,
            tags: tags, meta: meta, done: false,
            via: via, url: url,
            savedAt: BucketItem.savedAtFormatter.string(from: Clock.today)
        )
        items.insert(item, at: 0)
        Haptics.success()
        if autoPrio && autoSeasons {
            flash("自動入力で保存しました。")
        } else {
            flash("保存しました。")
        }
        return item
    }

    // MARK: mutation — custom tags

    @discardableResult
    func addCustomTag(_ label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = allTags.first(where: { $0.ja == trimmed }) {
            return existing.key
        }
        guard customTags.count < Tags.maxCustom else {
            flash("カスタムタグは\(Tags.maxCustom)個までです。")
            return nil
        }
        // UUID-based key: collision-free even when two tags are added in the
        // same second (a second-resolution timestamp key was not).
        let key = "c-" + UUID().uuidString
        customTags.append(TagDef(key: key, ja: trimmed, builtin: false))
        flash("「\(trimmed)」を追加しました。")
        return key
    }

    func renameCustomTag(key: String, to label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let idx = customTags.firstIndex(where: { $0.key == key }) else { return }
        customTags[idx].ja = trimmed
    }

    func removeCustomTag(key: String) {
        customTags.removeAll { $0.key == key }
        // Strip the tag off every item in one pass, then assign once — the old
        // per-index mutation re-persisted the whole document N times (O(N²)).
        var next = items
        for i in next.indices { next[i].tags.removeAll { $0 == key } }
        items = next
        filters.tags.remove(key)
        flash("タグを削除しました。")
    }

    // MARK: toast

    func flash(_ msg: String,
               duration: TimeInterval = 1.8,
               undoLabel: String? = nil,
               undo: (() -> Void)? = nil) {
        let token = UUID()
        toastToken = token
        toast = msg
        toastUndo = undo
        toastUndoLabel = undoLabel
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            // Only clear if no newer toast has been posted in the meantime.
            if self.toastToken == token {
                self.toast = ""
                self.toastUndo = nil
                self.toastUndoLabel = nil
                self.pendingUndo = nil
                self.pendingUndoMany = nil
            }
        }
    }

    // Invoked by the toast's action button. Runs the undo block, then clears
    // toast state immediately so the row doesn't linger after restoring.
    func runToastUndo() {
        let action = toastUndo
        toast = ""
        toastUndo = nil
        toastUndoLabel = nil
        action?()
    }

    // MARK: persistence

    // Items and custom tags are one document, written together so they stay
    // consistent. The host replaces the whole document (it's the source of
    // truth for its session and reloads on foreground to absorb the extension).
    private func persistDocument() {
        SharedStore.save(StoreDocument(items: items, customTags: customTags))
    }
    private func persistTweaks() { Storage.saveTweaks(tweaks) }
    private func persistPrefs() {
        Storage.savePrefs(ViewPrefs(sortMode: sortMode,
                                    sortAscending: sortAscending,
                                    filters: filters))
    }
}

// MARK: - Persisted document (items + custom tags)

// The user's list and their custom tags travel together as one document, so a
// single write keeps the two consistent — an item can never reference a tag
// that a separate, half-finished write hasn't saved yet.
struct StoreDocument: Codable, Equatable {
    var items: [BucketItem] = []
    var customTags: [TagDef] = []
}

// Outcome of a load. Deliberately separates "nothing saved yet" from "data is
// present but unreadable", so a transient or partly-corrupt read never causes
// the store to be replaced with seed/empty data. The previous design decoded
// the whole array with `try?` and treated the resulting nil as "no data",
// which meant a single bad record could silently wipe the entire list.
enum StoreLoad: Equatable {
    case absent
    case loaded(StoreDocument)
    case unreadable
}

// Decodes an array element-by-element, skipping records that fail instead of
// throwing the whole array away. A future schema change that invalidates one
// old item then costs that one item — not the user's entire list.
private struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        out.reserveCapacity(container.count ?? 0)
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                out.append(value)
            } else {
                // A failed decode does not advance the unkeyed container, so
                // step past the unparseable slot to keep the loop moving.
                _ = try? container.decode(Skip.self)
            }
        }
        elements = out
    }
}

private struct LossyDocument: Decodable {
    let items: [BucketItem]
    let customTags: [TagDef]
    // Whether the JSON actually carried our keys. A valid JSON object that has
    // neither key is not one of our documents (some other file / garbage that
    // happened to parse) — the caller treats that as unreadable rather than as
    // a legitimately empty store, so backup recovery can kick in.
    let hasAnyKey: Bool
    enum CodingKeys: String, CodingKey { case items, customTags }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasAnyKey = c.contains(.items) || c.contains(.customTags)
        items = (try? c.decode(LossyArray<BucketItem>.self, forKey: .items))?.elements ?? []
        customTags = (try? c.decode(LossyArray<TagDef>.self, forKey: .customTags))?.elements ?? []
    }
}

// MARK: - SharedStore (App Group file, NSFileCoordinator)
//
// The canonical store for items + custom tags. Lives as a single JSON file in
// the App Group container and is read/written through NSFileCoordinator, so the
// host app and the Share Extension serialize their access and never overwrite
// each other's updates the way two independent UserDefaults read-modify-write
// cycles could. Falls back to the legacy UserDefaults blobs only when the App
// Group container can't be resolved (a misconfigured build), so the app still
// works rather than losing data.

enum SharedStore {
    static let appGroupID = "group.teratech.BucketList"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
    private static var fileURL: URL? { containerURL?.appendingPathComponent("store.json") }
    private static var backupURL: URL? { containerURL?.appendingPathComponent("store.bak.json") }

    static var isAvailable: Bool { fileURL != nil }

    // MARK: read

    static func load() -> StoreLoad {
        guard let url = fileURL else { return Storage.legacyLoad() }
        let primary = read(url)
        if case .unreadable = primary, let bak = backupURL {
            // The live file is damaged (e.g. an interrupted write) — recover the
            // last good snapshot rather than surfacing a wipe.
            let recovered = read(bak)
            if case .loaded(let doc) = recovered {
                // Heal the primary from the backup immediately, so a later write
                // can't back the damaged primary over the still-good backup.
                _ = save(doc)
                return recovered
            }
        }
        return primary
    }

    // Current document, or an empty one if nothing/garbage is stored.
    static func snapshot() -> StoreDocument {
        if case .loaded(let d) = load() { return d }
        return StoreDocument()
    }

    private static func read(_ url: URL) -> StoreLoad {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        let coordinator = NSFileCoordinator()
        var coordErr: NSError?
        var result: StoreLoad = .unreadable
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordErr) { u in
            guard let data = try? Data(contentsOf: u) else { result = .unreadable; return }
            result = interpret(data)
        }
        if coordErr != nil { return .unreadable }
        return result
    }

    private static func interpret(_ data: Data) -> StoreLoad {
        // A 0-byte file is never one of our documents (every write emits a JSON
        // object), and a parsed object lacking both keys isn't ours either —
        // treat both as damaged so backup recovery can run instead of showing an
        // empty list and then overwriting a good backup.
        guard !data.isEmpty,
              let doc = try? JSONDecoder().decode(LossyDocument.self, from: data),
              doc.hasAnyKey else {
            return .unreadable
        }
        return .loaded(StoreDocument(items: doc.items, customTags: doc.customTags))
    }

    // MARK: write

    // Full-document write. The host app is the source of truth for its own
    // session, so it replaces the document wholesale (and reloads on foreground
    // to absorb anything the extension added while it was away).
    @discardableResult
    static func save(_ doc: StoreDocument) -> Bool {
        guard let url = fileURL else { return Storage.legacySave(doc) }
        guard let data = try? JSONEncoder().encode(doc) else { return false }
        let coordinator = NSFileCoordinator()
        var coordErr: NSError?
        var ok = false
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordErr) { u in
            ok = write(data, to: u)
        }
        return ok && coordErr == nil
    }

    // Coordinated read-modify-write. The Share Extension appends through this so
    // it merges into whatever the host last saved instead of clobbering it.
    @discardableResult
    static func mutate(_ body: (inout StoreDocument) -> Void) -> Bool {
        guard let url = fileURL else {
            var doc = Storage.legacyDocument()
            body(&doc)
            return Storage.legacySave(doc)
        }
        let coordinator = NSFileCoordinator()
        var coordErr: NSError?
        var ok = false
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordErr) { u in
            var doc: StoreDocument
            switch interpretFile(u) {
            case .loaded(let d): doc = d
            case .absent:        doc = StoreDocument()
            case .unreadable:    return   // never overwrite damaged data blindly
            }
            body(&doc)
            guard let data = try? JSONEncoder().encode(doc) else { return }
            ok = write(data, to: u)
        }
        return ok && coordErr == nil
    }

    // Reads from inside an existing coordination block (used by mutate()).
    private static func interpretFile(_ url: URL) -> StoreLoad {
        // Mirror read(): a missing file is .absent, but a file that exists and
        // can't be read is .unreadable — NOT .absent. Otherwise mutate() would
        // treat an OS read failure as an empty store and overwrite the existing
        // data with just the new item.
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        return interpret(data)
    }

    // Atomic write, then refresh the one-generation backup FROM the just-written
    // (known-good) primary. Order matters: backing up before the write would
    // copy a possibly-damaged primary over a good backup, and a subsequent
    // failed write would leave both bad. Writing first means the backup is only
    // ever a copy of a successfully-saved document, and a failed write leaves
    // both the primary (atomic) and the backup untouched.
    private static func write(_ data: Data, to url: URL) -> Bool {
        do { try data.write(to: url, options: .atomic) }
        catch { return false }
        if let bak = backupURL {
            try? FileManager.default.removeItem(at: bak)
            try? FileManager.default.copyItem(at: url, to: bak)
        }
        return true
    }

    // One-time import of the pre-file UserDefaults blobs into the file store.
    // Non-destructive: the legacy blobs are left untouched as a safety copy, so
    // a botched migration can always be re-run from the original data.
    static func migrateLegacyIfNeeded() {
        guard isAvailable, case .absent = load() else { return }
        let doc = Storage.legacyDocument()
        if !doc.items.isEmpty || !doc.customTags.isEmpty {
            _ = save(doc)
        }
    }
}

// MARK: - Storage (UserDefaults: tweaks, prefs, onboarding + legacy item blobs)

enum Storage {
    private static let kItems = "bucket-list-v2.items"
    private static let kTags  = "bucket-list-v2.customTags"
    private static let kTweaks = "bucket-list-v2.tweaks"
    private static let kPrefs = "bucket-list-v2.viewPrefs"
    // Flag marking that the one-time .standard → App Group migration ran.
    private static let kMigrated = "bucket-list-v2.migratedToAppGroup"
    // Marks that the first-launch onboarding walkthrough has been completed.
    private static let kOnboarded = "bucket-list-v2.onboardingDone"

    // App Group id shared by the host app and the Share Extension. Both
    // targets declare this group in their entitlements. Falls back to .standard
    // if the group isn't provisioned (e.g. a stray build), so the app still
    // works rather than silently losing data.
    static let appGroupID = "group.teratech.BucketList"
    static let defaults: UserDefaults =
        UserDefaults(suiteName: appGroupID) ?? .standard

    // MARK: legacy item/tag blobs
    // Pre-SharedStore storage. Now read only as the migration source (and as
    // the fallback when the App Group container can't be resolved). Decoded
    // leniently so a single bad record can't take the rest down with it.

    static func legacyDocument() -> StoreDocument {
        StoreDocument(items: legacyItems(), customTags: legacyCustomTags())
    }
    static func legacyLoad() -> StoreLoad {
        let doc = legacyDocument()
        return (doc.items.isEmpty && doc.customTags.isEmpty) ? .absent : .loaded(doc)
    }
    @discardableResult
    static func legacySave(_ doc: StoreDocument) -> Bool {
        if let d = try? JSONEncoder().encode(doc.items) { defaults.set(d, forKey: kItems) }
        if let d = try? JSONEncoder().encode(doc.customTags) { defaults.set(d, forKey: kTags) }
        return true
    }
    private static func legacyItems() -> [BucketItem] {
        guard let data = defaults.data(forKey: kItems) else { return [] }
        return (try? JSONDecoder().decode(LossyArray<BucketItem>.self, from: data))?.elements ?? []
    }
    private static func legacyCustomTags() -> [TagDef] {
        guard let data = defaults.data(forKey: kTags) else { return [] }
        return (try? JSONDecoder().decode(LossyArray<TagDef>.self, from: data))?.elements ?? []
    }

    // MARK: tweaks / prefs (host-written; the extension reads tweaks)

    static func loadTweaks() -> Tweaks? {
        guard let data = defaults.data(forKey: kTweaks) else { return nil }
        return try? JSONDecoder().decode(Tweaks.self, from: data)
    }
    static func saveTweaks(_ t: Tweaks) {
        guard let data = try? JSONEncoder().encode(t) else { return }
        defaults.set(data, forKey: kTweaks)
    }
    static func loadPrefs() -> ViewPrefs? {
        guard let data = defaults.data(forKey: kPrefs) else { return nil }
        return try? JSONDecoder().decode(ViewPrefs.self, from: data)
    }
    static func savePrefs(_ p: ViewPrefs) {
        guard let data = try? JSONEncoder().encode(p) else { return }
        defaults.set(data, forKey: kPrefs)
    }

    // Whether the first-launch onboarding has run. Lives in the shared suite
    // alongside the rest of the store; defaults to false (not yet shown).
    static var onboardingDone: Bool {
        get { defaults.bool(forKey: kOnboarded) }
        set { defaults.set(newValue, forKey: kOnboarded) }
    }

    // One-time copy of existing data from UserDefaults.standard into the
    // App Group container. Runs once (guarded by kMigrated) so users who had
    // data before the Share Extension shipped don't lose it when the store
    // moves to the shared suite. No-op if the group isn't available (the
    // fallback makes `defaults` and `.standard` the same object).
    static func migrateFromStandardIfNeeded() {
        guard defaults !== UserDefaults.standard else { return }
        guard !defaults.bool(forKey: kMigrated) else { return }
        let std = UserDefaults.standard
        // Carry the onboarding flag too, so upgrading users who already finished
        // the walkthrough don't see it again after the suite move.
        if std.bool(forKey: kOnboarded) { defaults.set(true, forKey: kOnboarded) }
        for key in [kItems, kTags, kTweaks, kPrefs] where defaults.data(forKey: key) == nil {
            if let data = std.data(forKey: key) {
                defaults.set(data, forKey: key)
            }
        }
        defaults.set(true, forKey: kMigrated)
    }

    // MARK: - Pro entitlement & free auto-capture quota
    // The Pro unlock is a one-time, non-consumable purchase. StoreKit itself
    // lives only in the host app (see ProStore); the Share Extension can't run
    // StoreKit, so the host mirrors the resolved entitlement into this shared
    // App Group suite. Both targets then read `proEntitled` / the quota from the
    // same place — no StoreKit needed in the extension.
    private static let kProEntitled = "bucket-list-v2.proEntitled"
    private static let kFreeCaptures = "bucket-list-v2.freeCapturesUsed"

    // Free automatic URL imports allowed before Pro is required. A modest taste
    // of the URL→list "magic" so the value is felt before the wall. Lifetime
    // count (not monthly): simplest to reason about and clearest to the user.
    // Tune freely.
    static let freeCaptureLimit = 10

    // Mirror of the StoreKit entitlement. Written by the host app whenever the
    // entitlement changes; read everywhere (including the Share Extension).
    static var proEntitled: Bool {
        get { defaults.bool(forKey: kProEntitled) }
        set { defaults.set(newValue, forKey: kProEntitled) }
    }

    // How many free auto-imports have been consumed so far.
    static var freeCapturesUsed: Int {
        get { defaults.integer(forKey: kFreeCaptures) }
        set { defaults.set(newValue, forKey: kFreeCaptures) }
    }

    // True when an automatic URL reading may run. With Pro disabled it's always
    // allowed (unlimited free release); otherwise Pro unlocks it outright, or the
    // free allowance must not be exhausted yet.
    static var canAutoCapture: Bool {
        guard FeatureFlags.proEnabled else { return true }
        return proEntitled || freeCapturesUsed < freeCaptureLimit
    }

    // Count one consumed free auto-import. No-op when Pro is disabled (unlimited)
    // or once Pro is owned, so an accidental call can't waste anything.
    static func consumeFreeCapture() {
        guard FeatureFlags.proEnabled, !proEntitled else { return }
        freeCapturesUsed += 1
    }
}

// MARK: - Filtering & sorting

extension AppStore {
    func filtered() -> [BucketItem] {
        items.filter { it in
            passes(filterPriority: it) && passes(filterSeasons: it)
                && passes(filterTags: it) && passes(filterStatus: it)
                && passes(filterYear: it)
        }
    }

    // Calendar years that hold at least one achievement, plus the current year
    // (so "今年" is always selectable even before the first done item),
    // ascending. Drives the year selectors on the report and the list.
    var achievementYears: [Int] {
        var years = Set(items.compactMap { it -> Int? in
            guard it.done, let at = it.doneAt else { return nil }
            return Clock.calendar.component(.year, from: at)
        })
        years.insert(Clock.year)
        return years.sorted()
    }

    // Year scope applies only to achievements — open items are future plans and
    // always show regardless of the selected year.
    func passes(filterYear it: BucketItem) -> Bool {
        guard it.done else { return true }
        switch achievementYear {
        case .all:
            return true
        case .year(let y):
            guard let at = it.doneAt else { return false }
            return Clock.calendar.component(.year, from: at) == y
        }
    }

    func passes(filterPriority it: BucketItem) -> Bool {
        filters.priority.isEmpty || filters.priority.contains(it.priority)
    }
    func passes(filterStatus it: BucketItem) -> Bool {
        filters.statuses.isEmpty || filters.statuses.contains(it.done ? .done : .open)
    }
    func passes(filterSeasons it: BucketItem) -> Bool {
        if filters.seasons.isEmpty { return true }
        let itemTags = it.normalizedSeasons
        return filters.seasons.contains { selected in
            if itemTags.contains(selected) { return true }
            if case .season(let s) = selected {
                let monthTags = s.months.map(SeasonTag.month)
                if monthTags.contains(where: itemTags.contains) { return true }
            }
            if case .any = selected, itemTags.contains(.any) { return true }
            return false
        }
    }
    func passes(filterTags it: BucketItem) -> Bool {
        filters.tags.isEmpty || it.tags.contains(where: filters.tags.contains)
    }

    func nowScore(_ it: BucketItem) -> Double {
        let tags = it.normalizedSeasons
        var s = 0.0
        if tags.contains(.month(Clock.month)) { s += 4 }
        if tags.contains(.season(Clock.season)) { s += 2 }
        if tags.contains(.any) { s += 0.4 }
        return s
    }

    // Months from the current month until a season tag is next active (0 = now).
    // "いつでも" carries no specific season, so it sinks below dated items.
    func seasonRank(_ it: BucketItem) -> Int {
        let tags = it.normalizedSeasons
        let cur = Clock.month
        var best = Int.max
        for t in tags {
            switch t {
            case .any:
                best = min(best, 90)
            case .month(let m):
                best = min(best, (m - cur + 12) % 12)
            case .season(let s):
                for m in s.months { best = min(best, (m - cur + 12) % 12) }
            }
        }
        return best == Int.max ? 99 : best
    }

    func sort(_ list: [BucketItem]) -> [BucketItem] {
        let ordered = naturalSorted(list)
        // Direction is applied by reversing the natural order — keeps each
        // mode's comparator in one place and reads as a simple "逆順".
        return sortAscending ? ordered.reversed() : ordered
    }

    private func naturalSorted(_ list: [BucketItem]) -> [BucketItem] {
        list.sorted { a, b in
            // Done-ness deliberately does NOT reorder items — checking something
            // off should leave it in place. Only the "達成順" mode keys on it.
            switch sortMode {
            case .recommended:
                // Priority leads; season relevance breaks ties.
                if a.priority.weight != b.priority.weight {
                    return a.priority.weight > b.priority.weight
                }
                let sa = nowScore(a), sb = nowScore(b)
                if sa != sb { return sa > sb }
            case .priority:
                if a.priority.weight != b.priority.weight {
                    return a.priority.weight > b.priority.weight
                }
            case .added:
                if a.id != b.id { return a.id > b.id }
            case .season:
                let ra = seasonRank(a), rb = seasonRank(b)
                if ra != rb { return ra < rb }
            case .name:
                let c = a.title.localizedCompare(b.title)
                if c != .orderedSame { return c == .orderedAscending }
            case .completed:
                // Achieved items first, most recently achieved on top.
                if a.done != b.done { return a.done && !b.done }
                if a.done && b.done {
                    let da = a.doneAt ?? .distantPast, db = b.doneAt ?? .distantPast
                    if da != db { return da > db }
                }
            }
            return a.id < b.id
        }
    }

    // Per-axis cross-counts used by the filter sheet's chip badges:
    // each axis counts items that pass the OTHER axes' filters.
    func filterCounts() -> (priority: [Priority: Int],
                            seasons: [SeasonTag: Int],
                            tags: [String: Int],
                            statuses: [ItemStatus: Int]) {
        let all = items
        let forPrio = all.filter { passes(filterSeasons: $0) && passes(filterTags: $0) && passes(filterStatus: $0) }
        let forSeas = all.filter { passes(filterPriority: $0) && passes(filterTags: $0) && passes(filterStatus: $0) }
        let forTag  = all.filter { passes(filterPriority: $0) && passes(filterSeasons: $0) && passes(filterStatus: $0) }
        let forStat = all.filter { passes(filterPriority: $0) && passes(filterSeasons: $0) && passes(filterTags: $0) }

        var prio: [Priority: Int] = [:]
        for it in forPrio { prio[it.priority, default: 0] += 1 }

        var seas: [SeasonTag: Int] = [:]
        for it in forSeas {
            let itemTags = it.normalizedSeasons
            for season in Season.order {
                let tag = SeasonTag.season(season)
                let monthTags = season.months.map(SeasonTag.month)
                if itemTags.contains(tag) || monthTags.contains(where: itemTags.contains) {
                    seas[tag, default: 0] += 1
                }
            }
            if itemTags.contains(.any) { seas[.any, default: 0] += 1 }
        }

        var tags: [String: Int] = [:]
        for t in allTags { tags[t.key] = 0 }
        for it in forTag { for k in it.tags { tags[k, default: 0] += 1 } }

        var stat: [ItemStatus: Int] = [.open: 0, .done: 0]
        for it in forStat { stat[it.done ? .done : .open, default: 0] += 1 }

        return (prio, seas, tags, stat)
    }
}

// MARK: - AI classifier (heuristics ported from shared.jsx)

enum Classifier {
    static func priority(_ title: String) -> Priority {
        let s = title
        if matches(s, "オーロラ|アメリカ|海外|世界|留学|移住|本を書|小説") { return .someday }
        if matches(s, "今週|今月|金曜|土曜|日曜|週末|代々木|渋谷|新宿|友達|銭湯|蕎麦") { return .top }
        if matches(s, "花見|桜|花火|紅葉|海水浴|カニ|富士|ドライブ") { return .maybe }
        return .maybe
    }

    static func seasons(_ title: String) -> [SeasonTag] {
        var out = Set<SeasonTag>()
        let s = title
        if matches(s, "桜|花見") { out.insert(.season(.spring)); out.insert(.month(4)) }
        if matches(s, "紫陽花|梅雨") { out.insert(.month(6)) }
        if matches(s, "夏|海|海水浴|花火|BBQ|ビーチ|プール") { out.insert(.season(.summer)) }
        if matches(s, "紅葉|秋") { out.insert(.season(.fall)); out.insert(.month(11)) }
        if matches(s, "雪|スキー|スノボ|イルミ") { out.insert(.season(.winter)) }
        if matches(s, "カニ") {
            out.insert(.season(.winter)); out.insert(.month(11)); out.insert(.month(12))
        }
        if matches(s, "オーロラ") {
            out.insert(.season(.winter))
            [11, 12, 1, 2, 3].forEach { out.insert(.month($0)) }
        }
        if matches(s, "富士") { out.insert(.season(.summer)) }
        // explicit "X月" hints
        if let re = monthRe {
            let ns = s as NSString
            re.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                if let m = m, m.numberOfRanges > 1 {
                    let n = Int(ns.substring(with: m.range(at: 1))) ?? 0
                    if (1...12).contains(n) { out.insert(.month(n)) }
                }
            }
        }
        if out.isEmpty { out.insert(.any) }
        return Array(out)
    }

    static func tags(_ title: String) -> [String] {
        var out: [String] = []
        if matches(title, "蕎麦|食|カニ|レストラン|カフェ|BBQ|ランチ|ディナー|ご飯|寿司|ラーメン|焼肉") { out.append("food") }
        if matches(title, "旅|海外|ツアー|ドライブ|国|アメリカ|アイスランド|京都|沖縄|オーロラ|温泉|富士") { out.append("travel") }
        if matches(title, "映画|花見|花火|紅葉|海水浴|銭湯|ピクニック|キャンプ|釣り|ライブ|フェス|散歩|公園") { out.append("leisure") }
        if matches(title, "買|ショッピング|本|服|時計|スニーカー|家具|カメラ") { out.append("shopping") }
        return out
    }

    // Compiled-regex cache. The keyword patterns are matched many times per
    // keystroke while the user types a title; compiling each pattern on every
    // call (the old `range(of:options:.regularExpression)` / per-call
    // NSRegularExpression) showed up as avoidable work. Classification runs on
    // the main thread, so a plain static cache needs no locking.
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static func regex(_ pattern: String) -> NSRegularExpression? {
        if let cached = regexCache[pattern] { return cached }
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache[pattern] = re
        return re
    }
    private static let monthRe = try? NSRegularExpression(pattern: "(\\d{1,2})月")

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        guard let re = regex(pattern) else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}

// MARK: - NotificationPlanner
// Local notifications backing the 通知 toggles — the timing nudges (concept
// §5-③) delivered when the app is closed. Authorization is requested only
// when the user actively flips a toggle on (requestIfNeeded), never as an
// ambush on first launch.

enum NotificationPlanner {
    private static let ids = [
        "nudge.season.spring", "nudge.season.summer",
        "nudge.season.fall", "nudge.season.winter",
        "nudge.weekend", "nudge.monthEnd",
    ]

    static func sync(tweaks: Tweaks,
                     items: [BucketItem] = [],
                     requestIfNeeded: Bool = false,
                     onDenied: (() -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)

        var requests: [UNNotificationRequest] = []
        if tweaks.seasonNudge {
            for season in Season.order {
                let (title, body) = seasonCopy(season, items: items)
                var date = DateComponents()
                date.month = season.months[0]; date.day = 1; date.hour = 9
                requests.append(request(id: "nudge.season.\(season.rawValue)",
                                        title: title, body: body, date: date))
            }
        }
        if tweaks.weekendNudge {
            var date = DateComponents()
            date.weekday = 6; date.hour = 17   // Friday evening
            let (title, body) = weekendCopy(items: items)
            requests.append(request(id: "nudge.weekend",
                                    title: title, body: body, date: date))
        }
        if tweaks.monthEndNudge {
            var date = DateComponents()
            date.day = 25; date.hour = 19
            let (title, body) = monthEndCopy(items: items)
            requests.append(request(id: "nudge.monthEnd",
                                    title: title, body: body, date: date))
        }
        guard !requests.isEmpty else { return }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                guard requestIfNeeded else { return }
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        requests.forEach { center.add($0) }
                    } else {
                        DispatchQueue.main.async { onDenied?() }
                    }
                }
            case .denied:
                if requestIfNeeded { DispatchQueue.main.async { onDenied?() } }
            default:
                requests.forEach { center.add($0) }
            }
        }
    }

    // MARK: concrete, item-referencing copy
    // A nudge names a specific saved item so it reads as an action
    // ("この夏は「海でBBQ」、いかがですか？"), not a generic "確認しましょう".
    // The item is chosen at schedule time from the current list; sync() runs on
    // every launch / foreground, so the pick stays in step with the list.

    private static func seasonCopy(_ season: Season, items: [BucketItem]) -> (String, String) {
        let title = "\(season.ja)がやってきました"
        if let it = pick(items, season: season) {
            return (title, "この\(season.ja)は「\(it.title)」、いかがですか？")
        }
        return (title, "この\(season.ja)にやりたいこと、確認しませんか？")
    }

    private static func weekendCopy(items: [BucketItem]) -> (String, String) {
        let title = "今週末はどう過ごす？"
        if let it = pick(items, season: Clock.season) ?? pick(items, season: nil) {
            return (title, "今週末は「\(it.title)」、いかがですか？")
        }
        return (title, "今週末にできること、確認しませんか？")
    }

    private static func monthEndCopy(items: [BucketItem]) -> (String, String) {
        let title = "今月もあと少し"
        if let it = pick(items, season: Clock.season) ?? pick(items, season: nil) {
            return (title, "今月のうちに「\(it.title)」、いかがですか？")
        }
        return (title, "今月のうちにやりたいこと、確認しませんか？")
    }

    // Best still-open item for a frame: season-fit first (season or month tag),
    // then priority, then most-recently added. `season: nil` ranks by priority
    // across all open items.
    private static func pick(_ items: [BucketItem], season: Season?) -> BucketItem? {
        func fit(_ it: BucketItem) -> Int {
            guard let season else { return 0 }
            let tags = it.normalizedSeasons
            for t in tags {
                switch t {
                case .season(let s) where s == season: return 2
                case .month(let m) where Season.of(month: m) == season: return 2
                default: continue
                }
            }
            return tags.contains(.any) ? 1 : 0
        }
        let open = items.filter { !$0.done }
        let pool = season == nil ? open : open.filter { fit($0) > 0 }
        return pool.max { a, b in
            let fa = fit(a), fb = fit(b)
            if fa != fb { return fa < fb }
            if a.priority.weight != b.priority.weight { return a.priority.weight < b.priority.weight }
            return a.id < b.id
        }
    }

    private static func request(id: String, title: String, body: String,
                                date: DateComponents) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}

// MARK: - Timing suggestion (concept §5-③)
// "適切なタイミングで差し出す" — pick a frame from where today sits in the
// week / month / season / year, and offer up to 3 open items that fit now.
// Frames in scarcity order: year-end > weekend > month-start > season-close.

struct TimingSuggestion {
    let line: String          // the nudge, e.g. "今週末におすすめ"
    let picks: [BucketItem]   // max 3, best match first
}

extension AppStore {
    func timingSuggestion() -> TimingSuggestion? {
        // Season-fit and intent combined — a "someday / long-vacation" item
        // shouldn't outrank a top-priority one just because its season is
        // now; the suggestion must feel doable inside the frame.
        func score(_ it: BucketItem) -> Double {
            nowScore(it) + Double(it.priority.weight)
        }
        let picks = items
            .filter { !$0.done && nowScore($0) > 0 }
            .sorted { a, b in
                let sa = score(a), sb = score(b)
                if sa != sb { return sa > sb }
                return a.id > b.id
            }
            .prefix(3)
        guard !picks.isEmpty else { return nil }
        return TimingSuggestion(line: frameLine(), picks: Array(picks))
    }

    private func frameLine() -> String {
        if Clock.isYearEnd { return "今年のうちにおすすめ" }
        if Clock.isWeekendish { return "今週末におすすめ" }
        if Clock.isMonthStart { return "今月におすすめ" }
        if Clock.isSeasonClosing { return "\(Clock.season.ja)が終わる前に" }
        return SeasonalCopy.suggestionLine(for: Clock.season)
    }
}

// MARK: - Seasonal copy
// Season-based suggestion line used by the home timing banner's default frame.

enum SeasonalCopy {
    static func suggestionLine(for season: Season) -> String {
        switch season {
        case .spring: return "春におすすめ"
        case .summer: return "夏におすすめ"
        case .fall:   return "秋におすすめ"
        case .winter: return "冬におすすめ"
        }
    }
}
