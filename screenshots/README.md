# App Store スクリーンショット

`appstore-6.9inch/` … iPhone 6.9型（1320×2868px）。App Store Connect の
「iPhone 6.9インチディスプレイ」枠にそのままアップロードできる。

| ファイル | 画面 |
|---|---|
| 01-home.png | ホーム（リスト＋今週末のおすすめ） |
| 02-report.png | レポート（達成の記録） |
| 03-settings.png | 設定 |
| 04-add.png | 追加シート |

好きな枚数を選んで（1〜10枚）アップロード。おすすめは 01→02→04→03 の順。

## 再生成の方法（DEBUGのみ）
デモデータ・撮影フックは `BucketList/Models.swift` の `Screenshots` /
`Seed.screenshotItems` と `ContentView` 等に実装（Release では無効）。
シミュレータ（iPhone 6.9型）にDebugビルドを入れ、環境変数付きで起動して撮影:

```sh
# 例: レポート画面
SIMCTL_CHILD_SCREENSHOTS=1 SIMCTL_CHILD_SCREEN=records \
  xcrun simctl launch <UDID> teratech.BucketList
xcrun simctl io <UDID> screenshot 02-report.png
```
`SCREEN` は `home` / `records` / `settings` / `add`。
9:41 表示にするには事前に
`xcrun simctl status_bar <UDID> override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3`。
