import Testing
import Foundation
@testable import Wishes

// Pure-logic tests for the 3-axis model (優先度 × 季節 × タグ).
// These exercise deterministic, UI-independent logic — the kind of quality
// signal an autonomous agent can rely on without booting the app.
// See docs/architecture/data-model.md and docs/workflows/build-and-verify.md.

struct SeasonTagTests {
    @Test func anyKeyRoundTrips() {
        #expect(SeasonTag.from(key: "any") == .any)
        #expect(SeasonTag.any.storageKey == "any")
    }

    @Test func seasonKeysRoundTrip() {
        for s in Season.order {
            #expect(SeasonTag.from(key: s.rawValue) == .season(s))
            #expect(SeasonTag.season(s).storageKey == s.rawValue)
        }
    }

    // Legacy month keys ("m4" 等) must fold into their season so old data
    // survives the removal of month-level granularity (ADR 0001).
    @Test func legacyMonthKeysFoldIntoSeason() {
        #expect(SeasonTag.from(key: "m4") == .season(.spring))   // April → 春
        #expect(SeasonTag.from(key: "m7") == .season(.summer))   // July → 夏
        #expect(SeasonTag.from(key: "m10") == .season(.fall))    // Oct → 秋
        #expect(SeasonTag.from(key: "m1") == .season(.winter))   // Jan → 冬
    }

    @Test func invalidKeysReturnNil() {
        #expect(SeasonTag.from(key: "nope") == nil)
        #expect(SeasonTag.from(key: "m13") == nil)
        #expect(SeasonTag.from(key: "") == nil)
    }
}

struct SeasonTests {
    @Test func monthMapping() {
        #expect(Season.of(month: 3) == .spring)
        #expect(Season.of(month: 8) == .summer)
        #expect(Season.of(month: 11) == .fall)
        #expect(Season.of(month: 12) == .winter)
        #expect(Season.of(month: 1) == .winter)
    }

    @Test func upcomingStartsFromGivenSeason() {
        #expect(Season.upcoming(from: .fall) == [.fall, .winter, .spring, .summer])
        #expect(Season.upcoming(from: .spring).count == 4)
    }
}

struct PriorityTests {
    @Test func weightsAreOrdered() {
        #expect(Priority.top.weight > Priority.maybe.weight)
        #expect(Priority.maybe.weight > Priority.someday.weight)
    }

    @Test func canonicalOrder() {
        #expect(Priority.order == [.top, .maybe, .someday])
    }
}

struct BucketItemTests {
    private func item(seasons: [SeasonTag]) -> BucketItem {
        BucketItem(id: 1, title: "t", priority: .maybe, seasons: seasons,
                   tags: [], meta: "", done: false, via: nil, url: nil,
                   savedAt: "2026·07·05")
    }

    // "空 = いつでも" — an item with no season tags behaves as .any.
    @Test func emptySeasonsNormalizeToAny() {
        #expect(item(seasons: []).normalizedSeasons == [.any])
    }

    @Test func nonEmptySeasonsPassThrough() {
        let s: [SeasonTag] = [.season(.spring), .season(.summer)]
        #expect(item(seasons: s).normalizedSeasons == s)
    }
}

// TimingEngine is the shared "適切なタイミングで差し出す" selection used by both the
// in-app home banner (AppStore.timingSuggestion) and the home-screen widget. Lock
// its behavior so the two surfaces can't silently diverge.
// Serialized: withDate() pins the process-wide Clock.override, so these must not
// interleave with each other (no other suite touches the override).
@Suite(.serialized)
struct TimingEngineTests {
    private func item(id: Int, _ priority: Priority, _ seasons: [SeasonTag],
                      done: Bool = false) -> BucketItem {
        BucketItem(id: id, title: "t\(id)", priority: priority, seasons: seasons,
                   tags: [], meta: "", done: done, via: nil, url: nil, savedAt: "2026·07·05")
    }

    // Fix "now" to a given summer date so season fit + day seed are deterministic
    // regardless of when the test runs. 2026-07-15/16 are Wed/Thu in summer —
    // avoid weekend/month-start/year-end frames so the season line is under test.
    private func withDate(_ y: Int, _ m: Int, _ d: Int, _ body: () -> Void) {
        let saved = Clock.override
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        Clock.override = Calendar.current.date(from: comps)
        defer { Clock.override = saved }
        body()
    }

    private func withSummer(_ body: () -> Void) { withDate(2026, 7, 15, body) }

    @Test func picksSeasonFitOpenItemsOnly() {
        withSummer {
            let items = [
                item(id: 1, .someday, [.season(.summer)]),   // fits now
                item(id: 2, .top, [.season(.winter)]),       // wrong season → excluded
                item(id: 3, .maybe, [], done: true),         // done → excluded
            ]
            let s = TimingEngine.suggestion(items: items)
            #expect(s != nil)
            #expect(s?.picks.map(\.id) == [1])
        }
    }

    // Season fit + priority weight combine: a summer top item outranks a summer
    // someday one, and an "いつでも" (.any) item ranks below a season match.
    @Test func ranksBySeasonFitThenPriority() {
        withSummer {
            let items = [
                item(id: 1, .someday, [.season(.summer)]),   // 2 + 1 = 3
                item(id: 2, .top, [.season(.summer)]),       // 2 + 3 = 5
                item(id: 3, .top, []),                       // .any: 0.4 + 3 = 3.4
            ]
            let s = TimingEngine.suggestion(items: items)
            #expect(s?.picks.map(\.id) == [2, 3, 1])
        }
    }

    // Same-score items rotate by the day so the widget/banner gently changes,
    // while staying deterministic (same day → same order). Two summer .maybe
    // items tie (2 + 2); consecutive days flip their order but keep the same set.
    @Test func tiedItemsRotateByDay() {
        let items = [item(id: 10, .maybe, [.season(.summer)]),
                     item(id: 20, .maybe, [.season(.summer)])]
        var day15: [Int] = [], day16: [Int] = []
        withDate(2026, 7, 15) { day15 = TimingEngine.suggestion(items: items)!.picks.map(\.id) }
        withDate(2026, 7, 16) { day16 = TimingEngine.suggestion(items: items)!.picks.map(\.id) }
        #expect(day15 != day16)                 // order changed with the day
        #expect(Set(day15) == Set(day16))       // same items, just reordered
        #expect(Set(day15) == [10, 20])
    }

    // A clear winner (distinct score) must NOT rotate — only genuine ties do.
    @Test func distinctScoresDoNotRotate() {
        let items = [item(id: 1, .top, [.season(.summer)]),      // 2 + 3 = 5
                     item(id: 2, .someday, [.season(.summer)])]  // 2 + 1 = 3
        var a: [Int] = [], b: [Int] = []
        withDate(2026, 7, 15) { a = TimingEngine.suggestion(items: items)!.picks.map(\.id) }
        withDate(2026, 7, 16) { b = TimingEngine.suggestion(items: items)!.picks.map(\.id) }
        #expect(a == [1, 2])
        #expect(b == [1, 2])
    }

    @Test func returnsNilWhenNothingFits() {
        withSummer {
            let items = [item(id: 1, .top, [.season(.winter)])]
            #expect(TimingEngine.suggestion(items: items) == nil)
        }
    }

    @Test func summerFrameLineWhenNoScarcerFrame() {
        withSummer {
            #expect(TimingEngine.frameLine() == "夏におすすめ")
        }
    }
}

struct FilterCountsTests {
    private func item(_ id: Int, _ priority: Priority, _ seasons: [SeasonTag],
                      _ tags: [String], done: Bool = false) -> BucketItem {
        BucketItem(id: id, title: "t", priority: priority, seasons: seasons,
                   tags: tags, meta: "", done: done, via: nil, url: nil,
                   savedAt: "2026·07·05")
    }

    @Test func emptyListKeepsSelectableTagsAndStatusesAtZero() {
        let counts = Filters().counts(in: [], allTags: Tags.defaults)
        #expect(counts.priority.isEmpty)
        #expect(counts.seasons.isEmpty)
        #expect(counts.tags == Dictionary(uniqueKeysWithValues: Tags.defaults.map { ($0.key, 0) }))
        #expect(counts.statuses == [.open: 0, .done: 0])
    }

    @Test func eachBadgeIgnoresOnlyItsOwnAxis() {
        let items = [
            item(1, .top, [.season(.summer)], ["food"]),
            item(2, .maybe, [.season(.summer)], ["food"]),
            item(3, .top, [.season(.winter)], ["food"]),
            item(4, .top, [.season(.summer)], ["travel"]),
            item(5, .top, [.season(.summer)], ["food"], done: true),
        ]
        let filters = Filters(priority: [.top], seasons: [.season(.summer)],
                              tags: ["food"], statuses: [.open])
        let counts = filters.counts(in: items, allTags: Tags.defaults)
        #expect(counts.priority == [.top: 1, .maybe: 1])
        #expect(counts.seasons == [.season(.summer): 1, .season(.winter): 1])
        #expect(counts.tags["food"] == 1)
        #expect(counts.tags["travel"] == 1)
        #expect(counts.statuses == [.open: 1, .done: 1])
    }

    // Compare all combinations against independent per-axis counts, including
    // legacy duplicates, empty seasons, unknown tags and multi-select OR rules.
    @Test func combinationsPreserveBadgeSemantics() {
        let items = [
            item(1, .top, [], ["food"]),
            item(2, .maybe, [.season(.summer), .season(.summer)], ["travel", "food"]),
            item(3, .someday, [.any, .season(.winter)], ["legacy"], done: true),
            item(4, .top, [.season(.summer), .season(.winter)], [], done: true),
        ]
        let priorities: [Set<Priority>] = [[], [.top], [.maybe, .someday]]
        let seasons: [Set<SeasonTag>] = [[], [.any], [.season(.summer)], [.any, .season(.winter)]]
        let tags: [Set<String>] = [[], ["food"], ["travel", "legacy"], ["missing"]]
        let statuses: [Set<ItemStatus>] = [[], [.open], [.done]]
        for priority in priorities {
            for season in seasons {
                for tag in tags {
                    for status in statuses {
                        let filters = Filters(priority: priority, seasons: season, tags: tag, statuses: status)
                        let actual = filters.counts(in: items, allTags: Tags.defaults)
                        func matches(_ item: BucketItem, ignoring axis: Int) -> Bool {
                            (axis == 0 || priority.isEmpty || priority.contains(item.priority)) &&
                            (axis == 1 || season.isEmpty || !season.isDisjoint(with: item.normalizedSeasons)) &&
                            (axis == 2 || tag.isEmpty || !tag.isDisjoint(with: item.tags)) &&
                            (axis == 3 || status.isEmpty || status.contains(item.done ? .done : .open))
                        }
                        for p in Priority.order {
                            #expect(actual.priority[p, default: 0] == items.filter {
                                $0.priority == p && matches($0, ignoring: 0)
                            }.count)
                        }
                        for s in [SeasonTag.any] + Season.order.map(SeasonTag.season) {
                            #expect(actual.seasons[s, default: 0] == items.filter {
                                $0.normalizedSeasons.contains(s) && matches($0, ignoring: 1)
                            }.count)
                        }
                        for t in Tags.defaults.map(\.key) + ["legacy"] {
                            #expect(actual.tags[t, default: 0] == items.filter {
                                $0.tags.contains(t) && matches($0, ignoring: 2)
                            }.count)
                        }
                        for s in ItemStatus.allCases {
                            #expect(actual.statuses[s] == items.filter {
                                ($0.done ? ItemStatus.done : .open) == s && matches($0, ignoring: 3)
                            }.count)
                        }
                    }
                }
            }
        }
    }
}


// Report history is a read-only view over the existing store. In particular,
// legacy timestamps remain approximations, and no schema migration is needed.
struct AchievementHistoryTests {
    private func item(_ id: Int, _ year: Int?, done: Bool = true) -> BucketItem {
        let date = year.flatMap { Clock.calendar.date(from: DateComponents(year: $0, month: 1, day: 1)) }
        return BucketItem(id: id, title: String(repeating: "長い思い出", count: 30),
                          priority: .maybe, seasons: [.any], tags: [], meta: "",
                          done: done, doneAt: date, via: nil, url: nil, savedAt: "2025·12·31")
    }

    @Test func scopesYearsAndKeepsUndatedOnlyInAll() {
        let items = [item(1, 2025), item(2, 2026), item(3, nil), item(4, 2026, done: false)]
        #expect(AchievementHistory.items(items, scope: .year(2025)).map(\.id) == [1])
        #expect(AchievementHistory.items(items, scope: .year(2026)).map(\.id) == [2])
        #expect(AchievementHistory.items(items, scope: .year(2024)).isEmpty)
        #expect(AchievementHistory.items(items, scope: .all).map(\.id) == [2, 1, 3])
    }

    @Test func stableOrderingAndLargeListPreserveContent() {
        let items = (1...2000).reversed().map { item($0, 2026) }
        let history = AchievementHistory.items(items, scope: .all)
        #expect(history.map(\.id) == Array(1...2000))
        #expect(history.first?.title == items.last?.title)
        #expect(items.first?.id == 2000) // no mutation or truncation
    }

    @Test func undoDeleteAndUndoneAreImmediatelyReflected() {
        var items = [item(1, 2026), item(2, 2026)]
        let deleted = items.removeFirst()
        #expect(AchievementHistory.items(items, scope: .all).map(\.id) == [2])
        items.append(deleted)
        #expect(AchievementHistory.items(items, scope: .all).count == 2)
        items[0].done = false
        #expect(AchievementHistory.items(items, scope: .all).map(\.id) == [1])
        items[0].done = true
        #expect(AchievementHistory.items(items, scope: .all).count == 2)
    }

    @Test func missingAndMalformedLegacyDatesKeepExistingDecodeBehavior() throws {
        for field in ["", ",\"doneAt\":\"invalid\""] {
            let json = "{\"id\":1,\"title\":\"旧記録\",\"priority\":\"maybe\",\"seasons\":[],\"done\":true,\"savedAt\":\"2025·12·31\"\(field)}"
            let item = try JSONDecoder().decode(BucketItem.self, from: Data(json.utf8))
            #expect(item.doneAt == BucketItem.parseSavedAt("2025·12·31"))
            #expect(AchievementHistory.items([item], scope: .year(2025)).count == 1)
            let roundTrip = try JSONDecoder().decode(BucketItem.self, from: JSONEncoder().encode(item))
            #expect(roundTrip == item)
        }
    }
}
