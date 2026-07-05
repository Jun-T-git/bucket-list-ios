import Foundation

// Deterministic fallback used whenever the on-device model is unavailable or
// fails. Reads the on-device metadata + user memo, picks a category by keyword,
// and shapes a "やりたいこと" title. Always returns something usable.
//
// Policy: the title is the *subject* as a noun phrase (体言止め) — never an
// action. Whether the user wants to go to / watch / cook the thing is intent
// that isn't in the shared content, so we don't guess a verb (mirrors the
// on-device model). Category keywords still drive the tag + confidence, just not
// the wording. The user adds a verb in the confirm sheet if they want one.
enum RuleBasedCandidate {

    static func make(metadata: LinkMetadata, memo: String, sharedText: String = "", allTags: [TagDef]) -> ItemCandidate {
        let name = bestName(metadata, memo: memo, sharedText: sharedText)
        let host = metadata.resolvedURL.host?.lowercased() ?? ""
        // Signal text the rules scan. Memo + the share sheet's own text first —
        // strongest hints, especially for X/Instagram posts whose body a server
        // fetch can't reach.
        let signal = [memo, sharedText, metadata.title, metadata.siteName, metadata.placeName,
                      metadata.description, metadata.resolvedURL.absoluteString]
            .compactMap { $0 }.joined(separator: " ")

        // --- Category detection drives only the tag + confidence; the title is
        // always the subject noun phrase. Non-outing kinds are checked first so a
        // recipe/video/product gets its category tag rather than a generic one. ---

        if metadata.sourceType == .youtube ||
            matches(signal, "映画|movie|cinema|trailer|予告|netflix|prime video|配信|作品|アニメ|ドラマ") {
            return finish(name ?? "この作品", tagHints: ["leisure"],
                          confidence: name != nil ? 0.72 : 0.4, needsName: name == nil,
                          metadata: metadata, signal: signal, allTags: allTags)
        }
        if matches(signal, "レシピ|recipe|作り方|材料|献立") {
            return finish(name ?? "この料理", tagHints: ["food"],
                          confidence: name != nil ? 0.66 : 0.4, needsName: name == nil,
                          metadata: metadata, signal: signal, allTags: allTags)
        }
        if isShopping(signal: signal, host: host) {
            return finish(name ?? "この商品", tagHints: ["shopping"],
                          confidence: name != nil ? 0.66 : 0.4, needsName: name == nil,
                          metadata: metadata, signal: signal, allTags: allTags)
        }
        if matches(signal, "解説|入門|方法|やり方|とは|tutorial|guide|how to|講座|まとめ|について調") {
            return finish(name ?? "この記事", tagHints: ["c-learn", "学び"],
                          confidence: name != nil ? 0.58 : 0.4, needsName: name == nil,
                          metadata: metadata, signal: signal, allTags: allTags)
        }

        // --- Outing kinds → place/leisure tags. ---

        if isOuting(signal: signal, host: host, sourceType: metadata.sourceType) {
            let tags = outingTags(signal: signal, host: host)
            if let name {
                return finish(name, tagHints: tags,
                              confidence: outingConfidence(metadata, host: host),
                              needsName: false, metadata: metadata, signal: signal, allTags: allTags)
            }
            // No clean name (e.g. an article headline) — the seasonal phenomenon
            // itself ("紅葉" 等) reads far better than a generic place noun.
            if let (subject, _) = firstKeyword(signal, Self.seasonalPairs) {
                return finish(subject, tagHints: ["leisure"], confidence: 0.55,
                              needsName: true, metadata: metadata, signal: signal, allTags: allTags)
            }
            // Clearly an outing but no name — confirm, and nudge the user to add a
            // memo (esp. for login-walled X/Instagram posts).
            return finish(outingNoun(signal: signal, host: host), tagHints: tags,
                          confidence: 0.4, needsName: true,
                          metadata: metadata, signal: signal, allTags: allTags)
        }

        // Seasonal phenomenon outside an outing context (rare).
        if let (subject, _) = firstKeyword(signal, Self.seasonalPairs) {
            return finish(subject, tagHints: ["leisure"], confidence: 0.55,
                          needsName: true, metadata: metadata, signal: signal, allTags: allTags)
        }

        // A bare name with no detectable category → use it as-is, but ask to confirm.
        if let name {
            return finish(name, tagHints: [], confidence: 0.45,
                          needsName: true, metadata: metadata, signal: signal, allTags: allTags)
        }

        return ItemCandidate.fallback(url: metadata.bestURL)
    }

    // MARK: - category detection

    // True for place / restaurant / event / leisure links. Social posts and Maps
    // default to outings (this is a bucket list — a shared post is usually a
    // place/experience to visit), unless an earlier non-outing kind matched.
    private static func isOuting(signal: String, host: String, sourceType: SourceType) -> Bool {
        if sourceType == .googleMaps || sourceType == .instagram || sourceType == .x || sourceType == .tiktok {
            return true
        }
        if isOutingDomain(host) { return true }
        return matches(signal, outingKeywords)
    }

    private static let outingKeywords =
        // food
        "居酒屋|レストラン|カフェ|喫茶|焼肉|寿司|ラーメン|そば|蕎麦|うどん|バー|ビストロ|食堂|定食|ダイニング|グルメ|" +
        "restaurant|cafe|coffee|bar|dining|bistro|ランチ|ディナー|店|" +
        // event
        "イベント|フェス|ライブ|コンサート|展示|個展|展覧会|美術館|博物館|祭|まつり|マルシェ|マーケット|" +
        "ナイト|花火大会|festival|concert|live|exhibition|market|event|" +
        // place / leisure / sightseeing
        "観光|名所|絶景|スポット|温泉|銭湯|サウナ|神社|寺|公園|水族館|動物園|遊園地|テーマパーク|キャンプ|" +
        "ビーチ|海水浴|ハイキング|登山|spot|onsen|park|zoo|aquarium|leisure|trip|travel|sightsee"

    // Domains that are essentially "a place / event to go to".
    private static let outingDomains = [
        // restaurants / dining reservations
        "tabelog", "hotpepper", "gnavi", "retty", "ikyu", "ozmall", "favy",
        // travel / leisure booking
        "jalan", "asoview", "rurubu", "rakuten.co.jp/travel", "travel.rakuten", "booking.com",
        "jtb", "tripadvisor", "veltra", "kkday", "klook", "walkerplus",
        // event ticketing
        "peatix", "eventbrite", "connpass", "eplus", "pia.jp", "t.pia", "eventernote",
        "doorkeeper", "twipla", "livepocket", "teket",
    ]
    private static func isOutingDomain(_ host: String) -> Bool {
        outingDomains.contains { host.contains($0) }
    }

    private static func isShopping(signal: String, host: String) -> Bool {
        let shopDomains = ["amazon.", "rakuten.co.jp/item", "mercari", "zozo", "shop.", "store."]
        if shopDomains.contains(where: { host.contains($0) }) { return true }
        return matches(signal, "商品|購入|通販|価格|お取り寄せ|buy|shop|product|スニーカー|時計|ガジェット|コスメ|家電")
    }

    // MARK: - tag / confidence / generic-noun helpers

    private static func outingTags(signal: String, host: String) -> [String] {
        if matches(signal, "居酒屋|レストラン|カフェ|喫茶|焼肉|寿司|ラーメン|そば|蕎麦|うどん|バー|ビストロ|食堂|定食|グルメ|restaurant|cafe|café|coffee|bar|dining|ランチ|ディナー") ||
            ["tabelog", "hotpepper", "gnavi", "retty", "ikyu", "favy"].contains(where: { host.contains($0) }) {
            return ["food"]
        }
        if matches(signal, "観光|名所|絶景|温泉|旅行|trip|travel|神社|寺|sightsee") ||
            ["jalan", "rurubu", "booking", "jtb", "tripadvisor"].contains(where: { host.contains($0) }) {
            return ["travel"]
        }
        return ["leisure"]   // events, parks, general outings
    }

    private static func outingConfidence(_ md: LinkMetadata, host: String) -> Double {
        if md.sourceType == .googleMaps { return 0.82 }
        if isOutingDomain(host) { return 0.8 }
        // A name pulled from a social post body is less certain than a venue site.
        if md.sourceType == .instagram || md.sourceType == .x || md.sourceType == .tiktok { return 0.62 }
        return 0.72
    }

    private static func outingNoun(signal: String, host: String) -> String {
        if matches(signal, "イベント|フェス|ライブ|コンサート|展|祭|festival|concert|event") { return "このイベント" }
        if outingTags(signal: signal, host: host) == ["food"] { return "このお店" }
        return "この場所"
    }

    // MARK: - assembly

    private static func finish(_ title: String, tagHints: [String], confidence: Double,
                               needsName: Bool, metadata: LinkMetadata, signal: String,
                               allTags: [TagDef]) -> ItemCandidate {
        let tags = TagValidator.validate(tagHints, against: allTags)
        var seasons = Classifier.seasons(signal)
        if seasons.isEmpty { seasons = [.any] }
        let priority = Classifier.priority(signal)
        let needsConfirm = needsName || confidence < ItemCandidate.lowConfidenceThreshold
        return ItemCandidate(
            title: title, tags: tags, seasons: seasons, priority: priority,
            confidence: confidence, needsUserConfirmation: needsConfirm,
            sourceURL: metadata.resolvedURL, canonical: metadata.canonical
        )
    }

    // MARK: - name extraction

    // The first meaningful proper name across the signals, skipping generic
    // titles ("Home", "Google Maps", a bare brand).
    private static func bestName(_ md: LinkMetadata, memo: String, sharedText: String) -> String? {
        let isSocial = md.sourceType == .instagram || md.sourceType == .x || md.sourceType == .tiktok
        // On a social post the fetched title/siteName is the poster or the app
        // name — never the venue. Prefer the caption / user note; if neither has a
        // clean name, return nil so we ask to confirm rather than saving the
        // poster's name. (The on-device model extracts the venue from the caption
        // when it can; this deterministic path stays conservative.)
        let candidates: [String?] = isSocial
            ? [md.placeName, primaryName(sharedText), primaryName(memo)]
            : [md.placeName, primaryName(md.title), primaryName(md.siteName),
               primaryName(sharedText), primaryName(memo)]
        for c in candidates where !GenericTitle.isGeneric(c) && !isOrgName(c) { return c }
        return nil
    }

    // Org / publisher names ("○○観光協会", "株式会社○○") aren't a place to "go".
    private static func isOrgName(_ s: String?) -> Bool {
        guard let s else { return false }
        return s.range(of: "協会|株式会社|有限会社|一般社団法人|合同会社|財団法人|公式|Inc\\.?|Ltd\\.?|Corp",
                       options: [.regularExpression, .caseInsensitive]) != nil
    }

    // Strip "Page Title | Site Name" style suffixes down to the first segment.
    private static func primaryName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let separators: [Character] = ["|", "｜", "–", "—", "－", "・", "»", "·"]
        var best = raw
        for sep in separators {
            if let chunk = raw.split(separator: sep).first?.trimmingCharacters(in: .whitespaces),
               !chunk.isEmpty, chunk.count < best.count {
                best = chunk
            }
        }
        if let dash = best.range(of: " - ") { best = String(best[..<dash.lowerBound]) }
        // "<poster> on Instagram/X" is the account holder, not a place to go —
        // discard it entirely rather than keep the poster's name as the subject.
        for marker in [" on Instagram", " on X"] {
            if best.range(of: marker) != nil { return nil }
        }
        // Strip a trailing "(@handle)" but keep the display name before it.
        for marker in ["（@", " (@"] {
            if let r = best.range(of: marker) { best = String(best[..<r.lowerBound]) }
        }
        let trimmed = best.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Reject an article headline (a sentence, not a name) — these read badly
        // as "{headline}に行く". The seasonal / confirm fallbacks handle them.
        if trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "！!？?。、…")) != nil { return nil }
        if trimmed.count > 24 { return nil }
        return trimmed
    }

    private static let seasonalPairs: [(needle: String, subject: String)] = [
        ("紅葉", "紅葉"), ("もみじ", "紅葉"), ("桜", "桜"), ("花見", "桜"),
        ("花火", "花火"), ("イルミ", "イルミネーション"), ("ライトアップ", "ライトアップ"),
    ]

    private static func firstKeyword(_ s: String, _ pairs: [(needle: String, subject: String)]) -> (String, String)? {
        for p in pairs where matches(s, NSRegularExpression.escapedPattern(for: p.needle)) {
            return (p.subject, p.needle)
        }
        return nil
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
