# データモデル：3軸モデル — Wishes

すべて `BucketList/Models.swift`。3軸 = **優先度（priority）× 季節（season）× タグ（tag）** で、
1アイテムをゆるく分類する。時間階層（今月/今年/いつか）は廃止済み
（[ADR 0001](../decisions/0001-3軸モデル.md)）。「タグ地獄にしない・シンプル優先」が指針
（[コアコンセプト§5](../philosophy/01-コアコンセプト.md)）。

## 中心の型：`BucketItem`

`struct BucketItem`（`Codable` は手書きで寛容 = [設計原則§9](../philosophy/02-設計原則.md)）。主なフィールド：

| フィールド | 型 | 意味 |
|-----------|----|------|
| `id` | `Int` | 単調増加の識別子。次IDは現ドキュメントの max+1 |
| `title` | `String` | 体言止めの主題（[設計原則§7](../philosophy/02-設計原則.md)）。生成時は30字上限 |
| `priority` | `Priority` | 軸①。1アイテム1つ |
| `seasons` | `[SeasonTag]` | 軸②。複数選択可。**空 = いつでも** |
| `tags` | `[String]` | 軸③。タグ**キー**の配列（複数選択可） |
| `meta` | `String?` | 補足メモ |
| `done` / `doneAt` | `Bool` / `Date?` | 消化フラグと達成日時。`doneAt` がレポート集計を駆動 |
| `via` | `String?` | 由来（"共有" / "URL" / "X" 等）。プロベナンス |
| `url` | `String?` | 元リンク |
| `savedAt` | `String` | "yyyy·MM·dd"（中黒区切り） |

## 軸①：`Priority`

`enum Priority { case top, maybe, someday }` → 日本語 高/中/低。
- 各ケースは green の濃淡へ写像（`green700/500/300`）＝**色は1系統**（[設計原則§2](../philosophy/02-設計原則.md)）。
- `weight`（3/2/1）で並び替えに寄与。`static let order` が正準順。

## 軸②：季節 — `Season` と `SeasonTag`

- `enum Season { spring, summer, fall, winter }`。`.months` / `.of(month:)` / `.upcoming(from:)`
  （現在地からの時間順。レポート・並び替えで使用）。
- **アイテムに実際に載るのは `SeasonTag`**：`.season(Season)` または `.any`（「いつでも」ワイルドカード）。
  - `storageKey` が永続化文字列。`from(key:)` は**旧・月キー（"m4" 等）を季節へ畳み込む**（後方互換）。
  - **`seasons` が空 = いつでも扱い** → 正規化は `BucketItem.normalizedSeasons`。
  - 月単位指定は廃止（春夏秋冬のみ）。[ADR 0001](../decisions/0001-3軸モデル.md)。

## 軸③：タグ — `TagDef` と `Tags`

- `struct TagDef { key, ja, builtin, desc? }`。
  - `desc` は**自然言語の説明文（例つき）**で、オンデバイスモデルに**意味ベースの分類根拠**として渡す
    唯一のタグ指針（[capture-pipeline](capture-pipeline.md)）。
- `enum Tags` … 固定4個（食/旅/遊び/買い物、各リッチな `desc` つき）＋カスタム最大10個（`maxCustom = 10`）。
  - カスタムタグのキーは `c-<UUID>`。**編集可能なのはカスタムのみ**、固定4個の説明文は不変。
  - タグ削除時は全アイテム・アクティブフィルタからも除去（`SettingsView` のタグ管理）。

## 付随する設定・ビュー状態の型

| 型 | 役割 |
|----|------|
| `Tweaks` | 設定ブロブ（通知トグル、`autoClassify`、`analyticsEnabled`＝利用状況送信の opt-out、`yearGoal`＋年別 `yearGoals`、`userName`） |
| `Filters` | 4集合：priority / seasons / tags / statuses。軸間 AND・軸内 OR |
| `ViewPrefs` / `SortMode` | 表示設定 / 並び替え（6モード） |
| `ItemStatus` / `YearScope` | 状態フィルタ / 年スコープ（`.all` / `.year(Int)`） |
| `Clock` | ライブな「今日」。`Clock.override` でスクショ/プレビュー用に日付固定。`isWeekendish` 等の時間フレーム判定 |

## Models.swift 内のロジック（モデル以外）

- フィルタ/ソート拡張：`nowScore`・`seasonRank`・軸横断カウント `filterCounts`。
- `Classifier` … タイトル入力中に優先度/季節/タグを即時下書きする**正規表現ベースのオフライン分類器**
  （コンパイル済み正規表現キャッシュあり）。設定の自動分類 OFF を尊重。
- `NotificationPlanner` … 特定アイテムを名指しするローカル通知。純関数 `plan(tweaks:items:now:)` が
  **日付つき単発（`repeats: false`）の `Nudge` 列**を作り、`sync()` が `UNCalendarNotificationTrigger` に変換する
  （週末＝金曜17時×24週先／月末＝25日19時×12か月先／季節＝各季節初日9時の次回1件。計40件＜iOS上限64）。
  **配信ごとに名指しする項目が変わる**（`NotificationPlanner.Rotation`）：
  - 順番は発火日から決まる（週/月/年インデックス）。再計画しても各日付の項目は不変。
  - 候補（その季節に合う未達成項目。無ければ全未達成）を、重み＝優先度 高3:中2:低1＋季節一致 +2
    （`TimingEngine.nowScore` と同じ加点）の滑らかな重み付きラウンドロビンで巡回。同一項目は連続しない。
  - **同じ重みの項目どうしはランダム順**。デッキ1周ごとにシャッフルし直す（固定の並びにならない）。
    乱数は周回番号をシードにした決定的なもの（ライブ乱数ではない）ので、上の「日付ごとに不変」「連続なし」が再計画をまたいで保たれる。
  - 候補が1件だけなら汎用文言と交互。季節適合は**発火日の季節**で判定。
  `sync()` は起動／復帰／バックグラウンド移行／設定変更で窓を引き直す。
  アプリを一度も開かないまま窓が尽きたら通知は止まる（意図的：無視され続けた通知を無期限に送り続けない）。
- `SeasonPlan.pending(items:from:)`（`ReportView.swift`）… レポート「これからの季節」の振り分け（純関数）。
  季節タグ付きは該当する全季節に載せ、**「いつでも」は今の季節に寄せず4季節のどれか1つへ**：件数が均されるよう
  少ない季節から枠を配り、優先度の高いものほど近い季節に置く。
- `TimingSuggestion` / `TimingEngine.suggestion(items:)` … タイミング提案（[コアコンセプト§5③](../philosophy/01-コアコンセプト.md)）。
  今日の位置（年末＞週末[金-日]＞月初＞季節終わり＞季節中）からフレームを選び、開いている項目を
  季節適合＋優先度で並べた**全ランク一覧**を返す（表示側が prefix：本体バナー3件／ウィジェット Small・accessory 1件、Medium 3件）。
  **同スコアの項目は `Clock.dayOrdinal` で日替わりローテーション**（決定的＝同じ日は同じ順。強い1件は固定、同点だけが順番に）。
  `[BucketItem]` を受ける純関数 `TimingEngine`（季節適合スコアは `TimingEngine.nowScore`）に抽出済みで、
  `AppStore.timingSuggestion()`（本体ホームバナー）と `WidgetExtension`（ホームウィジェット）が同一ロジックを共有。
- `Seed` … デモ/スクショ専用データ。**実ユーザーには出さない**（新規インストール = 空リスト）。

## テスト対象として価値が高いロジック

純粋関数的で UI に依存しないため、[テスト](../workflows/build-and-verify.md)の主対象：
`Classifier` / `TimingEngine`（`Clock.override` で分岐）/ `NotificationPlanner.plan` / `SeasonPlan.pending` /
`SeasonTag.from(key:)`＋`normalizedSeasons` /
filter・sort（`nowScore`/`seasonRank`/`filterCounts`）/ 寛容 `Codable`（`LossyArray`/`StoreLoad`）/
`TagValidator`（[capture-pipeline](capture-pipeline.md)）。
