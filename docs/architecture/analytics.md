# 利用状況アナリティクス — Wishes

「どれくらい使われ、どれくらい続き、どの機能が効いて、"やった"に変わっているか」を
数字で見るための仕組み。バックエンドは **Firebase Analytics（無料・イベント数無制限）**、
コード側の入口は **`BucketList/Analytics.swift` の1ファイルだけ**。

> 決定の経緯 → [ADR 0006](../decisions/0006-利用状況アナリティクス.md)。
> 守るべき線 → [設計原則§8](../philosophy/02-設計原則.md)（推論はオンデバイス／ユーザーの内容を外に出さない）。

## 3つの約束（コードで担保している）

1. **内容は送らない**：タイトル・メモ・URL・タグ名・ユーザー名は一切送らない。パラメータは
   固定語彙の文字列（`source=share` 等）・件数・バケット（`10-29`）だけ。`Analytics.Event` と
   shaped ヘルパー（`itemAdded` / `itemDone` …）以外からイベントを組み立てない。
2. **オフにできる**：設定 →「プライバシー」→「利用状況の送信」（`Tweaks.analyticsEnabled`、既定 ON）。
   OFF で SDK の収集を止め、Firebase 側のアプリインスタンス ID と未送信データも消し（`resetAnalyticsData`）、
   拡張のキューも破棄。`Analytics.track` は毎回この値を読む。OFF 操作そのものは送らない。
3. **SDK は本体だけ**：`ANALYTICS_FIREBASE` コンパイル条件が付く `BucketList` ターゲットのみ Firebase を
   リンク。共有拡張・ウィジェットは App Group の UserDefaults キュー（`Storage.appendAnalyticsQueue`）に
   積み、本体が次回前面復帰時に送る（`Analytics.appDidBecomeActive` → `flushQueue`）。
   高速型チェック（`swiftc -typecheck`）は SDK なしの経路でコンパイルされる。

DEBUG ビルドは **何も送らない**（`ANALYTICS_DEBUG=1` を環境変数に付けたときだけ送る）。
`Screenshots` モードも常に無効。Release は `GoogleService-Info.plist` が本物のときだけ有効。

## 仕組み（データフロー）

```
UI / AppStore ──Analytics.track(.itemDone, …)──▶ Analytics.swift
                                                    ├─ 本体: FirebaseAnalytics.logEvent
                                                    └─ 拡張: App Group キュー ──(次回前面)──▶ 本体が logEvent
起動:  AppDelegate.didFinishLaunching → Analytics.start()（plist が本物なら configure → 設定の ON/OFF を適用）
復帰:  scenePhase == .active → Analytics.appDidBecomeActive(items:)
         → Engagement（連続日数/開いた日数）を更新 → app_foreground → user property 更新 → キュー送出
通知:  AppDelegate（UNUserNotificationCenterDelegate）が nudge_open を記録
```

- `Engagement`（`Analytics.swift`、純関数 `advanced(_:today:)`）… 端末内の「開いた日」記録。
  `streak`（連続日数）・`openDays`（開いた日数）・`firstOpen`。Firebase が出せない「連続で開いているか」を
  `app_foreground` のパラメータとして送る。`Info.plist`（本体）で `FirebaseDataCollectionDefaultEnabled=false`
  にしてあるので、設定の値を適用するまで `first_open` すら送られない。
- user property（ユーザー単位の属性。ヘビー/ライトの切り分け用）：`items_bucket` / `done_bucket` / `streak_bucket`
  （値は `0` / `1-4` / `5-9` / `10-29` / `30+`）。

## イベント語彙（`Analytics.Event`）

| イベント | いつ | 主なパラメータ | 何がわかるか |
|---|---|---|---|
| `app_foreground` | 前面復帰ごと | `streak_days` `open_days` `days_since_first` `item_count` `done_count` `done_this_year` | DAU の中身・連続利用・保有数分布 |
| `onboarding_complete` | 初回ガイド完了 | — | 導入率 |
| `screen_view` | タブ切替・シート表示 | `screen_name`= home/report/settings/add/edit/detail/filter | 画面ごとの利用 |
| `item_add` | 保存 | `source`=app/share `has_url` `from_capture` `priority` `season` `tag_count` | 追加経路・URL取込の寄与 |
| `item_update` | 編集保存 | `has_url` | |
| **`item_done`** | **達成（KPI）** | `source`=list/detail/bulk `priority` `season` `has_url` `days_open` | "やった"に変わった数・寝かせ日数 |
| `item_undone` | 未達成に戻す | `source` | 誤タップ率 |
| `item_delete` | 削除 | `source`=single/bulk `count` `was_done` | |
| `undo` | トーストの元に戻す | `kind`=delete/delete_many `count` | 誤操作の救済回数 |
| `item_link_open` | 詳細から保存元リンクを開く | — | リンク保存の価値 |
| `capture_result` | URL 読み取り完了 | `outcome`=ok/low_confidence/failed/invalid `source` | 取込の成功率 |
| `capture_apply` | 「反映」タップ（アプリ内） | — | 候補の採用率 |
| `suggestion_tap` / `suggestion_dismiss` | ホームのタイミング提案 | — | 提案が効いているか |
| `widget_tap` | ウィジェットからの起動 | — | ウィジェット経由の復帰 |
| `nudge_open` | 通知タップ | `kind`=season/weekend/month_end | 通知の効き |
| `filter_change` / `sort_change` | 絞り込み・並び替え | `axis` `active_count` / `mode` `ascending` | 3軸の使われ方 |
| `bulk_action` | 一括編集 | `kind`=tag_add/tag_remove/priority/done/undone `count` | 選択モードの利用 |
| `custom_tag_add` | カスタムタグ追加 | `custom_count` | |
| `goal_change` | 年間目標変更 | `goal` | |
| `setting_change` | 設定トグル | `key` `value` | 通知/自動分類/計測の ON/OFF 率 |

命名ルール：snake_case・40字以内・Firebase 予約名（`session_start` `first_open` `notification_open` …）を
使わない。**名前を変えると履歴が分断される**ので、変えるなら ADR。`AnalyticsLogicTests` が語彙の形式を検査する。

## よく聞く問いと、Firebase コンソールでの見方

Firebase コンソール → プロジェクト → **Analytics**（左メニュー）。データ反映は最大 24 時間遅れ。

| 知りたいこと | 見る場所 |
|---|---|
| アクティブユーザー（DAU/WAU/MAU） | ダッシュボード「ユーザー数」／「エンゲージメント」 |
| 継続率（N日後に戻ってきたか） | 「維持率（Retention）」コホート表 |
| **連続で開いている人** | 探索（Explore）→ ユーザーの `streak_bucket` で内訳、または `app_foreground` の `streak_days` 分布 |
| **ヘビーユーザーの割合** | 探索 → ユーザー属性 `items_bucket` / `done_bucket` のセグメント比較 |
| どの機能がどれだけ | 「イベント」一覧のイベント数・ユーザー数（`item_add` `capture_result` `suggestion_tap` …） |
| **"やった"に変わった数** | `item_done` の件数と `days_open` の分布。`source` で入口比較 |
| URL 取込の成功率 | `capture_result` を `outcome` で内訳 → 目標：`failed` を減らす |
| 通知・ウィジェットの効き | `nudge_open` / `widget_tap` の後に `item_done` が続くファネル（探索 → ファネル） |
| 設定のオプトアウト率 | **取れない**（OFF にした瞬間から一切送らない＝"off means off"。`setting_change key=analytics` は ON に戻した時だけ届く）。ユーザー数の減り方から間接的に推定する |

パラメータで内訳を見るには、Firebase で **カスタムディメンション** として登録する（Analytics → カスタム定義。
イベント単位：`source` `outcome` `screen_name` `kind` `axis`、ユーザー単位：`items_bucket` `done_bucket` `streak_bucket`）。
数値パラメータ（`days_open` `streak_days`）は **カスタム指標** として登録。上限はディメンション 50・指標 50。

## セットアップと鍵ファイル

- Firebase プロジェクト：**`wishes`**（ID `wishes-750b8`、コンソール
  https://console.firebase.google.com/project/wishes-750b8/analytics ）。iOS アプリ `teratech.BucketList`（ニックネーム "Wishes iOS"）を登録済み（2026-09-23）。
  Google アナリティクスは有効、Gemini in Firebase は無効にして作成。
- `BucketList/GoogleService-Info.plist` は上記アプリの本物（git 管理。iOS の API キーはバンドル ID で制限されるため秘密扱い不要。
  CI の署名なしビルドもこのファイルを使う）。差し替えるときはコンソール → プロジェクトの設定 → マイアプリ → GoogleService-Info.plist。
  プレースホルダ（`GOOGLE_APP_ID` が `1:` で始まらない）に戻すと `Analytics.start()` が configure を諦め、計測だけが無効になる。
- 動作確認は DEBUG で環境変数 `ANALYTICS_DEBUG=1`（シミュレータなら `SIMCTL_CHILD_ANALYTICS_DEBUG=1`）＋
  起動引数 `-FIRDebugEnabled` で、Firebase の **DebugView** に数秒でイベントが並ぶ。

依存：SPM `firebase-ios-sdk`（プロダクト `FirebaseAnalytics` のみ、本体ターゲット限定）、
`OTHER_LDFLAGS` に `-ObjC`（Analytics に必須）。初回ビルドはパッケージ取得で数分かかる。

## 変更するとき

- イベントを足す：`Analytics.Event` にケース追加 → shaped ヘルパーか `track` を発火点に置く →
  上の表に1行追加 → 必要なら Firebase でカスタムディメンション登録。
- **足してはいけないもの**：自由文字列（タイトル・URL・タグ名）、ユーザー名、位置情報、連絡先。
  迷ったら「固定語彙 or 件数 or バケット」に落とす。
- 拡張で発火するイベントは自動的にキュー経由（時刻は送出時になる＝日次集計には十分）。
- App Store 側：App Privacy の申告（[release-runbook](../workflows/release-runbook.md#4-アプリ情報バージョン情報を入力)）と
  公開プライバシーポリシー（`docs/index.html` §6）を同期させる。


## 4アプリ共通計測 v1（2026-10-17）

`Analytics.Operation` がローカル操作トークンを持ち、受付時 `action_start`、終端時に1回だけ
`action_result` を送る。ID・内容・URL・エラー文・認証情報は渡さない。固定パラメータは
`schema_version=1`、`action_name`、`result=success/error/cancelled`。処理エラーは固定許可リスト
`error_code`（現在の保存失敗は `storage`）。バックグラウンド/ユーザー確認待ち時間を除く継続時間を取得していないため、`duration_ms` は省略する。

- `save_item`：手動保存受付から SharedStore 保存（本体は既存の1回リトライ含む）の確定まで。候補未採用・解析失敗後の手入力保存もこの操作。
- `import_item`：新規追加で有効URL・自動分類・利用上限を検証後、実際の候補生成開始から採用した項目の保存確定まで同一token。本体は「反映」、共有拡張は自動採用。解析失敗は error=unknown、低信頼で候補を採用できない結果は error=validation。明示キャンセル・破棄・候補却下・URL置換・候補未採用の手動保存は cancelled。無効URLや処理を始めない入力ではstartしない。旧URLの非同期結果はtoken一致も検証し、再生成の結果を上書きしない。編集画面の解析は新規項目取り込みに数えない。
  URLメタ情報取得や候補生成そのものは既存 `capture_result` の担当で、共通の保存成功に数えない。
- `complete_item`：一覧・詳細・一括で未完了から完了へ変える時。実書込み成功のみ success。
  一括は実際に遷移する各項目について1操作。既に完了した項目への再適用、達成日編集、未完了戻しは対象外。
- `view_item`：既存項目詳細の初回表示で result=success のみ。SwiftUI 再描画/同一sheet再表示では再送しない。

手動保存前のフォーム破棄では共通開始/取消を送らない。取り込み開始済みの明示破棄は取消にする。同期保存には実行中の取消UIがない。
background/killを取消やエラーと推定しない。既存 `item_add` / `item_done` も実保存成功時だけに合わせた。
失敗後のメモリとディスクの差、host/share同時編集の競合解決は既存ストアの挙動を維持する。

### 初回価値の証拠・移行・重複抑止

初回scope状態の作成は本体AppStore初期化/共有拡張開始の最初に行う。作成前のSharedStore
（空の既存ファイルを含む/読取り不能）、旧item/tagデータ、engagement、onboarding、tweaks/prefs、
Pro/無料取込履歴は existing の証拠として分類する。今回の初起動でも作られる移行済みフラグは証拠に使わない。
証拠なしは unknown であり、空ストア/フラグ不在を新規とはしない。履歴snapshotの協調保存が成功する前は検証済み新規証拠も受理せず、初回価値を発火しない。snapshot未確定時の保存も消費し、後から初期化/証拠が成功しても遡及発火しない。この履歴snapshotを1回だけ記録し、
計測導入後に同じscopeが作った履歴を後からexistingと誤判定しない。

本体は計測同意ON・送信許可ビルド（DEBUGは明示opt-in）・Screenshots無効・`CommonMeasurementFirstBuild` 設定済みの場合だけ StoreKit `AppTransaction.shared` を読む。
検証済み・production・bundleID一致・現在CFBundleVersionが導入build以上・originalAppVersionが導入build以上を
すべて満たすと verifiedNew。originalAppVersionが境界より前ならexisting。数値dot区切りbuild版を比較し、
マーケティング版は使用しない。sandbox、署名未検証、throw、形式不正、境界未設定、原取得buildが現在buildより大きい不整合はunknown。
`refresh()`、購入、復元、認証UIは呼ばず、取得情報/ID/署名をAnalyticsへ送らない。
既存履歴のexisting分類は新規証拠より優先する。

**境界は未設定であり、新規対象の初回価値は現状未収集**。現在のbuild10を導入版と推定しない。
最初の計測入りApp Store公開ビルドを確定する際、本体Info.plistに文字列 `CommonMeasurementFirstBuild` と
そのCFBundleVersionを設定し、以後境界を維持する（今回版上げ/配布は行わない）。SDK first_openのcallbackは仮定しない。

共通初回価値の導入境界を設定する前に、App Store Connect の過去全バージョン・全配布ビルドの
CFBundleVersionを監査する。マーケティング版をまたいでbuild番号がリセット/再利用されている可能性があるため、
「現在10なので次11」だけでは新規取得の証拠にならない。過去の全配布値を数値dot区切り比較で上回る未使用の
導入buildを選び、その値を本体Info.plistの文字列 `CommonMeasurementFirstBuild` に設定する。
以後は全マーケティング版でCFBundleVersionを単調増加させ、境界を固定し、番号を下げたり再利用しない。
この履歴は今回未監査のため境界は未設定のまま維持し、初回価値を収集しない。公開前提を確認できない間は有効化しない。

originalAppVersionはAppleアカウントが最初にアプリを取得した時のbuildであり、端末へのinstall日時ではない。
対象は「署名済みの導入後取得かつ旧local履歴なし」のlocal scopeの部分集合で、旧取得アカウントの新端末/再インストールは除外され得る。
人物の初取得や端末の初installを保証する指標ではない。共有拡張先行や証拠遅延/取得失敗ではunknownのまま最初の保存を
消費し、後着proofでも発火しない。pending再送は持たず、正しい初保存の欠測を受容する。この遡及抑止は回帰テストで確認する。

`FirstValueState` はApp Groupの `common-measurement-v1.json` にNSFileCoordinatorで読み書きを直列化し、
原子的書込み成功後にのみイベントを渡す。旧UserDefaultsの消費済み状態を移行し、既存/不明/同意OFFの保存成功も
消費する。後からON、アップデート、証拠後着でも再送しない。破損ファイル/共有コンテナ取得失敗/書込み失敗は
発火せず、破損を空状態として上書きしない。SDKへの受け渡し直後のクラッシュを含む配送exactly-onceは保証しない。
実機では旧版更新・初インストール・再インストール・共有先行・同意切替とGA4自動first_openとの対応を検証する。

### GA4/集計の別工程

イベントスコープのカスタム定義に `action_name`, `result`, `schema_version`、将来activation有効化時は
`activation_key`, `definition_version`, `first_status` を登録。任意 `error_code`。operation/item IDは登録しない。
通常収集後 Data API metadata の利用可能性を確認し、collector/MetricDefinitionsを更新する。
`action_start` と `action_result AND result=success` は action_name別の期間全体totalUsersとして別問い合わせ。
legacy `item_add/item_done` と共通イベントは同一操作を表すため、件数/UUを合算しない。期間/stream/identityを揃えて
共通系列へ切り替え、移行期間の和集合UUが必要なら重複排除可能な探索で確認する。独立UU比を順序付き成功率や
7日activation率にしない。first_open/session_start/user_engagementを手動送信しない。
Proは現リリース無効、既存StoreKit経路に売上送信を追加しない。GA4設定/Sheet/Apps Scriptは本変更で操作しない。
