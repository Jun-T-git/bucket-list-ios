import Foundation

// One entry point for turning a URL (typed or shared) into an editable
// candidate. Orchestrates: safety/normalize → on-device metadata → on-device
// model (if available) → rule-based fallback. Always resolves to a usable
// ItemCandidate; it never throws and never blocks on the network forever.
enum CandidateGenerator {

    // From a raw string (paste field). Invalid/unsafe URLs resolve to a safe
    // "confirm this" candidate rather than failing.
    static func make(rawURL: String, memo: String = "", existingTags: [TagDef]) async -> ItemCandidate {
        guard let url = URLSafety.normalized(rawURL) else {
            return ItemCandidate.fallback(url: nil)
        }
        return await make(url: url, memo: memo, existingTags: existingTags)
    }

    static func make(url: URL, memo: String = "", existingTags: [TagDef]) async -> ItemCandidate {
        // Warm the model while the network fetch runs, so the two costs overlap
        // instead of adding up.
        OnDeviceModel.prewarm()
        let metadata = await MetadataFetcher.fetch(url)
        var candidate = await OnDeviceModel.generate(metadata: metadata, memo: memo, existingTags: existingTags)
            ?? RuleBasedCandidate.make(metadata: metadata, memo: memo, allTags: existingTags)
        // Never hand back an over-long title (e.g. a page title that slipped through).
        candidate.title = String(candidate.title.prefix(ItemCandidate.titleMaxLength))
        return candidate
    }
}
