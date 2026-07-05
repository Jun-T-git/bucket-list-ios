import Testing
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
