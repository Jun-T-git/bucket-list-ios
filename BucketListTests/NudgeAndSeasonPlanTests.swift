import Testing
import Foundation
@testable import Wishes

// NotificationPlanner.plan and SeasonPlan.pending are the pure halves of the
// timing nudges and the report's 「これからの季節」. Lock the two behaviors that
// regressed in the field: nudges naming the same item every time, and
// "いつでも" items all piling into the current season.

private func item(id: Int, _ priority: Priority, _ seasons: [SeasonTag],
                  done: Bool = false) -> BucketItem {
    BucketItem(id: id, title: "t\(id)", priority: priority, seasons: seasons,
               tags: [], meta: "", done: done, via: nil, url: nil, savedAt: "2026·07·05")
}

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var comps = DateComponents()
    comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
    return Calendar.current.date(from: comps)!
}

struct NotificationPlanTests {
    private func tweaks(season: Bool = false, weekend: Bool = false,
                        monthEnd: Bool = false) -> Tweaks {
        var t = Tweaks()
        t.seasonNudge = season; t.weekendNudge = weekend; t.monthEndNudge = monthEnd
        return t
    }

    @Test func weekendNudgesAreFutureFridaysOneWeekApart() {
        let now = date(2026, 9, 19)   // Saturday
        let plan = NotificationPlanner.plan(tweaks: tweaks(weekend: true), items: [], now: now)
        #expect(plan.count == NotificationPlanner.weekendSlots)
        #expect(Set(plan.map(\.id)).count == plan.count)
        let cal = Calendar.current
        for n in plan {
            #expect(n.fireDate > now)
            #expect(cal.component(.weekday, from: n.fireDate) == 6)
            #expect(cal.component(.hour, from: n.fireDate) == 17)
        }
        for (a, b) in zip(plan, plan.dropFirst()) {
            #expect(cal.dateComponents([.day], from: a.fireDate, to: b.fireDate).day == 7)
        }
    }

    // The field bug: every delivery named the same (top-ranked) item.
    @Test func consecutiveNudgesNameDifferentItems() {
        let items = [
            item(id: 1, .top, [.season(.fall)]),
            item(id: 2, .maybe, [.season(.fall)]),
            item(id: 3, .someday, []),
        ]
        // From 9/1 everything up to the end of November is inside fall, so one
        // rotation is under test (a season change swaps the candidate set).
        let plan = NotificationPlanner.plan(tweaks: tweaks(weekend: true, monthEnd: true),
                                            items: items, now: date(2026, 9, 1))
        for (kind, n) in [("nudge.weekend.", 13), ("nudge.monthEnd.", 3)] {
            let bodies = plan.filter { $0.id.hasPrefix(kind) }.prefix(n).map(\.body)
            #expect(bodies.count == n)
            for (a, b) in zip(bodies, bodies.dropFirst()) { #expect(a != b) }
        }
    }

    // A lone candidate can't rotate — it alternates with the generic copy
    // instead of being named on every single delivery.
    @Test func singleCandidateAlternatesWithGenericCopy() {
        let plan = NotificationPlanner.plan(tweaks: tweaks(weekend: true),
                                            items: [item(id: 1, .top, [])], now: date(2026, 9, 1))
        let bodies = plan.map(\.body)
        for (a, b) in zip(bodies, bodies.dropFirst()) { #expect(a != b) }
        #expect(bodies.contains { $0.contains("「t1」") })
    }

    // Every fitting wish gets its turn; 高 comes around more often than 低.
    @Test func rotationCoversAllItemsAndFavorsPriority() {
        let items = [
            item(id: 1, .top, [.season(.fall)]),
            item(id: 2, .someday, [.season(.fall)]),
            item(id: 3, .someday, [.season(.fall)]),
        ]
        // 2026-09-04 … 11-27 = 13 Fridays, all in fall.
        let plan = NotificationPlanner.plan(tweaks: tweaks(weekend: true), items: items,
                                            now: date(2026, 9, 1))
        let bodies = plan.prefix(13).map(\.body)
        func count(_ id: Int) -> Int { bodies.filter { $0.contains("「t\(id)」") }.count }
        #expect(count(1) > 0 && count(2) > 0 && count(3) > 0)
        #expect(count(1) > count(2))
    }

    // Same bonus as TimingEngine.nowScore: a wish that only fits this season comes
    // around more often than an equal-priority "いつでも" one.
    @Test func seasonMatchOutweighsAnytime() {
        let items = [
            item(id: 1, .maybe, [.season(.fall)]),
            item(id: 2, .maybe, []),
            item(id: 3, .maybe, []),
        ]
        let plan = NotificationPlanner.plan(tweaks: tweaks(weekend: true), items: items,
                                            now: date(2026, 9, 1))
        let bodies = plan.prefix(13).map(\.body)   // 13 Fridays, all in fall
        func count(_ id: Int) -> Int { bodies.filter { $0.contains("「t\(id)」") }.count }
        #expect(count(2) > 0 && count(3) > 0)
        #expect(count(1) > count(2))
    }

    // Same-priority wishes are named in a shuffled order that changes every lap
    // — not a fixed cycle (newest-first) — yet each still gets exactly one turn
    // per lap and none is ever named twice in a row, even across laps.
    @Test func equalPriorityItemsAreShuffledEachLap() {
        let items = (1...6).map { item(id: $0, .maybe, []) }
        let plan = NotificationPlanner.plan(tweaks: tweaks(weekend: true), items: items,
                                            now: date(2026, 9, 1))
        let bodies = plan.map(\.body)
        #expect(bodies.count == 24)
        for (a, b) in zip(bodies, bodies.dropFirst()) { #expect(a != b) }
        // Any 6 consecutive deliveries aligned to a lap name all 6 items; find the
        // lap boundary by looking for the first window that is a full permutation.
        let offset = (0..<6).first { o in Set(bodies[o..<(o + 6)]).count == 6
                                          && Set(bodies[(o + 6)..<(o + 12)]).count == 6 }
        #expect(offset != nil)
        guard let o = offset else { return }
        let laps = stride(from: o, to: bodies.count - 5, by: 6).map { Array(bodies[$0..<($0 + 6)]) }
        #expect(laps.count >= 3)
        for lap in laps { #expect(Set(lap).count == 6) }
        #expect(Set(laps).count > 1)   // the order is not the same every lap
    }

    // The no-repeat guarantee must survive lap boundaries (where the shuffle
    // changes) for every list shape — sweep many turns over assorted pools.
    @Test func rotationNeverRepeatsAcrossLapBoundaries() {
        let pools: [[BucketItem]] = [
            (1...2).map { item(id: $0, .top, []) },
            (1...3).map { item(id: $0, .top, []) },
            (1...7).map { item(id: $0, .someday, []) },
            [item(id: 1, .top, []), item(id: 2, .maybe, []), item(id: 3, .maybe, [])],
            [item(id: 1, .top, [.season(.fall)]), item(id: 2, .top, [.season(.fall)]),
             item(id: 3, .someday, []), item(id: 4, .someday, [])],
            (1...4).map { item(id: $0, .top, []) } + (5...9).map { item(id: $0, .maybe, []) }
                + (10...12).map { item(id: $0, .someday, [.season(.fall)]) },
        ]
        for pool in pools {
            let r = NotificationPlanner.Rotation(pool, season: .fall)
            var seen: Set<Int> = []
            for turn in 100_000..<102_000 {
                let a = r.item(turn: turn), b = r.item(turn: turn + 1)
                #expect(a != nil && a?.id != b?.id)
                if let a { seen.insert(a.id) }
            }
            #expect(seen.count == pool.count)   // everyone gets named
        }
    }

    // A date keeps its pick when the plan is rebuilt on a later day — otherwise
    // "the next Friday" would always restart from the top item.
    @Test func replanningKeepsEachDatesPick() {
        let items = (1...5).map { item(id: $0, .maybe, []) }
        let t = tweaks(weekend: true)
        let first = NotificationPlanner.plan(tweaks: t, items: items, now: date(2026, 9, 19))
        let later = NotificationPlanner.plan(tweaks: t, items: items, now: date(2026, 9, 27))
        let byDate = Dictionary(uniqueKeysWithValues: first.map { ($0.fireDate, $0.body) })
        #expect(later.first?.fireDate != first.first?.fireDate)
        for n in later {
            if let earlier = byDate[n.fireDate] { #expect(earlier == n.body) }
        }
    }

    // Season fit is judged at the fire date, not at schedule time.
    @Test func picksFitTheSeasonOfTheFireDate() {
        let items = [
            item(id: 1, .top, [.season(.fall)]),   item(id: 2, .top, [.season(.fall)]),
            item(id: 3, .top, [.season(.winter)]), item(id: 4, .top, [.season(.winter)]),
        ]
        let plan = NotificationPlanner.plan(tweaks: tweaks(weekend: true), items: items,
                                            now: date(2026, 9, 19))
        let cal = Calendar.current
        for n in plan {
            let month = cal.component(.month, from: n.fireDate)
            switch Season.of(month: month) {
            case .fall:   #expect(n.body.contains("「t1」") || n.body.contains("「t2」"))
            case .winter: #expect(n.body.contains("「t3」") || n.body.contains("「t4」"))
            default:      break   // spring: neither fits → falls back to any open item
            }
        }
    }

    @Test func doneItemsAreNeverNamedAndEmptyListFallsBackToGenericCopy() {
        let items = [item(id: 1, .top, [], done: true)]
        let plan = NotificationPlanner.plan(tweaks: tweaks(season: true, weekend: true, monthEnd: true),
                                            items: items, now: date(2026, 9, 19))
        #expect(plan.count == 4 + NotificationPlanner.weekendSlots + NotificationPlanner.monthEndSlots)
        for n in plan { #expect(!n.body.contains("「")) }
    }

    @Test func disabledTogglesScheduleNothing() {
        #expect(NotificationPlanner.plan(tweaks: tweaks(), items: [], now: date(2026, 9, 19)).isEmpty)
    }
}

struct SeasonPlanTests {
    // The field bug: every "いつでも" item landed in the current season.
    @Test func anytimeItemsSpreadAcrossUpcomingSeasons() {
        let items = (1...8).map { item(id: $0, .maybe, []) }
        let plan = SeasonPlan.pending(items: items, from: .fall)
        for s in Season.order { #expect(plan[s]?.count == 2) }
    }

    @Test func anytimeItemsFillSparseSeasonsFirst() {
        var items = (1...4).map { item(id: $0, .maybe, [.season(.winter)]) }
        items += (5...10).map { item(id: $0, .maybe, []) }
        let plan = SeasonPlan.pending(items: items, from: .fall)
        #expect(plan[.winter]?.count == 4)   // already full — takes no いつでも
        #expect(plan[.fall]?.count == 2)
        #expect(plan[.spring]?.count == 2)
        #expect(plan[.summer]?.count == 2)
    }

    // Higher-priority "いつでも" wishes land nearer to now.
    @Test func higherPriorityAnytimeItemsLandSooner() {
        let items = [
            item(id: 1, .someday, []), item(id: 2, .top, []),
            item(id: 3, .maybe, []),   item(id: 4, .someday, []),
        ]
        let plan = SeasonPlan.pending(items: items, from: .fall)
        #expect(plan[.fall]?.map(\.id) == [2])
        #expect(plan[.winter]?.map(\.id) == [3])
        #expect(plan[.spring]?.map(\.id) == [1])
        #expect(plan[.summer]?.map(\.id) == [4])
    }

    @Test func anytimeItemAppearsInExactlyOneSeasonAndDoneIsExcluded() {
        let items = [
            item(id: 1, .top, []),
            item(id: 2, .top, [], done: true),
            item(id: 3, .maybe, [.season(.fall), .season(.winter)]),
        ]
        let plan = SeasonPlan.pending(items: items, from: .fall)
        let all = Season.order.flatMap { plan[$0] ?? [] }.map(\.id)
        #expect(all.filter { $0 == 1 }.count == 1)
        #expect(!all.contains(2))
        #expect(all.filter { $0 == 3 }.count == 2)   // season-tagged: every named season
    }
}
