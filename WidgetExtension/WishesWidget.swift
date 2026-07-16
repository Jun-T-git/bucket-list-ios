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
    let priority: Priority
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
            WishPick(id: 1, title: "海でBBQ", priority: .top),
            WishPick(id: 2, title: "オーロラ", priority: .maybe),
            WishPick(id: 3, title: "代々木公園のあの蕎麦屋", priority: .someday),
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
    private func currentEntry() -> WishEntry {
        let items = SharedStore.snapshot().items
        guard let s = TimingEngine.suggestion(items: items) else {
            return WishEntry(date: Date(), line: "", picks: [])
        }
        let picks = s.picks.map { WishPick(id: $0.id, title: $0.title, priority: $0.priority) }
        return WishEntry(date: Date(), line: s.line, picks: picks)
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
