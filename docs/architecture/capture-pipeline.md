# 取り込みパイプライン：URL → やりたいこと候補 — Wishes

`BucketList/Capture/` の5ファイル。共有された/貼られた URL を、編集可能な「やりたいこと候補」
（`ItemCandidate`）に変える。**すべて端末内で完結、外部にテキストを送らない**
（[設計原則§8](../philosophy/02-設計原則.md)）。エントリは `CandidateGenerator.make(...)`。

## パイプライン

```
URL
 └─ 1. 正規化 + 安全性  URLSafety.normalized / isSafe   （URLMetadata.swift）
 └─ 2. モデル暖機        OnDeviceModel.prewarm()          （fetch と並行させ待ち時間を隠す）
 └─ 3. メタデータ取得    MetadataFetcher.fetch → LinkMetadata（URLMetadata.swift）
 └─ 4. 一次：オンデバイスLLM  OnDeviceModel.generate       （OnDeviceModel.swift）
        └─ 失敗/非対応なら
 └─ 5. フォールバック：ルールベース  RuleBasedCandidate.make（RuleBasedCandidate.swift）
 └─ 6. 組み立て          ItemCandidate（＋ TagValidator）  （ItemCandidate.swift）
```

### 1. 正規化 + 安全性（`URLMetadata.swift`）
`URLSafety.normalized` / `isSafe`：ベストエフォートの SSRF ガード（http(s) のみ、localhost/`.local`/
プライベートIP帯を弾く）。不正なら `ItemCandidate.fallback`。

### 2. モデル暖機
`OnDeviceModel.prewarm()` を fetch と並行で走らせ、推論コストを取得待ちに重ねる。

### 3. メタデータ取得（`URLMetadata.swift`）
`MetadataFetcher.fetch`：
- `SourceType.detect` … googleMaps / instagram / tiktok / x / youtube / web を判別。
- 短縮URLは redirect 上限付き `RedirectGuard` で展開。
- タイトルは `LinkPresentation`（`LPMetadataProvider`）。欠けた分だけ**サイズ上限（256KB）の HTML/OGP head**
  を読んで補う。
- Google Maps は `GoogleMapsURL.placeName` で URL から地名を抽出。
- 返すのは `LinkMetadata`。**ページ本文は決してモデルに渡さない**（この事実だけを渡す）。

### 4. 一次：オンデバイス LLM（`OnDeviceModel.swift`）
- ゲート：`#if canImport(FoundationModels)` ＋ `iOS 26.0` ＋
  `SystemLanguageModel(useCase: .contentTagging).availability == .available`。
- 8秒タイムアウト（`withTaskGroup` レース）。
- `@Generable struct GeneratedCandidate` に `@Guide` で構造化出力を拘束：
  タイトルは**名詞句・体言止め**（[設計原則§7](../philosophy/02-設計原則.md)）、タグは**既存ラベルからのみ**、
  季節、confidence、needsUserConfirmation。`temperature: 0.2`。
- システムプロンプト（`instructionsBody`）は、各タグの `ja: desc`（[data-model](data-model.md) の `TagDef.desc`）を
  タグ指針の唯一の源として注入。
- 失敗時は `nil` を返して 5. へ。すべて端末内。

### 5. フォールバック：ルールベース（`RuleBasedCandidate.swift`）
`RuleBasedCandidate.make`：決定論的なキーワード/ドメイン分類器。
- 結合した「シグナル」文字列からカテゴリ（youtube/recipe/shopping/learn/outing）を検出。
- 固有名を `bestName`→`primaryName` で抽出（「店舗概要/アクセス」等の見出しラベルを剥がし、
  組織名/ヘッドラインを避け、「X on Instagram」の投稿者名採用を回避 = [設計原則§7](../philosophy/02-設計原則.md)）。
- 厳選ドメインリスト（`outingDomains`・買い物系）。confidence とタグを算出。
- **常に使える結果を返す**（LLM が無くても取り込みが成立する）。

### 6. 組み立て（`ItemCandidate.swift`）
両経路とも `ItemCandidate` を生成：`title, tags, seasons, priority, confidence,
needsUserConfirmation, readable, sourceURL, canonical`。
- `shouldConfirm` = needsConfirm または confidence < 0.5。
- `TagValidator.validate` … 実在タグキーのみ・重複除去・**最大3件**に丸める。
- タイトルは `CandidateGenerator` で **30字ハードキャップ**。

## どこで消費されるか

共有フォーム `ItemForm`（[設計原則§5](../philosophy/02-設計原則.md)）の URL フィールドを起点に、
ほぼ同一の2つの状態機械が駆動：

- **アプリ内**（`AddEditSheet.onUrlSettled`）：結果を**プレビューカード**で見せ、ユーザーが「反映」で採用
  （`applyPreview`）。
- **共有拡張**（`ShareComposeView`）：確信度が高い読み取りを**未編集フィールドにだけ自動採用**（`applyAI`）。

いずれも 600ms デバウンス、URL がまだ現在のものである時のみ結果を受理、成功時に無料取り込みを1回消費
（`Storage.consumeFreeCapture()`。v1.0 は無効 = [ADR 0005](../decisions/0005-v1無料とPro無効フラグ.md)）。

## 変更時の必須チェック（[設計原則](../philosophy/02-設計原則.md)）
- タイトルは体言止め・意図（動詞）を足さない。LLM とルールベースで**表現を統一**。
- 入力に使うのは端末内メタデータのみ。ページ本文・ユーザーテキストを外部送信しない。
- LLM が使えない端末（多くのシミュレータ含む）でも、ルールベースで必ず候補が出ること。
