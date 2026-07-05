import Foundation

// A draft "やりたいこと" the user can accept in one tap or freely overwrite.
// It is always a suggestion — never committed data — until the user saves.
struct ItemCandidate {
    var title: String
    var tags: [String]            // tag keys, already validated against existing tags
    var seasons: [SeasonTag]
    var priority: Priority
    var confidence: Double        // 0…1
    var needsUserConfirmation: Bool
    // False only for the `fallback` placeholder — i.e. nothing could be read
    // from the URL. Lets callers distinguish "couldn't read this link at all"
    // from "read something, but be unsure" (low confidence with real signal).
    var readable: Bool = true
    var sourceURL: URL?
    var canonical: URL?

    var bestURL: URL? { canonical ?? sourceURL }

    // Hard cap on a "やりたいこと" title — keeps both generated and typed titles
    // short and glanceable.
    static let titleMaxLength = 30

    // Shown when the model was unsure or metadata was thin, so the UI can nudge
    // the user to glance before saving.
    static let lowConfidenceThreshold = 0.5
    var shouldConfirm: Bool { needsUserConfirmation || confidence < Self.lowConfidenceThreshold }

    // Safe placeholder used whenever nothing better could be derived.
    static func fallback(url: URL?) -> ItemCandidate {
        ItemCandidate(
            title: "このURLを確認する", tags: [], seasons: [.any], priority: .maybe,
            confidence: 0.2, needsUserConfirmation: true, readable: false,
            sourceURL: url, canonical: nil
        )
    }
}

// Keeps generated tags honest: only ever returns keys that exist in the app
// (built-in + custom), de-duplicated, capped at 3. Matches on either the tag
// key or its Japanese label so the model can answer in natural language.
enum TagValidator {
    static func validate(_ raw: [String], against allTags: [TagDef], limit: Int = 3) -> [String] {
        var keys: [String] = []
        for token in raw {
            let needle = token.trimmingCharacters(in: .whitespaces).lowercased()
            guard !needle.isEmpty else { continue }
            guard let hit = allTags.first(where: {
                $0.key.lowercased() == needle || $0.ja.lowercased() == needle
            }) else { continue }
            if !keys.contains(hit.key) { keys.append(hit.key) }
            if keys.count >= limit { break }
        }
        return keys
    }
}
