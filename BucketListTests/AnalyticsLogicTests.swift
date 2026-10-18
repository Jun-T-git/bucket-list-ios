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


struct CommonMeasurementTests {
    @Test func operationHasExactlyOneTerminalResult() {
        let op = Analytics.Operation(.saveItem)
        let p = op.finishParameters(.error, error: .storage)
        #expect(p == ["schema_version": .int(1), "action_name": .string("save_item"),
                      "result": .string("error"), "error_code": .string("storage")])
        #expect(op.finishParameters(.success) == nil)
        #expect(op.finishParameters(.cancelled) == nil)
    }

    @Test func successAndCancellationContainNoErrorOrContent() {
        for result in [Analytics.Result.success, .cancelled] {
            let p = Analytics.Operation(.importItem).finishParameters(result, error: .storage)!
            #expect(Set(p.keys) == Set(["schema_version", "action_name", "result"]))
            #expect(p["result"] == .string(result.rawValue))
        }
    }

    @Test func unknownScopeRemainsSuppressedAfterUpgrade() throws {
        var state = Analytics.FirstValueState()
        #expect(state.consumeFirstSave(collectionEnabled: true) == nil)
        let data = try JSONEncoder().encode(state)
        var restored = try JSONDecoder().decode(Analytics.FirstValueState.self, from: data)
        restored.applyEvidence(.verifiedNew)
        #expect(restored.consumeFirstSave(collectionEnabled: true) == nil)
    }

    @Test func verifiedScopeEmitsOnlyOnceAndOptOutIsConsumed() {
        var state = Analytics.FirstValueState(verifiedNewScope: true, scopeInitialized: true)
        #expect(state.consumeFirstSave(collectionEnabled: true)?["activation_key"] == .string("first_item_saved"))
        #expect(state.consumeFirstSave(collectionEnabled: true) == nil)
        var disabled = Analytics.FirstValueState(verifiedNewScope: true, scopeInitialized: true)
        #expect(disabled.consumeFirstSave(collectionEnabled: false) == nil)
        #expect(disabled.consumeFirstSave(collectionEnabled: true) == nil)
    }
}


struct FirstValueEvidenceTests {
    @Test func existingHistoryWinsAndCannotBePromoted() {
        var state = Analytics.FirstValueState()
        state.applyEvidence(.existing)
        state.applyEvidence(.verifiedNew)
        #expect(state.existingScope)
        #expect(state.consumeFirstSave(collectionEnabled: true) == nil)
    }

    @Test func positiveProofMustArriveBeforeFirstSave() {
        var unknown = Analytics.FirstValueState()
        #expect(unknown.consumeFirstSave(collectionEnabled: true) == nil)
        unknown.applyEvidence(.verifiedNew)
        #expect(unknown.consumeFirstSave(collectionEnabled: true) == nil)
        var proven = Analytics.FirstValueState(scopeInitialized: true)
        proven.applyEvidence(.verifiedNew)
        #expect(proven.consumeFirstSave(collectionEnabled: true) != nil)
    }

    @Test func coordinatedClaimsSurviveReopenAndRejectCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("measurement.json")
        Analytics.FirstValueStore.update(at: url, legacyData: nil) { state in
            state.scopeInitialized = true
            state.applyEvidence(.verifiedNew)
            return nil
        }
        let first = Analytics.FirstValueStore.update(at: url, legacyData: nil) { $0.consumeFirstSave(collectionEnabled: true) }
        let again = Analytics.FirstValueStore.update(at: url, legacyData: nil) { $0.consumeFirstSave(collectionEnabled: true) }
        #expect(first != nil)
        #expect(again == nil)
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: url)
        #expect(Analytics.FirstValueStore.update(at: url, legacyData: nil) { _ in
            Issue.record("corrupt state must not run the mutation")
            return [:]
        } == nil)
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test func legacyConsumedRecordCannotBeReopened() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let old = Data(#"{"verifiedNewScope":false,"firstSaveConsumed":true}"#.utf8)
        let result = Analytics.FirstValueStore.update(at: url, legacyData: old) { state in
            state.applyEvidence(.verifiedNew)
            return state.consumeFirstSave(collectionEnabled: true)
        }
        #expect(result == nil)
        let saved = try JSONDecoder().decode(Analytics.FirstValueState.self, from: Data(contentsOf: url))
        #expect(saved.firstSaveConsumed)
        #expect(!saved.verifiedNewScope)
    }
}


struct InstallEvidenceTests {
    @Test func productionProofUsesNumericBuildOrder() {
        #expect(Analytics.installEvidence(originalBuild: "11", currentBuild: "12", firstBuild: "11", production: true, bundleMatches: true) == .verifiedNew)
        #expect(Analytics.installEvidence(originalBuild: "9", currentBuild: "12", firstBuild: "11", production: true, bundleMatches: true) == .existing)
        #expect(Analytics.installEvidence(originalBuild: "11.0", currentBuild: "11.0.0", firstBuild: "11", production: true, bundleMatches: true) == .verifiedNew)
        #expect(Analytics.installEvidence(originalBuild: "10", currentBuild: "10", firstBuild: "11", production: true, bundleMatches: true) == .unknown)
    }

    @Test func sandboxMismatchAndMalformedVersionsAreUnknown() {
        #expect(Analytics.installEvidence(originalBuild: "13", currentBuild: "12", firstBuild: "11", production: true, bundleMatches: true) == .unknown)
        #expect(Analytics.installEvidence(originalBuild: "12", currentBuild: "12", firstBuild: "11", production: false, bundleMatches: true) == .unknown)
        #expect(Analytics.installEvidence(originalBuild: "12", currentBuild: "12", firstBuild: "11", production: true, bundleMatches: false) == .unknown)
        for invalid in ["", "0", "11beta", " 11", "11.", "11..1", "1.2.3.4", "9999999999999999999999999999"] {
            #expect(Analytics.installEvidence(originalBuild: invalid, currentBuild: "12", firstBuild: "11", production: true, bundleMatches: true) == .unknown)
            #expect(Analytics.installEvidence(originalBuild: "12", currentBuild: invalid, firstBuild: "11", production: true, bundleMatches: true) == .unknown)
            #expect(Analytics.installEvidence(originalBuild: "12", currentBuild: "12", firstBuild: invalid, production: true, bundleMatches: true) == .unknown)
        }
    }
}


private final class FirstValueClaimCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

struct ConcurrentFirstValueTests {
    @Test func concurrentWritersClaimOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        Analytics.FirstValueStore.update(at: url, legacyData: nil) { state in
            state.scopeInitialized = true
            state.applyEvidence(.verifiedNew)
            return nil
        }
        let counter = FirstValueClaimCounter()
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            let claim = Analytics.FirstValueStore.update(at: url, legacyData: nil) {
                $0.consumeFirstSave(collectionEnabled: true)
            }
            if claim != nil { counter.add() }
        }
        #expect(counter.count == 1)
        let persisted = try JSONDecoder().decode(Analytics.FirstValueState.self, from: Data(contentsOf: url))
        #expect(persisted.firstSaveConsumed)
    }
}


struct FirstValueSnapshotFailureTests {
    @Test func proofCannotPrecedeSuccessfulSnapshot() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        // Initialization failed because the shared destination was unavailable.
        #expect(Analytics.FirstValueStore.update(at: nil, legacyData: nil) { state in
            state.scopeInitialized = true
            return nil
        } == nil)
        // A later file write succeeds, but trusted proof cannot bypass snapshot.
        Analytics.FirstValueStore.update(at: url, legacyData: nil) { state in
            state.applyEvidence(.verifiedNew)
            return nil
        }
        let uninitialized = try JSONDecoder().decode(Analytics.FirstValueState.self, from: Data(contentsOf: url))
        #expect(!uninitialized.scopeInitialized)
        #expect(!uninitialized.verifiedNewScope)
        #expect(Analytics.FirstValueStore.update(at: url, legacyData: nil) {
            $0.consumeFirstSave(collectionEnabled: true)
        } == nil)
        Analytics.FirstValueStore.update(at: url, legacyData: nil) { state in
            state.scopeInitialized = true
            state.applyEvidence(.verifiedNew)
            return state.consumeFirstSave(collectionEnabled: true)
        }
        let final = try JSONDecoder().decode(Analytics.FirstValueState.self, from: Data(contentsOf: url))
        #expect(final.firstSaveConsumed)
        #expect(!final.verifiedNewScope)
    }

    @Test func oldDecodedStateNeedsSnapshotEvenIfProofFlagWasSet() throws {
        let old = Data(#"{"verifiedNewScope":true,"firstSaveConsumed":false}"#.utf8)
        var state = try JSONDecoder().decode(Analytics.FirstValueState.self, from: old)
        #expect(!state.scopeInitialized)
        #expect(!state.verifiedNewScope)
        #expect(state.consumeFirstSave(collectionEnabled: true) == nil)
        state.scopeInitialized = true
        state.applyEvidence(.verifiedNew)
        #expect(state.consumeFirstSave(collectionEnabled: true) == nil)
    }
}
