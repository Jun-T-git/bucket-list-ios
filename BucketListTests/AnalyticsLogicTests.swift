import Testing
import Foundation
@testable import Wishes

// The pure halves of usage analytics: the on-device engagement record (open
// streak / open days), the vocabulary rules that keep event names valid for
// Firebase, and the queue record extensions hand to the host app.
// The SDK itself is never touched here (Analytics.track is a no-op without
// GoogleService-Info.plist / ANALYTICS_DEBUG).

private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    var comps = DateComponents()
    comps.year = y; comps.month = m; comps.day = d; comps.hour = hour
    return Calendar.current.date(from: comps)!
}

struct EngagementTests {
    @Test func firstOpenStartsAStreakOfOne() {
        let (e, newDay) = Engagement.advanced(Engagement(), today: day(2026, 9, 1))
        #expect(newDay)
        #expect(e.streak == 1)
        #expect(e.openDays == 1)
        #expect(e.firstOpen == day(2026, 9, 1))
        #expect(e.lastOpen == day(2026, 9, 1))
    }

    @Test func secondOpenSameDayChangesNothing() {
        let (first, _) = Engagement.advanced(Engagement(), today: day(2026, 9, 1, hour: 8))
        let (again, newDay) = Engagement.advanced(first, today: day(2026, 9, 1, hour: 22))
        #expect(!newDay)
        #expect(again == first)
    }

    @Test func consecutiveDaysExtendTheStreak() {
        var e = Engagement()
        for d in 1...5 { e = Engagement.advanced(e, today: day(2026, 9, d)).0 }
        #expect(e.streak == 5)
        #expect(e.openDays == 5)
    }

    @Test func aGapResetsTheStreakButKeepsOpenDays() {
        var e = Engagement()
        for d in 1...3 { e = Engagement.advanced(e, today: day(2026, 9, d)).0 }
        let (after, newDay) = Engagement.advanced(e, today: day(2026, 9, 7))
        #expect(newDay)
        #expect(after.streak == 1)
        #expect(after.openDays == 4)
        #expect(after.firstOpen == day(2026, 9, 1))
    }

    @Test func daysSinceFirstCountsCalendarDays() {
        let (e, _) = Engagement.advanced(Engagement(), today: day(2026, 9, 1, hour: 23))
        #expect(e.daysSinceFirst(today: day(2026, 9, 1)) == 0)
        #expect(e.daysSinceFirst(today: day(2026, 9, 2, hour: 1)) == 1)
        #expect(e.daysSinceFirst(today: day(2026, 10, 1)) == 30)
    }

    @Test func bucketsAreCoarseAndOrdered() {
        #expect(Engagement.bucket(0) == "0")
        #expect(Engagement.bucket(1) == "1-4")
        #expect(Engagement.bucket(4) == "1-4")
        #expect(Engagement.bucket(5) == "5-9")
        #expect(Engagement.bucket(10) == "10-29")
        #expect(Engagement.bucket(29) == "10-29")
        #expect(Engagement.bucket(30) == "30+")
        #expect(Engagement.bucket(500) == "30+")
    }

    // A record written by an older build (fewer fields) must still decode.
    @Test func tolerantDecodeFillsDefaults() throws {
        let json = #"{"streak": 3}"#.data(using: .utf8)!
        let e = try JSONDecoder().decode(Engagement.self, from: json)
        #expect(e.streak == 3)
        #expect(e.openDays == 0)
        #expect(e.firstOpen == nil)
    }
}

struct AnalyticsVocabularyTests {
    // Firebase: names ≤ 40 chars, [a-zA-Z0-9_], must start with a letter, and
    // must not use the reserved / auto-collected names or prefixes.
    @Test func eventNamesAreFirebaseSafe() {
        let reserved: Set<String> = [
            "app_remove", "app_store_refund", "app_update", "error", "first_open",
            "in_app_purchase", "notification_dismiss", "notification_foreground",
            "notification_open", "notification_receive", "os_update",
            "session_start", "user_engagement",
        ]
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        for e in Analytics.Event.allCases {
            let name = e.rawValue
            #expect(name.count <= 40, "\(name)")
            #expect(name.unicodeScalars.allSatisfy { allowed.contains($0) }, "\(name)")
            #expect(name.first?.isLetter == true, "\(name)")
            #expect(!reserved.contains(name), "\(name)")
            for p in ["firebase_", "google_", "ga_"] { #expect(!name.hasPrefix(p), "\(name)") }
        }
    }

    @Test func eventNamesAreUnique() {
        let names = Analytics.Event.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
    }

    @Test func nudgeKindFromNotificationIdentifier() {
        #expect(Analytics.nudgeKind(fromIdentifier: "nudge.season.spring") == "season")
        #expect(Analytics.nudgeKind(fromIdentifier: "nudge.weekend.3") == "weekend")
        #expect(Analytics.nudgeKind(fromIdentifier: "nudge.weekend") == "weekend")   // legacy id
        #expect(Analytics.nudgeKind(fromIdentifier: "nudge.monthEnd.0") == "month_end")
        #expect(Analytics.nudgeKind(fromIdentifier: "something.else") == "other")
    }

    @Test func seasonLabelCollapsesToOneWord() {
        #expect(Analytics.seasonLabel([]) == "any")
        #expect(Analytics.seasonLabel([.any]) == "any")
        #expect(Analytics.seasonLabel([.season(.summer)]) == "summer")
        #expect(Analytics.seasonLabel([.season(.spring), .season(.fall)]) == "mixed")
    }

    @Test func daysOpenUsesTheSavedAtDate() {
        let it = BucketItem(id: 1, title: "t", priority: .maybe, seasons: [],
                            tags: [], meta: "", done: false, via: nil, url: nil,
                            savedAt: "2026·09·01")
        #expect(Analytics.daysOpen(it, today: day(2026, 9, 11)) == 10)
        let bad = BucketItem(id: 2, title: "t", priority: .maybe, seasons: [],
                             tags: [], meta: "", done: false, via: nil, url: nil,
                             savedAt: "not a date")
        #expect(Analytics.daysOpen(bad, today: day(2026, 9, 11)) == nil)
    }

    // Extension → host hand-off: the queue record must round-trip both value kinds.
    @Test func queuedEventRoundTrips() throws {
        let e = Analytics.QueuedEvent(name: "item_add",
                                      params: ["source": .string("share"), "tag_count": .int(2)])
        let data = try JSONEncoder().encode([e])
        let back = try JSONDecoder().decode([Analytics.QueuedEvent].self, from: data)
        #expect(back == [e])
        #expect(back[0].params["tag_count"]?.raw as? Int == 2)
        #expect(back[0].params["source"]?.raw as? String == "share")
    }
}

struct TweaksAnalyticsFlagTests {
    // Settings saved before the toggle existed must decode as opted-in (the
    // default), and an explicit opt-out must survive.
    @Test func missingFlagDefaultsToEnabled() throws {
        let json = #"{"seasonNudge": true}"#.data(using: .utf8)!
        let t = try JSONDecoder().decode(Tweaks.self, from: json)
        #expect(t.analyticsEnabled == true)
    }

    @Test func explicitOptOutRoundTrips() throws {
        var t = Tweaks()
        t.analyticsEnabled = false
        let back = try JSONDecoder().decode(Tweaks.self, from: JSONEncoder().encode(t))
        #expect(back.analyticsEnabled == false)
    }
}
