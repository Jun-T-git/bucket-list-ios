# ビルドと検証 — Wishes

自律開発で「壊していないこと」を機械的に確かめる手順。**変更後は必ずここを通す。**
この検証は `.claude/` の **hooks が自動で強制**する（下記§hooks）ので、AI は思い出さなくても外せない。

## 前提

- Xcode 26 / iOS 17.0 デプロイメントターゲット / Swift 5.0 / SPM 依存なし。
- プロジェクト＝スキーム＝フォルダは `BucketList`、製品名は `Wishes`（[用語](../README.md#用語命名の整理)）。
- 生成物は `.gitignore` 済みの `build/` か `/tmp` に出す（**repo を汚さない** ため `-derivedDataPath /tmp/...` 推奨）。

## 1. 高速型チェック（数秒・シミュレータ不要）

編集直後の最速フィードバック。README「Verifying」と同じ：

```sh
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos swiftc -typecheck -sdk "$SDK" \
    -target arm64-apple-ios17.0 $(find BucketList -name '*.swift')
```

> ⚠️ `BucketList/*.swift` だけだと `Capture/` 配下（`URLSafety` 等）を拾えず型解決に失敗する。
> **必ず `$(find BucketList -name '*.swift')`** でモジュール全体を渡すこと。

## 2. シミュレータビルド（本命の確認）

```sh
xcodebuild -project BucketList.xcodeproj -scheme BucketList \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -configuration Debug -derivedDataPath /tmp/BucketList-build build
```

- 利用可能なシミュレータは iPhone 17 系（`xcrun simctl list devices available` で確認）。
- 署名不要（シミュレータ）。実機ビルド確認だけなら
  `-destination 'generic/platform=iOS' ... CODE_SIGNING_ALLOWED=NO`。

## 3. ユニットテスト（純ロジック）

```sh
xcodebuild -project BucketList.xcodeproj -scheme BucketListTests \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -derivedDataPath /tmp/test-build test
```

- 対象は UI 非依存の純ロジック（`Classifier` / `TimingSuggestion` / `SeasonTag` / filter・sort /
  寛容 `Codable` / `TagValidator`）。詳細は [data-model](../architecture/data-model.md#テスト対象として価値が高いロジック)。
- 追加は新規テストファイル ＋ `BucketListTests` ターゲットへ。既存アプリロジックの挙動は変えない。
- スキル `/verify-build` が 1.→2.→3. をまとめて実行する。

## 4. 視覚確認（UI 変更時）

UI・哲学は視覚依存（[設計原則§1–3](../philosophy/02-設計原則.md)）。DEBUG の `Screenshots` モードで
安定したデモ状態を撮り、原則に照らして自己点検する。スキル `/visual-check` が下記を自動化：

- DEBUG `Screenshots`（`Models.swift`）＋ `Seed.screenshotItems` ＋ `Clock.override` で日付固定。
- `xcrun simctl status_bar ... override --time 9:41`、`xcrun simctl io <udid> screenshot <path>`。
- 詳しい撮影/合成手順は `screenshots/README.md`。

## 5. 哲学レビュー（差分を原則に照らす）

`design-guardian` エージェント（`.claude/agents/`）で、現在の差分が
[設計原則](../philosophy/02-設計原則.md)に反していないかをレビュー。`/code-review`（バグ観点）とは別軸。

## テストは無い前提から始まっている

このプロジェクトは元々テスト0件。`BucketListTests` は本整備で新設したもの。
新しいロジックを足したら、対応する純ロジックのテストも足すのが既定。

## hooks による自動強制（.claude/settings.json）

- **Stop フック**：会話を終える前に `.claude/hooks/verify-on-stop.sh` が走る。
  Swift 変更があれば §1 の型チェックを実行し、失敗なら完了をブロックして原因を返す。
  Swift 変更が無ければ即 no-op（ドキュメント編集だけの会話は邪魔しない）。
- **PostToolUse フック**：`*.swift` の Edit/Write 直後に同じ型チェックで即時フィードバック。
- **PreToolUse フック**：`docs/philosophy/**`・`docs/decisions/**` の編集時に確認を促す（正典ガード）。
- ノイズが多いと感じたら `.claude/settings.json` の該当フックを外して Stop ゲートだけに縮退できる。
