---
description: Wishes(iOS) の変更を検証する。型チェック→シミュレータビルド→ユニットテストを順に実行し、失敗を要約する。コード変更後・完了前に使う。
allowed-tools: Bash(xcrun --sdk iphoneos swiftc *), Bash(xcrun --sdk iphoneos --show-sdk-path), Bash(xcodebuild *), Bash(find BucketList *), Read
---

# /verify-build — 変更の検証

[docs/workflows/build-and-verify.md](../../../docs/workflows/build-and-verify.md) の 1→2→3 を実行する。
各段階で失敗したら、そこで止めてエラーの要点（ファイル:行 と error メッセージ）を報告し、原因を特定する。

## 手順

### 1. 型チェック（数秒）
```sh
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios17.0 $(find BucketList -name '*.swift')
```
※ `BucketList/*.swift` だけだと `Capture/` を拾えず失敗する。必ず `$(find ...)` を使う。

### 2. シミュレータビルド
```sh
xcodebuild -project BucketList.xcodeproj -scheme BucketList \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug -derivedDataPath /tmp/BucketList-build build
```
利用可能なシミュレータ名は `xcrun simctl list devices available` で確認（iPhone 17 系）。

### 3. ユニットテスト（`BucketListTests` が存在する場合）
```sh
xcodebuild -project BucketList.xcodeproj -scheme BucketListTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/test-build test
```
`BucketListTests` スキームが無ければこの段はスキップし、その旨を報告する。

## 報告の形

- すべて緑：「型チェック✓ / ビルド✓ / テスト N件✓」を簡潔に。
- 失敗：失敗した段階・`ファイル:行`・error 行（`grep -E 'error:'` の要点）を示し、次の一手を提案する。
- 出力は `/tmp` に置き、repo（`build/` は .gitignore 済み）を汚さない。
