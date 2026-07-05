import Testing
@testable import Wishes

// Pure-logic tests for the URL→candidate pipeline's honesty guarantees.
// See docs/architecture/capture-pipeline.md and 設計原則 §7/§8.

struct TagValidatorTests {
    // Only keys that exist in the app survive, matched by key or Japanese label.
    @Test func matchesByKeyAndByJapaneseLabel() {
        let tags = Tags.defaults
        #expect(TagValidator.validate(["food"], against: tags) == ["food"])
        #expect(TagValidator.validate(["飲食"], against: tags) == ["food"])
    }

    @Test func dropsUnknownTags() {
        #expect(TagValidator.validate(["不明", "food"], against: Tags.defaults) == ["food"])
        #expect(TagValidator.validate(["nonsense"], against: Tags.defaults) == [])
    }

    @Test func deduplicates() {
        let out = TagValidator.validate(["food", "飲食", "food"], against: Tags.defaults)
        #expect(out == ["food"])
    }

    // Never returns more than the limit (default 3) — keeps tagging light.
    @Test func capsAtLimit() {
        let raw = ["food", "travel", "leisure", "shopping"]
        #expect(TagValidator.validate(raw, against: Tags.defaults).count == 3)
        #expect(TagValidator.validate(raw, against: Tags.defaults, limit: 2).count == 2)
    }

    @Test func ignoresEmptyAndWhitespace() {
        #expect(TagValidator.validate(["", "  ", "food"], against: Tags.defaults) == ["food"])
    }
}

struct ItemCandidateTests {
    private func candidate(confidence: Double, needsConfirm: Bool) -> ItemCandidate {
        ItemCandidate(title: "t", tags: [], seasons: [.any], priority: .maybe,
                      confidence: confidence, needsUserConfirmation: needsConfirm,
                      sourceURL: nil, canonical: nil)
    }

    @Test func shouldConfirmWhenLowConfidence() {
        #expect(candidate(confidence: 0.2, needsConfirm: false).shouldConfirm)
        #expect(!candidate(confidence: 0.9, needsConfirm: false).shouldConfirm)
    }

    @Test func shouldConfirmWhenFlagged() {
        #expect(candidate(confidence: 0.9, needsConfirm: true).shouldConfirm)
    }

    // The fallback placeholder marks the link as unreadable so callers can tell
    // "couldn't read at all" from "read something but unsure".
    @Test func fallbackIsUnreadableAndNeedsConfirm() {
        let f = ItemCandidate.fallback(url: nil)
        #expect(f.readable == false)
        #expect(f.shouldConfirm)
    }

    @Test func titleCapIsThirty() {
        #expect(ItemCandidate.titleMaxLength == 30)
    }
}
