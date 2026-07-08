---
name: deploy-testflight
description: Wishes(iOS) を TestFlight に配信する。検証（型チェック→ビルド→テスト）を通してから scripts/release-testflight.sh でアーカイブ→App Store Connect アップロードまで一括実行し、バージョン変更をコミットする。「TestFlightに配信」「デプロイして」と言われたら使う。
---

# /deploy-testflight — TestFlight 配信

[scripts/release-testflight.sh](../../../scripts/release-testflight.sh) を使って配信する。

## 手順

1. **未コミットの変更があれば先に確認**：配信はコミット済みのコードで行うのが原則。
   未コミット差分があるときは、コミットするか確認してから進める。
2. **検証**：`/verify-build`（型チェック→シミュレータビルド→ユニットテスト）。失敗したら配信しない。
3. **配信**：
   ```sh
   scripts/release-testflight.sh                  # ビルド番号 +1（通常はこれ）
   scripts/release-testflight.sh --version 1.0.2  # App Store 提出済みトレインが閉じている場合
   ```
   - `bundle version must be higher than 'N'` → `--build N+1` で再実行。
   - `train version 'X' is closed` → ユーザーに新バージョン番号（例: パッチなら +0.0.1）を確認して `--version` で再実行。
4. **コミット**：成功したら pbxproj のバージョン変更を
   `リリース: vX.Y.Z (build N) — TestFlight配信` の形でコミット＆プッシュする。

## 前提・注意

- Xcode に Apple ID サインイン済みであること（署名とアップロード認証は Xcode のアカウントを使う）。
- アップロード後、ASC 側の処理に数分〜数十分かかる。内部テスターには処理完了後に自動配信される。
- App Store 審査への提出は別途 [docs/workflows/release-runbook.md](../../../docs/workflows/release-runbook.md) の手順で行う。
