# CLAUDE.md — Wishes 自律開発ガイド

iOS SwiftUI アプリ。**このファイルは毎セッション読み込まれるアンカー**。詳細は各ドキュメントへ辿る。
ドキュメント全体像 → [`docs/README.md`](docs/README.md)。

## このアプリは何か（1文）

> バケットリストを**管理する**アプリではない。バケットリストを**"ちゃんと消化させる"**アプリ。

保存だけで埋もれた「いつか」を、適切なタイミングでそっと差し出し、"やった"に変える。
ターゲットは 20代。KPI は DL 数ではなく **"やった"に変わった数**。
全体像 → [`docs/philosophy/01-コアコンセプト.md`](docs/philosophy/01-コアコンセプト.md)。

## 用語（重要）

- **Wishes** = 製品名／App Store 表示名（`PRODUCT_NAME = Wishes`）。ユーザー向け文言に使う。
- **BucketList** = Xcode プロジェクト/スキーム/フォルダ名・バンドルID接頭辞（`teratech.BucketList`）。コード/ビルドで使う。
- **バケットリスト** = 一般ジャンル名・思想議論での呼称。
- 同一物の別レイヤの呼称（[docs/README.md](docs/README.md#用語命名の整理)）。

---

## 非交渉の設計原則（＝迷ったら常にこれが優先）

以下は正典 [`docs/philosophy/02-設計原則.md`](docs/philosophy/02-設計原則.md) を丸ごと読み込む。**必ず順守する。**

@docs/philosophy/02-設計原則.md

---

## アーキ地図（どこに何があるか）

真実の源は単一の `AppStore: ObservableObject`（`BucketList/Models.swift`、約1800行）。per-screen MVVM ではない。
永続化は3層すべて JSON（SwiftData/Core Data 不使用）：App Group の `store.json`（`SharedStore`）＋ UserDefaults ＋ 旧データ移行。
アプリ↔共有拡張↔ホームウィジェットは App Group `group.teratech.BucketList` で共有（ウィジェットは `SharedStore.snapshot()` を読み取り専用）。詳細 → [`docs/architecture/overview.md`](docs/architecture/overview.md)。

- **データモデル（3軸：優先度×季節×タグ）** → [`docs/architecture/data-model.md`](docs/architecture/data-model.md)
- **URL→候補パイプライン（オンデバイス AI）** → [`docs/architecture/capture-pipeline.md`](docs/architecture/capture-pipeline.md)
- **追加フォームは `ItemForm.swift` を共有**（アプリ／拡張とも。新フォームを作らない）。
- **UI プリミティブ** = `Theme.swift`（色/フォント/`glass`/`Haptics`）＋ `Components.swift`。
- **主要画面**：`ContentView`(ルート/タブ) `HomeView`(リスト) `AddEditSheet` `ReportView` `SettingsView` `FilterSheet`。
- **Pro（v1.0 は無効）**：`ProStore.swift` / `PaywallView.swift`（[ADR 0005](docs/decisions/0005-v1無料とPro無効フラグ.md)）。
- **ホームウィジェット**：`WidgetExtension/`（タイミング提案を Small/Medium で表示）。提案の選定は純関数 `TimingEngine`（`Models.swift`）を本体と共有。

## 変更時の必須フロー

1. **原則に照らす**：関係する [設計原則](docs/philosophy/02-設計原則.md) を確認（`.claude/rules/*` がパスに応じ自動提示）。
2. **実装**：既存の型・Components・`ItemForm`・チップ語彙を再利用。周囲のコードの語彙・粒度に合わせる。
3. **検証**：[`docs/workflows/build-and-verify.md`](docs/workflows/build-and-verify.md) の型チェック→ビルド→テスト。
   スキル `/verify-build` で一括。**Stop フックが完了前に自動でこれを強制する**（壊れたコードで終われない）。
   UI 変更なら `/visual-check` で撮って原則に照らす。
4. **哲学レビュー**：`design-guardian` エージェントで差分を原則に照らす（`/code-review` はバグ観点＝別軸）。
5. **ドキュメント同期**：構造・データモデル・取り込み・手順を変えたら、対応する**常設ドキュメント**を追随させる
   （`/sync-docs` か `doc-scribe`。Stop フックが乖離を検知してリマインドする）。常設と一時の区別 →
   [`docs/README.md`](docs/README.md#常設と一時ドキュメント)。**一時メモ・計画・作業ログは repo に置かず scratchpad へ。**

## ビルド/検証コマンド（詳細は build-and-verify.md）

```sh
# 型チェック（数秒・シミュレータ不要）
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios17.0 $(find BucketList -name '*.swift')

# シミュレータビルド（repo を汚さないよう /tmp へ）
xcodebuild -project BucketList.xcodeproj -scheme BucketList \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/BucketList-build build

# ユニットテスト
xcodebuild -project BucketList.xcodeproj -scheme BucketListTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/test-build test
```

## やってはいけないこと

- 期限管理/優先度管理を主役にする、仕事タスクと混ぜる、複雑なタグ構造、SNS化（[コアコンセプト§6](docs/philosophy/01-コアコンセプト.md)）。
- **近似マテリアルで Liquid Glass を代用**する（iOS 26 では純正 `.glassEffect`）。
- 達成時に confetti/キラキラを足す。多色で塗り分ける。カスタム書体を無断で復活させる。
- AI が意図（動詞）を捏造する／ユーザーが編集した値を上書きする。分類のためにテキストを外部送信する。
- デコード失敗でストアを空に上書きする（[設計原則§9](docs/philosophy/02-設計原則.md)）。
- **設計原則そのものを勝手に変える**：必要なら [ADR](docs/decisions/) 起票を提案し依頼者の判断を仰ぐ。
- **一時ドキュメント（調査メモ/計画/作業ログ）を repo に残す**：scratchpad に置く。常設 doc を更新せずコードだけ変えて放置する。

## 会話・コード規約

- 会話は日本語。コードコメントは英語可。ドキュメントは日本語主体・型名/コマンドは英語。
- 既存アプリロジック（`BucketList/**` の `.swift`）を触るときは挙動を保存し、周囲の命名・`// MARK:` 粒度に合わせる。
- コミット/プッシュはユーザーの明示指示があるまで行わない。
