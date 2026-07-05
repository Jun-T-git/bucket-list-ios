import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Thin wrapper around Apple's on-device Foundation Models. Everything is gated
// on iOS 26 + model availability; callers treat a nil return as "use the
// rule-based fallback". No data ever leaves the device.
enum OnDeviceModel {

    // Returns a validated candidate, or nil if the model is unavailable / errors
    // out (timeout, guardrails, decode failure) — never throws to the caller.
    // Bound on how long we wait for the model before falling back to the
    // rule-based candidate. Real devices answer in ~1s; this caps pathological
    // cases (e.g. the iOS Simulator, which runs the model far slower than
    // hardware) so the user never waits a minute.
    static let timeout: TimeInterval = 8

    static func generate(metadata: LinkMetadata, memo: String, sharedText: String = "",
                         existingTags: [TagDef]) async -> ItemCandidate? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await withTimeout(seconds: timeout) {
                await Self.run(metadata: metadata, memo: memo, sharedText: sharedText, existingTags: existingTags)
            }
        }
        #endif
        return nil
    }

    // Race an async operation against a deadline; returns nil if it doesn't beat
    // the clock (caller then uses the rule-based fallback).
    private static func withTimeout<T>(seconds: TimeInterval,
                                       _ operation: @escaping () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // Warm the model so the first real request skips the ~0.8s cold start. Safe
    // to call eagerly (when a URL field appears) and to call more than once.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else { return }
            LanguageModelSession(model: SystemLanguageModel.default).prewarm()
        }
        #endif
    }
}

// Maps the model's season words (春/夏/秋/冬 or いつでも/その他) to SeasonTags,
// de-duped. Anything not a recognised season is ignored; an empty result means
// "いつでも".
enum SeasonParse {
    static func from(_ raw: [String]) -> [SeasonTag] {
        var seen = Set<Season>()
        var out: [SeasonTag] = []
        for token in raw {
            guard let s = season(from: token.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            if seen.insert(s).inserted { out.append(.season(s)) }
        }
        return out.isEmpty ? [.any] : out
    }
    private static func season(from ja: String) -> Season? {
        switch ja.lowercased() {
        case "春", "spring":            return .spring
        case "夏", "summer":            return .summer
        case "秋", "fall", "autumn":    return .fall
        case "冬", "winter":            return .winter
        default:                        return nil   // 「いつでも」等 → 特定季節なし
        }
    }
}

#if canImport(FoundationModels)

// Structured output the model is constrained to produce.
@available(iOS 26.0, *)
@Generable
struct GeneratedCandidate {
    // The title is the *subject* as a noun phrase — never an action. Whether the
    // user wants to watch / go to / cook the thing is intent that lives in their
    // head, not in the shared content, so we don't guess a verb (a wrong verb is
    // the most visible mistake). The user adds one in the confirm sheet if wanted.
    @Guide(description: "対象の主題を表す名詞句を体言止めで（店名・施設名・作品名・商品名・イベント名・場所名など）。最大30字。『〜に行く』『〜を見る』等の動詞・行動表現は絶対に付けない。ページタイトルや投稿本文をそのままコピーせず、宣伝文句・ハッシュタグ・絵文字・『公式』『完全版』等の飾りを除いて主題だけを残す。特定できなければ空文字")
    var title: String
    @Guide(description: "渡された既存タグの日本語ラベルだけを0〜3個。該当が無ければ空。新しいタグは作らない")
    var tags: [String]
    @Guide(description: "この「やりたいこと」に向いた季節。春・夏・秋・冬 のうち当てはまるものだけ（複数可）。特定の季節に紐づかない・通年なら「いつでも」だけ。")
    var seasons: [String]
    @Guide(description: "確信度。主題をはっきり特定できたら0.8以上、推測が混じるなら0.4〜0.7、主題が不明なら0.3未満")
    var confidence: Double
    @Guide(description: "主題を特定できない、または情報が乏しく人間の確認が必要ならtrue")
    var needsUserConfirmation: Bool
}

@available(iOS 26.0, *)
extension OnDeviceModel {

    static func run(metadata: LinkMetadata, memo: String, sharedText: String, existingTags: [TagDef]) async -> ItemCandidate? {
        let model = SystemLanguageModel(useCase: .contentTagging)
        guard model.availability == .available else { return nil }

        let session = LanguageModelSession(model: model, instructions: instructions(tags: existingTags))
        let prompt = prompt(metadata: metadata, memo: memo, sharedText: sharedText)
        // Extraction/classification wants consistency over creativity — keep it low.
        let options = GenerationOptions(temperature: 0.2)

        do {
            let response = try await session.respond(to: prompt, generating: GeneratedCandidate.self, options: options)
            let g = response.content
            let title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let tags = TagValidator.validate(g.tags, against: existingTags)
            let seasons = SeasonParse.from(g.seasons)
            let priority = Classifier.priority([title, memo].joined(separator: " "))
            return ItemCandidate(
                title: title, tags: tags, seasons: seasons, priority: priority,
                confidence: min(max(g.confidence, 0), 1), needsUserConfirmation: g.needsUserConfirmation,
                sourceURL: metadata.resolvedURL,
                canonical: metadata.canonical
            )
        } catch {
            return nil
        }
    }

    private static func instructions(tags: [TagDef]) -> String {
        // Each tag carries its own description (built-in defaults + user-set), so
        // the model classifies by meaning. This is the single source of truth for
        // tag guidance — no hard-coded category rules here.
        let tagSection = tags.map { t -> String in
            let d = t.desc?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (d?.isEmpty == false) ? "- \(t.ja): \(d!)" : "- \(t.ja)"
        }.joined(separator: "\n")
        return instructionsBody(tagSection: tagSection)
    }

    private static func instructionsBody(tagSection: String) -> String {
        """
        あなたは「やりたいことリスト」の見出し生成器です。日本語で、対象の主題を表す短い名詞句を1つ作ります（体言止め）。

        最重要ルール:
        - 「〜に行く」「〜を見る」「〜を作る」等の動詞・行動表現は絶対に付けない。
          ユーザーがそれを見たいのか実際にやりたいのか等の"意図"はこちらでは判断せず、主題（何についてか）だけを残す。
        - ページタイトルや投稿本文を“そのままコピーしない”。宣伝文句・ハッシュタグ・絵文字・「公式」「完全版」等の飾りを除き、主題の名詞句だけを抜き出す。
        - ユーザーメモがあれば主題の最有力の手がかりとして最優先する。
        - SNS（Instagram/X/TikTok）の投稿では、主題は本文・キャプション・共有本文で紹介されている店・場所・商品・作品・イベント。
          「投稿者名」（アカウント名）は主題にしない——ユーザーは投稿者ではなく、そこで紹介された対象に行きたい/試したいと考えている。
        - 主題を示す固有名詞がどこにも見つからないときは、投稿者名や汎用語で埋めず、needsUserConfirmation=true・confidenceを0.3未満にする。
        - 桜/紅葉/花火/イルミ等の季節語や、料理名・作品名などの特徴語は主題の一部として残す（例:「高尾山の紅葉ライトアップ」）。
        - 最大30字。

        例（左が入力、右が出力。出力に動詞が無いことに注意）:
        - 場所/店名「ABC Cafe」→「ABC Cafe」
        - 投稿本文「渋谷の隠れ家イタリアン Trattoria Rossi に行ってきた。最高」→「Trattoria Rossi」
        - ページタイトル「高尾山 紅葉ライトアップ2026」→「高尾山の紅葉ライトアップ」
        - YouTube「【完全版】新宿ラーメン食べ歩き」→「新宿ラーメン食べ歩き」
        - Amazon「Anker 充電器 65W USB-C 急速…（長い商品名）」→「Anker 65W充電器」
        - レシピ「基本の本格キーマカレーの作り方」→「キーマカレー」
        - サイト名「ABC Cafe / タイトル: ホーム」→「ABC Cafe」
        - 投稿者名「山田太郎」＋本文「渋谷のABC Cafeで最高のラテ☕ #カフェ巡り」→「ABC Cafe」（投稿者名は使わない）
        - 主題が特定できないとき → 『ホーム』『Google Maps』『山田太郎』等の投稿者名・汎用語は使わず、needsUserConfirmation=true・confidenceを0.3未満にする。

        季節(seasons)は、その「やりたいこと」に向いた季節を 春/夏/秋/冬 から選ぶ（複数可）。特定の季節に紐づかない・通年なら「いつでも」だけ。
        目安: 桜・花見・入学=春 / 海・花火・BBQ・プール=夏 / 紅葉・お月見=秋 / 雪・スキー・イルミネーション・カニ・オーロラ=冬。飲食店やカフェなど通年楽しめるものは「いつでも」。

        タグは次の一覧から、内容に最も合うものだけ0〜3個。無ければ空。一覧にないタグは絶対に作りません。
        各タグの説明（例を含む）を根拠に選ぶこと。実際に足を運ぶ「行く場所・お店」を"お買い物"にしない:
        \(tagSection)
        """
    }

    private static func prompt(metadata: LinkMetadata, memo: String, sharedText: String) -> String {
        let isSocial = [.instagram, .x, .tiktok].contains(metadata.sourceType)
        var lines = ["URL種別: \(metadata.sourceType.rawValue)", "URL: \(metadata.bestURL.absoluteString)"]
        if let p = metadata.placeName, !p.isEmpty { lines.append("地図から抽出した場所/店名: \(p)") }
        if let s = metadata.siteName, !s.isEmpty { lines.append("サイト名: \(s)") }
        if let t = metadata.title, !t.isEmpty {
            // On Instagram/X/TikTok the fetched title is the poster (login wall
            // hides the caption), so label it as such — otherwise the model turns
            // "山田太郎" into the title instead of the venue in the body.
            lines.append(isSocial ? "投稿者名（主題にしない）: \(t)" : "ページタイトル: \(t)")
        }
        if let d = metadata.description, !d.isEmpty { lines.append("説明/投稿本文: \(d)") }
        // Text the share sheet handed us — for login-walled apps this is often the
        // only place the real subject appears. Skip it if it just repeats the title.
        let trimmedShared = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedShared.isEmpty, trimmedShared != metadata.title {
            lines.append("共有アプリからの本文/キャプション: \(trimmedShared)")
        }
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("ユーザーメモ: \(trimmedMemo.isEmpty ? "（なし）" : trimmedMemo)")
        return lines.joined(separator: "\n")
    }
}

#endif
