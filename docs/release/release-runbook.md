# リリース手順書（バケットリスト v1.0 / iPhone）

コード・設定側は準備完了（Release ビルド/アーカイブ検証済み・iPhone限定・privacy manifest 同梱）。
残りは Apple アカウント上の手動作業。上から順に進める。メタデータは `app-store-metadata.md` からコピペ。

前提: Apple Developer Program 加入済み。Bundle ID `teratech.BucketList` / 拡張 `teratech.BucketList.ShareExtension`。

---

## 0. Xcode で署名チームを設定
1. `BucketList.xcodeproj` を Xcode で開く。
2. **BucketList** ターゲット → **Signing & Capabilities** → Team で自分のチームを選択（`Automatically manage signing` ON）。
3. **ShareExtension** ターゲットでも同じチームを選択。
4. これで App ID と App Group (`group.teratech.BucketList`) が Developer Portal に自動登録される。
   - （Team ID を教えてもらえれば、この手順なしで済むよう project に直接書き込めます）

## 1. 契約・税・銀行（Agreements, Tax, and Banking）※IAPに必須
App Store Connect → **契約/税金/口座情報**:
1. **有料Appプログラム（Paid Apps）契約**に同意。
2. **税務情報**・**銀行口座情報**を登録（これが未完だと IAP を含むアプリは審査に出せない）。

## 2. アプリを新規作成
App Store Connect → **マイApp** → **＋** → 新規App:
- プラットフォーム: iOS
- 名前: **バケットリスト**
- 主要言語: 日本語
- バンドルID: `teratech.BucketList`
- SKU: `bucket-list-ios`

## 3. アプリ内課金（IAP）を作成
対象App → **収益化 → App内課金** → ＋:
- タイプ: **非消費型**
- 参照名: BucketList Pro
- Product ID: **`teratech.BucketList.pro`**（コードと完全一致・必須）
- 価格: **¥600** の価格帯
- ローカリゼーション(ja): 表示名「バケットリスト Pro」／説明は `app-store-metadata.md` から
- レビュー用スクショ: Paywall画面を1枚アップロード
- ステータスが「提出準備完了」になればOK（初回はアプリ本体の審査と同時に審査される）

## 4. アプリ情報・バージョン情報を入力
- **一般情報**: カテゴリ（ライフスタイル）、年齢制限（4+）。
- **App プライバシー**: 「データを収集しません」を選択して公開。
- **プライバシーポリシーURL**: `https://jun-t-git.github.io/bucket-list-ios/`
- **サポートURL**: 同上。
- バージョン 1.0 の: プロモーションテキスト / 説明 / キーワード / スクリーンショット / 「このバージョンの新機能」を入力（`app-store-metadata.md`）。

## 5. スクリーンショット（iPhoneのみ・iPad不要）
- 必須: **6.7インチ（iPhone 15 Pro Max 等）** 1〜10枚。
- 推奨: 6.5インチも用意するとより多くの端末で最適表示。
- （希望すれば、シミュレータから規格サイズのスクショをこちらで生成できます）

## 6. ビルドをアップロード
1. Xcode 上部のデバイス選択を **Any iOS Device (arm64)** に。
2. **Product → Archive**。
3. 完了後 **Organizer** が開く → **Distribute App** → **App Store Connect** → **Upload**。
4. 数分〜数十分で ASC の「TestFlight/ビルド」に表示される（処理中はしばらく待つ）。
5. バージョン 1.0 の「ビルド」欄でアップロードしたビルドを選択。

## 7. 審査へ提出
- バージョンに IAP（バケットリスト Pro）を**紐付け**る。
- **App Review 情報**（連絡先・審査メモ）を `app-store-metadata.md` から記入。
- 輸出コンプライアンス: 「非対象暗号のみ使用」=はい（`ITSAppUsesNonExemptEncryption=NO` 設定済みなので追加質問は出ない想定）。
- **「審査へ提出」**。あとは Apple の審査（通常1〜3日程度）。

---

## 提出前チェックリスト
- [ ] 0. 両ターゲットに署名チーム設定
- [ ] 1. Paid Apps 契約＋税/銀行 完了
- [ ] 2. アプリ作成（Bundle ID 一致）
- [ ] 3. IAP `teratech.BucketList.pro` 作成（¥600・非消費）
- [ ] 4. App Privacy=収集なし／ポリシーURL登録
- [ ] 5. iPhone スクショ（6.7型）アップロード
- [ ] 6. Archive→Upload 完了・ビルド選択
- [ ] 7. IAP紐付け・審査メモ記入・提出

## 補足
- 実機テスト（任意・推奨）: TestFlight 内部テストで、共有拡張からの追加・無料10回の上限・Pro購入/復元（Sandbox）を一度確認しておくと安心。
- アプリ説明文で「完全オフライン／一切通信しない」と書かないこと（共有リンク取得で端末→リンク先の通信が発生するため）。
