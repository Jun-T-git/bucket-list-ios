import WidgetKit
import SwiftUI

// The home-screen widget surfaces the same "適切なタイミングで差し出す" nudge the
// app shows on Home — a frame line ("今週末におすすめ" 等) plus the open items that
// fit right now. It reads the App Group store directly (read-only) and reuses
// TimingEngine, so the widget and the in-app banner never diverge. Tapping the
// widget just opens the app (no deep link by design — plain / familiar, 原則§1).

// MARK: - Entry

struct WishPick: Identifiable {
    let id: Int
    let title: String
    let meta: String            // optional context ("東京・渋谷" 等); "" if none
}

struct WishEntry: TimelineEntry {
    let date: Date
    let line: String
    let picks: [WishPick]        // empty → the widget shows its quiet empty state

    // Shown in the widget gallery / while the real timeline loads.
    static let sample = WishEntry(
        date: Date(),
        line: "今週末におすすめ",
        picks: [
            WishPick(id: 1, title: "海でBBQ", meta: "湘南"),
            WishPick(id: 2, title: "オーロラ", meta: ""),
            WishPick(id: 3, title: "代々木公園のあの蕎麦屋", meta: ""),
            WishPick(id: 4, title: "ナイトプールに行く", meta: ""),
        ]
    )
}

// MARK: - Provider

struct WishesProvider: TimelineProvider {
    func placeholder(in context: Context) -> WishEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (WishEntry) -> Void) {
        completion(context.isPreview ? .sample : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WishEntry>) -> Void) {
        let entry = currentEntry()
        // The frame (weekend / month-start / season-close / year-end) is derived
        // from the calendar, so it can change at midnight even with no data edit.
        // Refresh at the start of tomorrow; item edits trigger an explicit reload
        // from the app / share extension in between.
        let next = Self.nextRefresh(after: entry.date)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    // Reads the shared store and runs the identical selection the app uses.
    // Keeps the top few so the medium family can fill its space; the views prefix
    // to what each size shows.
    private func currentEntry() -> WishEntry {
        let items = SharedStore.snapshot().items
        guard let s = TimingEngine.suggestion(items: items) else {
            return WishEntry(date: Date(), line: "", picks: [])
        }
        let picks = s.picks.prefix(4).map {
            WishPick(id: $0.id, title: $0.title, meta: $0.meta)
        }
        return WishEntry(date: Date(), line: s.line, picks: Array(picks))
    }

    private static func nextRefresh(after date: Date) -> Date {
        let cal = Calendar.current
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))
        return startOfTomorrow ?? date.addingTimeInterval(60 * 60 * 6)
    }
}

// MARK: - Widget

struct WishesWidget: Widget {
    let kind = "WishesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WishesProvider()) { entry in
            WishesWidgetView(entry: entry)
                .containerBackground(Theme.Color.paper0, for: .widget)
        }
        .configurationDisplayName("そっと、いつか")
        .description("今やれる「いつか」を、ホーム画面でそっと差し出します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct WishesWidgetBundle: WidgetBundle {
    var body: some Widget {
        WishesWidget()
    }
}
