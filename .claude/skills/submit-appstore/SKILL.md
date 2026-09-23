---
name: submit-appstore
description: Wishes(iOS) を App Store 審査に提出する（本番配信）。TestFlight 配信済みのビルドを scripts/submit-appstore.py でバージョン作成→新機能テキスト→ビルド紐付け→審査提出まで一括実行する。「本番に出して」「App Storeに配信」「審査に出して」と言われたら使う。
---

# /submit-appstore — App Store 審査提出（本番配信）

[scripts/submit-appstore.py](../../../scripts/submit-appstore.py) を使う。App Store Connect API で
バージョン作成 → 「このバージョンの新機能」 → ビルド紐付け → 審査提出 を一括で行う。

## 手順

1. **ビルドが上がっているか確認**：`scripts/submit-appstore.py status`。
   提出するのは `/deploy-testflight` でアップロードした pbxproj と同じ version/build。
   まだ配信していない変更があれば先に `/deploy-testflight`（未コミット確認→検証→配信→コミット）。
2. **新機能テキストを起こして確認**：前回提出以降の `git log`（`改善:`/`機能:` コミット）から
   ユーザー向けの箇条書き（「・」始まり、日本語、3行前後）を作り、**AskUserQuestion で文言を確認**する。
   ストアに出る文言なので、確認なしに提出しない。文体は
   [app-store-metadata.md](../../../docs/workflows/app-store-metadata.md) の過去バージョンに合わせる。
   「完全オフライン／一切通信しない」とは書かない。
3. **提出**：確認した文言を scratchpad のファイルに書き、
   ```sh
   scripts/submit-appstore.py submit --notes <notes.txt>            # 承認後に自動公開（既定）
   scripts/submit-appstore.py submit --notes <notes.txt> --release MANUAL
   ```
   - ビルド処理中（PROCESSING）なら自動で待つ（最大30分）。
   - `version X is READY_FOR_DISTRIBUTION` → 公開済みトレイン。`/deploy-testflight` で
     `--version` を上げて再配信してから。
   - `WAITING_FOR_REVIEW / IN_REVIEW` → 提出済み。差し替えは ASC で取り下げてから。
4. **記録**：提出した文言を `docs/workflows/app-store-metadata.md` の「このバージョンの新機能」に
   バージョン見出しで追記し、コミットする（`ドキュメント: vX.Y.Z の新機能テキストを記録`）。
5. **報告**：version/build・リリース方式・「審査は通常1〜3日、結果は ASC と連絡先メールに届く」を伝える。

## 前提

- `scripts/asc.env`（gitignore）に `ASC_ISSUER_ID` / `ASC_KEY_ID` / `ASC_APP_ID`、
  `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` に API キー。`pip3 install pyjwt`。
- 401 が出たらキー失効/権限不足。ユーザーに ASC でのキー再発行を依頼する（代行しない）。
