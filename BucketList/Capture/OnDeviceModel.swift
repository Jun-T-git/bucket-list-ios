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

    static func generate(metadata: LinkMetadata, memo: String, existingTags: [TagDef]) async -> ItemCandidate? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await withTimeout(seconds: timeout) {
                await Self.run(metadata: metadata, memo: memo, existingTags: existingTags)
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

#if canImport(FoundationModels)

// Structured output the model is constrained to produce.
@available(iOS 26.0, *)
@Generable
struct GeneratedCandidate {
    @Guide(description: "短い行動表現のタイトル。場所/飲食店/イベント/レジャーは必ず『{固有名詞}に行く』。ページタイトルや投稿本文をそのままコピーせず、名称だけ抽出して変換する")
    var title: String
    @Guide(description: "渡された既存タグの日本語ラベルだけを0〜3個。該当が無ければ空。新しいタグは作らない")
    var tags: [String]
    @Guide(description: "判断の確信度。0.0〜1.0")
    var confidence: Double
    @Guide(description: "情報が乏しく内容確認が必要ならtrue")
    var needsUserConfirmation: Bool
}

@available(iOS 26.0, *)
extension OnDeviceModel {

    static func run(metadata: LinkMetadata, memo: String, existingTags: [TagDef]) async -> ItemCandidate? {
        let model = SystemLanguageModel(useCase: .contentTagging)
        guard model.availability == .available else { return nil }

        let tagLabels = existingTags.map(\.ja)
        let session = LanguageModelSession(model: model, instructions: instructions(tagLabels: tagLabels))
        let prompt = prompt(metadata: metadata, memo: memo)
        let options = GenerationOptions(temperature: 0.3)

        do {
            let response = try await session.respond(to: prompt, generating: GeneratedCandidate.self, options: options)
            let g = response.content
            let title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let tags = TagValidator.validate(g.tags, against: existingTags)
            var seasons = Classifier.seasons([title, metadata.title ?? "", memo].joined(separator: " "))
            if seasons.isEmpty { seasons = [.any] }
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

    private static func instructions(tagLabels: [String]) -> String {
        """
        あなたは「やりたいことリスト」のタイトル生成器です。出力は必ず短い『行動表現』のタイトル1つ。
        与えられたメタデータから「対象の具体的な名称」（店名・施設名・イベント名・場所名などの固有名詞）を抽出し、
        場所・飲食店・イベント・レジャーに関するものは必ず「{名称}に行く」にします。
        重要：ページタイトルや投稿本文を“そのままコピーしない”。名称だけ抜き出して行動表現に変換する。

        例:
        - 入力「場所/店名: ABC Cafe」→「ABC Cafeに行く」
        - 入力「投稿本文: 渋谷の隠れ家イタリアン Trattoria Rossi に行ってきた。最高」→ 名称=Trattoria Rossi →「Trattoria Rossiに行く」
        - 入力「ページタイトル: 高尾山 紅葉ライトアップ2026」→ 名称=高尾山 →「高尾山に行く」
        - 入力「サイト名: ABC Cafe / タイトル: ホーム」→「ABC Cafeに行く」
        - 映画/動画は「{作品名}を見る」、商品は「{商品名}を試す」、レシピは「{料理名}を作る」、記事/学習は「{テーマ}について調べる」。
        - 名称が特定できないときは『ホーム』『Google Maps』等の汎用語を使わず、その旨を reason に書き needsUserConfirmation=true。

        タグは次の既存タグの中からのみ0〜3個選びます。一覧にないタグは絶対に作りません: \(tagLabels.joined(separator: " / "))。
        ユーザーメモがある場合は店名・場所名の手がかりとして強く参考にします。
        """
    }

    private static func prompt(metadata: LinkMetadata, memo: String) -> String {
        var lines = ["URL種別: \(metadata.sourceType.rawValue)", "URL: \(metadata.bestURL.absoluteString)"]
        if let p = metadata.placeName, !p.isEmpty { lines.append("地図から抽出した場所/店名: \(p)") }
        if let s = metadata.siteName, !s.isEmpty { lines.append("サイト名: \(s)") }
        if let t = metadata.title, !t.isEmpty { lines.append("ページタイトル: \(t)") }
        if let d = metadata.description, !d.isEmpty { lines.append("説明/投稿本文: \(d)") }
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("ユーザーメモ: \(trimmedMemo.isEmpty ? "（なし）" : trimmedMemo)")
        return lines.joined(separator: "\n")
    }
}

#endif
