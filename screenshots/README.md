# App Store スクリーンショット

App Store Connect には **`appstore-marketing/` の 4 枚を提出**する（1284×2778px。
iPhone 6.5/6.7インチ枠で受理される汎用サイズ）。`appstore-6.9inch/` はその素材となる生キャプチャ。

## 提出用（マーケティング版）— `appstore-marketing/`
見出し＋端末フレーム＋ブランド背景を合成した完成版。並び順どおり 01→04 でアップロード。

| ファイル | 見出し | 元画面 |
|---|---|---|
| 01.png | 他のアプリからでも、ワンタップで保存。 | 共有→Wishes コールアウト＋共有追加画面 |
| 02.png | 集めた「いつか」を、ちゃんと叶える。 | ホーム |
| 03.png | 面倒な入力は、AIにおまかせ。 | AI取り込み |
| 04.png | 叶えた数が、増えていく。 | レポート |

### 合成の再生成
`appstore-6.9inch/` の生キャプチャ＋アプリアイコンから、ヘッドレス Chrome で合成:
```sh
python3 screenshots/marketing/generate.py
```
文言・レイアウトは `screenshots/marketing/generate.py`（`SCREENS` 配列と CSS テンプレ）で編集。

## 生キャプチャ — `appstore-6.9inch/`
| ファイル | SCREEN 値 | 画面 |
|---|---|---|
| 01-home.png | home | ホーム |
| 02-report.png | records | レポート |
| 03-settings.png | settings | 設定 |
| 04-add.png | add | 追加シート（空） |
| 05-share.png | share | 共有拡張ふう「Wishesに追加」（場所入り） |
| 06-aicapture.png | addai | URL→AI 下書きカード表示 |

### 生キャプチャの撮り直し（DEBUGのみ）
撮影フック・デモデータは `BucketList/Models.swift` の `Screenshots` /
`Seed.screenshotItems` と `ContentView`（`ScreenshotFormMock`）に実装（Release では無効）。
iPhone 6.9型シミュレータに **Debug ビルド**を入れ、環境変数付きで起動して撮影:
```sh
# 事前に 9:41 のクリーンなステータスバーに
xcrun simctl status_bar <UDID> override --time "9:41" \
  --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --dataNetwork wifi

# 例: AI 取り込み画面
SIMCTL_CHILD_SCREENSHOTS=1 SIMCTL_CHILD_SCREEN=addai \
  xcrun simctl launch <UDID> teratech.BucketList
sleep 4
xcrun simctl io <UDID> screenshot screenshots/appstore-6.9inch/06-aicapture.png
```
`SCREEN` 値は `home` / `records` / `settings` / `add` / `share` / `addai`。
