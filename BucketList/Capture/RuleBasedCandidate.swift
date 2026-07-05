import Foundation

// Deterministic fallback used whenever the on-device model is unavailable or
// fails. Reads the on-device metadata + user memo, picks a category by keyword,
// and shapes a natural "やりたいこと" title. Always returns something usable.
//
// Policy: anything about a place / restaurant / event / leisure outing —
// including Maps links, reservation sites and shared X/Instagram posts —
// becomes "<具体的な名称>に行く". Only non-outing kinds (watch / buy / cook /
// look-up) use a different verb.
enum RuleBasedCandidate {

    static func make(metadata: LinkMetadata, memo: String, allTags: [TagDef]) -> ItemCandidate {
        let name = bestName(metadata, memo: memo)
        let host = metadata.resolvedURL.host?.lowercased() ?? ""
        // Signal text the rules scan. Memo first — a user note is the strongest
        // hint, especially for X/Instagram posts whose body we can't fully read.
        let signal = [memo, metadata.title, metadata.siteName, metadata.placeName,
                      metadata.description, metadata.resolvedURL.absoluteString]
            .compactMap { $0 }.joined(separator: " ")

        // --- Non-outing kinds first (these never become "に行く"). ---

        if metadata.sourceType == .youtube ||
            matches(signal, "映画|movie|cinema|trailer|予告|netflix|prime video|配信|作品|アニメ|ドラマ") {
            return finish("\(name ?? "この作品")を見る", tagHints: ["leisure"],
                          confidence: name != nil ? 0.72 : 0.4, needsName: name == nil,
                          metadata: metadata, signal: signal, allTags: allTags)
        }
        if matches(signal, "レシピ|recipe|作り方|材料|献立") {
            return finish("\(name ?? "この料理")を作る", tagHints: ["food"],
                          confidence: name != nil ? 0.66 : 0.4, needsName: name == nil,
                          metadata: metadata, signal: signal, allTags: allTags)
        }
        if isShopping(signal: signal, host: host) {
            return finish("\(name ?? "これ")を試す", tagHints: ["shopping"],
                          confidence: name != nil ? 0.66 : 0.4, needsName: name == nil,
                          metadata: metadata, signal: signal, allTags: allTags)
        }
        if matches(signal, "解説|入門|方法|やり方|とは|tutorial|guide|how to|講座|まとめ|について調") {
            return finish("\(name ?? "これ")について調べる", tagHints: ["c-learn", "学び"],
                          confidence: name != nil ? 0.58 : 0.4, needsName: name == nil,
                          metadata: metadata, signal: signal, allTags: allTags)
        }

        // --- Outing kinds → "<名称>に行く". ---

        if isOuting(signal: signal, host: host, sourceType: metadata.sourceType) {
            let tags = outingTags(signal: signal, host: host)
            if let name {
                return finish("\(name)に行く", tagHints: tags,
                              confidence: outingConfidence(metadata, host: host),
                              needsName: false, metadata: metadata, signal: signal, allTags: allTags)
            }
            // No clean name (e.g. an article headline) — a seasonal phenomenon
            // reads far better than "この場所に行く".
            if let (subject, _) = firstKeyword(signal, Self.seasonalPairs) {
                return finish("\(subject)を見に行く", tagHints: ["leisure"], confidence: 0.55,
                              needsName: true, metadata: metadata, signal: signal, allTags: allTags)
            }
            // Clearly an outing but no name — confirm, and nudge the user to add a
            // memo (esp. for login-walled X/Instagram posts).
            return finish("\(outingNoun(signal: signal, host: host))に行く", tagHints: tags,
                          confidence: 0.4, needsName: true,
                          metadata: metadata, signal: signal, allTags: allTags)
        }

        // Seasonal phenomenon outside an outing context (rare).
        if let (subject, _) = firstKeyword(signal, Self.seasonalPairs) {
            return finish("\(subject)を見に行く", tagHints: ["leisure"], confidence: 0.55,
                          needsName: true, metadata: metadata, signal: signal, allTags: allTags)
        }

        // A bare name with no category → default to an outing, but ask to confirm.
        if let name {
            return finish("\(name)に行く", tagHints: [], confidence: 0.45,
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
    private static func bestName(_ md: LinkMetadata, memo: String) -> String? {
        let candidates = [md.placeName, primaryName(md.title), primaryName(md.siteName), primaryName(memo)]
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
        // Drop a "… on Instagram/X" suffix that social cards append.
        for marker in [" on Instagram", " on X", "（@", " (@"] {
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
