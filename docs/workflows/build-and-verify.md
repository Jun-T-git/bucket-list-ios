# ビルドと検証 — Wishes

自律開発で「壊していないこと」を機械的に確かめる手順。**変更後は必ずここを通す。**
この検証は `.claude/` の **hooks が自動で強制**する（下記§hooks）ので、AI は思い出さなくても外せない。

## 前提

- Xcode 26 / iOS 17.0 デプロイメントターゲット / Swift 5.0。SPM 依存は `firebase-ios-sdk`（本体のみ）。
  **初回のシミュレータビルド／アーカイブはパッケージ取得で数分＋ネットワークが要る**（`Package.resolved` は
  `BucketList.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` に生成され、git 管理する）。
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
>
> Firebase を import するのは `Analytics.swift` の `#if ANALYTICS_FIREBASE` ブロックだけ（このフラグは
> Xcode の本体ターゲットでのみ定義）。この型チェックでは SDK なしの経路がコンパイルされるので、
> 従来どおりシミュレータ不要・数秒で通る。`Analytics.swift` の SDK 側の経路は §2 のビルドで検証される。

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

- 対象は UI 非依存の純ロジック（`Classifier` / `TimingEngine` / `NotificationPlanner.plan` / `SeasonPlan` / `SeasonTag` / filter・sort /
  寛容 `Codable` / `TagValidator` / `Engagement`＋計測語彙）。詳細は [data-model](../architecture/data-model.md#テスト対象として価値が高いロジック)。
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

## CI（GitHub Actions）と配信

- **CI**：`.github/workflows/ci.yml` が push（main）/ PR ごとに §1→2→3 を macOS ランナーで実行する。
  署名不要（シミュレータのみ）なのでシークレット設定は不要。
- **TestFlight 配信**：`scripts/release-testflight.sh`（スキル `/deploy-testflight`）。
  手順の全体は [release-runbook.md](release-runbook.md#6-ビルドをアップロード)。
- **App Store 審査提出（本番）**：`scripts/submit-appstore.py`（スキル `/submit-appstore`）。
  [release-runbook.md §7](release-runbook.md#7-審査へ提出)。

## clang環境検査がpipe待ちで停止する場合だけの回避

2026-11-10、Xcode 26.6（17F113、iOS Simulator SDK 26.5）の `clang -v -E -dM` 検査が `write()` 待ちとなり、
アプリのコンパイル前に停止した。直接実行でstdout/stderrを並行回収すると成功し、通常実行と
`-quiet` の再試行で同じ停止を確認した。逐次回収のdeadlockを修正した
[SwiftBuild #1315](https://github.com/swiftlang/swift-build/pull/1315)と整合する現象であり、
アプリコードのコンパイル失敗とは区別する。全体再起動や無関係なプロセスの終了は行わない。

同じ条件を確認した時だけ、次の `/tmp` 補助を作り、その実行に `CC` / `CXX` を明示する。
検査の両出力を並行回収し、stdoutの書出し後にcloseしてからstderrを書き出す。出力の省略・
改変はせず、終了値とsignalを保持する。通常コンパイルは元のclangへ同じ引数で `execv` する。

```sh
mkdir -p /tmp/wishes-clang-probe
cat > /tmp/wishes-clang-probe/clang <<'PY'
#!/usr/bin/python3
import os, signal, subprocess, sys
real = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/' + os.path.basename(sys.argv[0])
if all(arg in sys.argv for arg in ['-v', '-E', '-dM']):
    result = subprocess.run([real, *sys.argv[1:]], capture_output=True)
    for fd, data in [(1, result.stdout), (2, result.stderr)]:
        while data:
            count = os.write(fd, data)
            data = data[count:]
        os.close(fd)
    if result.returncode < 0:
        if -result.returncode not in (signal.SIGKILL, signal.SIGSTOP):
            signal.signal(-result.returncode, signal.SIG_DFL)
        os.kill(os.getpid(), -result.returncode)
    sys.exit(result.returncode)
os.execv(real, [real, *sys.argv[1:]])
PY
chmod +x /tmp/wishes-clang-probe/clang
cp /tmp/wishes-clang-probe/clang /tmp/wishes-clang-probe/clang++
# §2/§3のxcodebuildの末尾へ追加（build/testの指定は維持）
# CC=/tmp/wishes-clang-probe/clang CXX=/tmp/wishes-clang-probe/clang++
```

使用前に同じSDK/言語/引数で直接clangと補助を `subprocess.run(..., capture_output=True)` し、
stdout/stderrのバイト列と終了値が完全一致することを検証する。補助のSHA-256、比較結果、
実際のコマンド、ビルド/テスト結果を当該作業の証拠に残す。検査の停止回避だけで品質完了にしない。
これは実行単位の回避であり、プロジェクト/CI/通常compiler設定を恒久変更しない。ツール更新や
実行環境の再起動後はoverrideなしで再試行し、停止しなければ補助を使わず `/tmp` から削除する。
