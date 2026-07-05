---
description: Wishes(iOS) のUI変更を視覚的に自己検証する。Screenshotsモードで主要画面を撮り、設計原則(§1-4)に照らして点検する。UI/レイアウト/色/Theme を変えたら使う。
allowed-tools: Bash(xcodebuild *), Bash(xcrun simctl *), Bash(find BucketList *), Read
---

# /visual-check — UIの視覚的自己検証

UI・哲学は視覚依存（[設計原則§1–4](../../../docs/philosophy/02-設計原則.md)）。DEBUG の `Screenshots`
モードで安定したデモ状態を撮り、原則に照らして自分の目で確かめる。詳しい背景は
[screenshots/README.md](../../../screenshots/README.md) と
[docs/workflows/build-and-verify.md](../../../docs/workflows/build-and-verify.md)。

## 手順

1. **シミュレータを用意**（iPhone 17 系）。UDID を取得：
   ```sh
   xcrun simctl list devices available | grep -i "iPhone 17"
   xcrun simctl boot <UDID> 2>/dev/null; open -a Simulator
   ```
2. **Debug ビルドをインストール**：
   ```sh
   xcodebuild -project BucketList.xcodeproj -scheme BucketList \
     -destination 'platform=iOS Simulator,id=<UDID>' \
     -configuration Debug -derivedDataPath /tmp/BucketList-build build
   xcrun simctl install <UDID> /tmp/BucketList-build/Build/Products/Debug-iphonesimulator/Wishes.app
   ```
3. **9:41 のクリーンなステータスバーに**：
   ```sh
   xcrun simctl status_bar <UDID> override --time "9:41" \
     --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --dataNetwork wifi
   ```
4. **Screenshotsモードで各画面を起動して撮る**（scratchpad へ）。`SCREEN` 値：
   `home` / `records` / `settings` / `add` / `share` / `addai`。変更に関係する画面だけでよい。
   ```sh
   OUT=/private/tmp/claude-501/.../scratchpad   # 実際のスクラッチパッドに置換
   for S in home add addai; do
     SIMCTL_CHILD_SCREENSHOTS=1 SIMCTL_CHILD_SCREEN=$S xcrun simctl launch <UDID> teratech.BucketList
     sleep 4
     xcrun simctl io <UDID> screenshot "$OUT/vc-$S.png"
     xcrun simctl terminate <UDID> teratech.BucketList 2>/dev/null
   done
   ```
5. **撮った画像を Read で開き、原則に照らして点検**：
   - 色は1系統(green)の濃淡か。装飾色を乱用していないか（§2）。
   - フローティングのクロームは本物のガラス感か（§3）。
   - 標準 iOS らしい佇まいか。奇抜な独自要素・confetti が無いか（§1）。
   - レイアウト崩れ・見切れ・Dynamic Type 崩れが無いか。
6. 問題があれば具体的に指摘し修正する。無ければ「視覚確認✓（画面名）」と簡潔に報告。

## 注意
- Foundation Models はシミュレータでは基本非対応 → `addai` はルールベース候補で表示される（それが正常）。
- 生成物・スクショは scratchpad か `/tmp` に置き、repo を汚さない（`screenshots/` の正式素材は上書きしない）。
