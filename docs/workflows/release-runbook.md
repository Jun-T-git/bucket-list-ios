# リリース手順書（Wishes: やりたいことリスト v1.0 / iPhone）

コード・設定側は準備完了（Release ビルド/アーカイブ検証済み・iPhone限定・privacy manifest 同梱）。
残りは Apple アカウント上の手動作業。上から順に進める。メタデータは `app-store-metadata.md` からコピペ。

前提: Apple Developer Program 加入済み。Bundle ID `teratech.BucketList` / 共有拡張 `teratech.BucketList.ShareExtension` /
ウィジェット拡張 `teratech.BucketList.Widget`。

> ℹ️ **v1.0 は課金機能を無効化した無料リリース**（コード側 `FeatureFlags.proEnabled = false`）。
> そのため **手順1（Paid Apps契約）と手順3（IAP作成）は不要・スキップ**。税/銀行情報の登録も後回しでよい。
> 将来 Pro を再開するときは `FeatureFlags.proEnabled = true` に戻し、手順1・3を実施する。

---

## 0. Xcode で署名チームを設定
1. `BucketList.xcodeproj` を Xcode で開く。
2. **BucketList** ターゲット → **Signing & Capabilities** → Team で自分のチームを選択（`Automatically manage signing` ON）。
3. **ShareExtension** と **WidgetExtension** ターゲットでも同じチームを選択。
4. これで App ID と App Group (`group.teratech.BucketList`) が Developer Portal に自動登録される。
   - （Team ID を教えてもらえれば、この手順なしで済むよう project に直接書き込めます）

## 1. 契約・税・銀行（Agreements, Tax, and Banking）※v1.0はスキップ可
無料アプリ（IAPなし）なので **今回は不要**。無料App契約（Free Apps）が有効ならそのままでOK。
（将来 Pro を有効化する際に、Paid Apps 契約＋税務・銀行情報の登録が必要になる）

## 2. アプリを新規作成
App Store Connect → **マイApp** → **＋** → 新規App:
- プラットフォーム: iOS
- 名前: **Wishes: やりたいことリスト**
- 主要言語: 日本語
- バンドルID: `teratech.BucketList`
- SKU: `bucket-list-ios`

## 3. アプリ内課金（IAP）を作成 ※v1.0はスキップ
本バージョンは課金機能を無効化しているため **IAP は作成しない**。
（将来 Pro を有効化する際の手順は `app-store-metadata.md` のIAP節を参照）

## 4. アプリ情報・バージョン情報を入力
- **一般情報**: カテゴリ（ライフスタイル）、年齢制限（4+）。
- **App プライバシー**（v1.1.0 build 10 以降、利用状況アナリティクス導入後。2026-09-23 設定済み）: 「はい、データを収集します」で以下を申告
  （[ADR 0006](../decisions/0006-利用状況アナリティクス.md)／[analytics.md](../architecture/analytics.md)）:
  - **利用状況データ → プロダクトの操作**：目的＝アナリティクス／ユーザーに紐付けない／トラッキングに使用しない
  - **識別子 → デバイス ID**（Firebase SDK のアプリインスタンス ID）：目的＝アナリティクス／紐付けない／トラッキングなし
  - **診断 → その他の診断データ** は Firebase Analytics 単体では不要（Crashlytics 未使用）
  - 最終確認は Xcode Organizer のアーカイブ → **Generate Privacy Report**（自前＋SDK の manifest を合算した結果）と一致させる。
  - 「トラッキング」は **いいえ**（ATT なし・IDFA 不使用）。
  - v1.1 以前は「データを収集しません」だった。ポリシー URL の内容（`docs/index.html` §1/§6）も同時に更新済みであること。
- **プライバシーポリシーURL**: `https://jun-t-git.github.io/bucket-list-ios/`
- **サポートURL**: 同上。
- バージョン 1.0 の: プロモーションテキスト / 説明 / キーワード / スクリーンショット / 「このバージョンの新機能」を入力（`app-store-metadata.md`）。

## 5. スクリーンショット（iPhoneのみ・iPad不要）
- **提出用（完成版）**: `screenshots/appstore-marketing/`（1284×2778px・4枚）。
  見出し＋端末フレーム＋背景を合成済み。**01→02→03→04 の順**でアップロード（iPhone 6.5/6.7インチ枠で受理）。
- この1サイズで iPhone 全機種の表示に使われる（6.9型枠に出す場合は 1320×2868 が必要）。
- 文言・レイアウトの調整や再生成は `screenshots/README.md` /
  `screenshots/marketing/generate.py` を参照。

## 6. ビルドをアップロード

**推奨: スクリプトで一括**（型チェック→ビルド番号+1→アーカイブ→アップロード。スキル `/deploy-testflight` でも同じ）:

```sh
scripts/release-testflight.sh                  # ビルド番号を +1 して配信
scripts/release-testflight.sh --version 1.0.2  # リリース済みトレインが閉じている場合はバージョンを上げる
```

前提は Xcode に Apple ID サインイン済みのみ（認証・署名に使う）。成功したら pbxproj のバージョン変更をコミットする。
アナリティクスを有効にして出すには `BucketList/GoogleService-Info.plist` が **本物**（Firebase コンソール由来）であること
（プレースホルダのままでもビルド・審査は通るが計測は無効。[analytics.md §セットアップ](../architecture/analytics.md#セットアップ初回と鍵ファイル)）。

<details><summary>手動（Xcode GUI）の場合</summary>

1. Xcode 上部のデバイス選択を **Any iOS Device (arm64)** に。
2. **Product → Archive**。
3. 完了後 **Organizer** が開く → **Distribute App** → **App Store Connect** → **Upload**。

</details>

- 数分〜数十分で ASC の「TestFlight/ビルド」に表示される（処理中はしばらく待つ）。
- 審査に出す場合は、対象バージョンの「ビルド」欄でアップロードしたビルドを選択。

## 7. 審査へ提出

**推奨: スクリプトで一括**（バージョン作成→新機能テキスト→ビルド紐付け→審査提出。スキル `/submit-appstore` でも同じ）:

```sh
scripts/submit-appstore.py status                    # バージョン/ビルドの状態
scripts/submit-appstore.py submit --notes notes.txt  # pbxproj の version/build を提出（承認後に自動公開）
scripts/submit-appstore.py submit --notes notes.txt --release MANUAL   # 承認後に手動で公開する場合
```

- `notes.txt` は「このバージョンの新機能」（日本語・「・」箇条書き）。提出した文言は
  `app-store-metadata.md` の同節にバージョンごとに記録する。
- 新バージョンの作成時、説明文・キーワード・スクショ等の ja ストア情報は前バージョンから ASC が複製する。
  変えたいときは提出前に ASC で編集（または `--dry-run` で手前まで作ってから ASC で編集→提出）。
- 前提: `scripts/asc.env`（gitignore。雛形 `asc.env.example`）に Issuer ID / Key ID / App ID、
  `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` に API キー（ASC → ユーザとアクセス → 統合）、`pip3 install pyjwt`。
- 公開済みトレイン（`READY_FOR_DISTRIBUTION`）には提出できない → §6 で `--version` を上げて再配信。

<details><summary>手動（ASC GUI）の場合</summary>

- **App Review 情報**（連絡先・審査メモ）を `app-store-metadata.md` から記入。
- 輸出コンプライアンス: 「非対象暗号のみ使用」=はい（`ITSAppUsesNonExemptEncryption=NO` 設定済みなので追加質問は出ない想定）。
- 対象バージョンの「ビルド」欄でアップロードしたビルドを選択し、**「審査へ提出」**。

</details>

あとは Apple の審査（通常1〜3日程度）。結果は ASC の App Review と連絡先メールに届く。

---

## 提出前チェックリスト（v1.0・無料）
- [ ] 0. 全ターゲット（本体/ShareExtension/WidgetExtension）に署名チーム設定
- [ ] 2. アプリ作成（Bundle ID 一致）
- [ ] 4. App Privacy＝利用状況データ＋識別子（紐付けなし・トラッキングなし）／ポリシーURL登録（v1.1 以前は「収集なし」）
- [ ] 4'. `GoogleService-Info.plist` が本物（計測を有効にする場合）
- [ ] 5. iPhone スクショ（6.7型）アップロード
- [ ] 6. Archive→Upload 完了・ビルド選択
- [ ] 7. 審査メモ記入・提出
- （1. Paid Apps と 3. IAP は v1.0 ではスキップ）

## 補足
- 実機テスト（任意・推奨）: TestFlight 内部テストで、共有拡張からの追加と、URL自動取り込みが無制限に動くことを確認しておくと安心。
- アプリ説明文で「完全オフライン／一切通信しない」と書かないこと（共有リンク取得で端末→リンク先の通信が発生するため）。
- Pro を将来有効化する手順: `BucketList/Models.swift` の `FeatureFlags.proEnabled` を `true` に戻し、本書の手順1・3（Paid Apps契約・IAP作成）を実施して再提出。
