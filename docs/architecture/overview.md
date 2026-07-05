# アーキテクチャ概観 — Wishes

対象：iOS 17.0+ / SwiftUI / Swift 5.0 / Xcode 26。外部依存パッケージなし（SPM 未使用）。
2ターゲット構成：本体アプリ（`BucketList`）＋共有拡張（`ShareExtension`）。全 UI 日本語。約10k行。

> 前提知識：[コアコンセプト](../philosophy/01-コアコンセプト.md)（何のためか）、
> [設計原則](../philosophy/02-設計原則.md)（守るべき核）。データモデルの詳細は
> [data-model.md](data-model.md)、URL取り込みは [capture-pipeline.md](capture-pipeline.md)。

## 全体像：単一の観測可能ストア（per-screen MVVM ではない）

真実の源はただ一つ、`AppStore: ObservableObject`（`BucketList/Models.swift`）。
items / customTags / filters / sort / tweaks と、シート・トースト・選択などの一時状態まで、
すべてここに集約する。ルートで一度だけ生成し、各画面は `@EnvironmentObject` で読む。

- エントリ：`BucketListApp.swift` が `AppStore()` と `ProStore()` を `@StateObject` で生成し `ContentView` に注入。
- 起動/復帰：`scenePhase == .active` で `store.reload()` ＋通知再同期。
  → **共有拡張がバックグラウンドで書いた項目が、再起動なしで前面復帰時に反映される**核心。
- 画面：各 View は素の SwiftUI struct。一時 UI 状態はローカル `@State`、共有データはストア経由。
  `ContentView` がタブ切替（`store.selectedTab`）・FAB・下部バー・全 `.sheet` を保持。
  `TabView` は使わず `switch store.selectedTab` ＋ `CustomTabBar`。
- 由来：もとは React プロトタイプの移植（`Models.swift` のコメントに `App()` / `shared.jsx` 対応の記述）。

## 永続化：3層、すべて JSON（SwiftData / Core Data は不使用）

1. **正典＝ App Group コンテナ内の単一 JSON ファイル**（`NSFileCoordinator` 経由）。
   `SharedStore`（`Models.swift`）が `store.json`（＋ `store.bak.json` 1世代バックアップ）を読み書き。
   `StoreDocument` が items＋customTags をひとまとまりで原子的に保存。
   - 本体アプリはドキュメント全体を置換保存（`SharedStore.save`）。
   - 拡張は協調的な read-modify-write で追記（`SharedStore.mutate`、`.forMerging`）→ **互いの書き込みを潰さない**。
2. **UserDefaults（App Group suite）** … 小さめの副次データ：tweaks / view prefs / オンボーディング済フラグ /
   Pro エンタイトルメントのミラー / 旧 item blob（`Storage`。`suiteName: appGroupID`）。
3. **旧データ（App Group 導入前）** … 初回起動で前方移行：`Storage.migrateFromStandardIfNeeded()` →
   `SharedStore.migrateLegacyIfNeeded()`。いずれも `AppStore.init()` の最初の読み込み前に実行。

### データを壊さない設計（[設計原則§9](../philosophy/02-設計原則.md) の実体）
- `StoreLoad` は `.absent` / `.loaded` / `.unreadable` の3値 → 読めない時に**空で上書きしない**
  （UI は `storageUnreadable` でアラート表示）。
- `LossyArray` / `LossyDocument` は要素ごとにデコード → 1件破損はその1件だけ失う。
- `BucketItem` は手書きの寛容な `Codable` → 新フィールドは既定値フォールバック。

## アプリ ↔ 拡張の共有

両ターゲットとも `com.apple.security.application-groups = group.teratech.BucketList` を
`.entitlements` に宣言（`BucketList/BucketList.entitlements`・`ShareExtension/ShareExtension.entitlements`）。
拡張は **`AppStore` を持たず StoreKit も動かせない** → `SharedStore` / `Storage` を直接読み書きする。
`ShareComposeView.save()` は `SharedStore.mutate` 内で最新ドキュメントから次IDを計算し `via: "共有"` で挿入。
App Group ID はコード内 `static let appGroupID = "group.teratech.BucketList"`（`Models.swift`）。

## 状態変更の作法

- 一時 UI 状態 = ローカル `@State`。共有データ = `@EnvironmentObject var store` / `pro`。
- ストアの変更メソッドはローカルコピーを編集して一度だけ代入 → `items` 等の `didSet` が**1回だけ永続化**。
- undo は変更メソッドに内蔵（`pendingUndo` バッファ＋アクション付きトースト。`remove` / `removeMany`）。

## 画面と主なファイル

| ファイル | 役割 |
|---------|------|
| `BucketListApp.swift` | @main。起動時に `pro.start()`／通知同期、復帰時に `reload()` |
| `ContentView.swift` | ルート。タブ切替・FAB・`CustomTabBar`・全シート・一括編集シート |
| `HomeView.swift` | リストタブ（`InlineSuggestionBanner`＝タイミング提案、`CountStrip`、スワイプ行、空状態） |
| `AddEditSheet.swift` | 追加/編集（共有 `ItemForm`。URL入力でプレビュー→「反映」で採用） |
| `DetailSheet.swift` | 詳細（過去の自分メモ） |
| `FilterSheet.swift` | `ViewOptionsSheet`＝並び替え＋3軸フィルタ統合（軸横断のチップ別カウント） |
| `ReportView.swift` | レポート（実績チャート・ペース・季節プラン） |
| `SettingsView.swift` | 設定（通知/AI/タグ管理/データ、法務画面） |
| `Models.swift` | モデル＋`AppStore`＋業務ロジック（分類/通知/提案/永続化）。約1800行の中心 |
| `Theme.swift` | デザイントークン（色/フォント/影/`glass`/`Haptics`） |
| `Components.swift` | アプリ内再利用ビュー（チップ/ピル/トースト/選択○ 等） |
| `ItemForm.swift` | **アプリと拡張が共有する**追加フォーム（＋`FlowLayout`/`SectionLabel`） |
| `Capture/` | URL→候補パイプライン（[詳細](capture-pipeline.md)） |
| `ProStore.swift` / `PaywallView.swift` | StoreKit2 の Pro（v1.0 は無効。[ADR 0005](../decisions/0005-v1無料とPro無効フラグ.md)） |

## 新しい画面/機能を足すときの定石

1. `NewView.swift` を作り `struct NewView: View`（`@EnvironmentObject var store`）。
2. タブなら：`AppStore.Tab` にケース追加 → `ContentView` の `switch` → `CustomTabBar` の `tabButton`。
3. モーダルなら：`ContentView` にローカル `@State` ＋ `.sheet`、ヘッダは `ScreenHeader`/`SheetHeader`。
4. UI は **Theme トークン ＋ Components プリミティブ ＋ `FlowLayout`/チップ語彙** で組む（[設計原則](../philosophy/02-設計原則.md)）。
5. 追加フォームが要るなら **`ItemForm` を再利用**（新規フォームを作らない。[設計原則§5](../philosophy/02-設計原則.md)）。
