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
