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
