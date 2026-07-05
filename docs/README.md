# ドキュメント地図 — Wishes

このディレクトリは、AI（および人間）が **哲学を順守した高品質な自律開発** を続けるための一次情報。
まず [`/CLAUDE.md`](../CLAUDE.md) を読み、必要に応じて下記へ辿る。

## 構成

```
docs/
  README.md                  ← このファイル（入口・用語）
  philosophy/                なぜ・何を作るか（＝判断の拠り所。正典）
    01-コアコンセプト.md        プロダクト定義（ビジョン/課題/3要素/非目標/KPI）
    02-設計原則.md ★           非交渉の設計原則（UI・AI・データの守るべき核）
  architecture/              どう作られているか（コードの地図）
    overview.md               単一 AppStore / 永続化3層 / App Group / 起動時リロード
    data-model.md             3軸モデル（優先度×季節×タグ）と主要な型
    capture-pipeline.md       URL → やりたいこと候補（オンデバイス）
  workflows/                 どう回すか（作業手順）
    build-and-verify.md       ビルド・型チェック・テスト・視覚確認・hooks の関係
    release-runbook.md        App Store 提出の手順
    app-store-metadata.md     ストア掲載メタデータ（コピペ用）
  decisions/                 なぜそう決めたか（ADR＝決定の記録。蒸し返し防止）
  index.html                 公開ポリシー/サポートページ（GitHub Pages。※移動禁止）
```

★ = 迷ったら最初に開く。

## 変更したら更新するもの（ドキュメントの鮮度維持）

- **プロダクトの方針・非目標を変えた** → `philosophy/` と、対応する `decisions/`（ADR）を更新。
- **アーキ・データモデル・取り込みパイプラインを変えた** → `architecture/` の該当ファイル。
- **ビルド/検証手順を変えた** → `workflows/build-and-verify.md`（と `.claude/` の hooks/skills）。
- **設計原則そのものを変える** → **必ず ADR を起票してから** `philosophy/02-設計原則.md` を変更。

## 用語（命名の整理）

| 表記 | 指すもの |
|------|---------|
| **Wishes** | 製品名・App Store 表示名（`PRODUCT_NAME = Wishes`、`CFBundleDisplayName = Wishes`）。ユーザーが目にする名前。 |
| **バケットリスト** | アプリの一般ジャンル名／社内での通称。哲学ドキュメントでの呼称。 |
| **BucketList** | Xcode の**プロジェクト名・スキーム名・ソースフォルダ名・バンドルID接頭辞**（`teratech.BucketList`）。開発上の識別子。 |

> つまり「Wishes（製品）＝ BucketList（開発名）＝ バケットリスト（ジャンル）」は同一物の別レイヤの呼称。
> ユーザー向け文言は **Wishes**、コード/ビルドは **BucketList**、思想の議論は **バケットリスト** を使う。
