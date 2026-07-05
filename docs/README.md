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

## 常設と一時ドキュメント

ドキュメントは **2種類** ある。混同しないこと。

| 種別 | 何 | 置き場所 | 鮮度 |
|------|----|---------|------|
| **常設（evergreen）** | 上記 `docs/**`（philosophy/architecture/workflows/decisions/index.html）＋ `/README.md`・`/CLAUDE.md` | **git 管理** | **常に最新に保つ**（下記の仕組みで担保） |
| **一時（temporary）** | 調査メモ・実装計画・作業ログ・下書き | **セッションの scratchpad**（repo 外）。commit しない | 使い捨て |

> 一時ドキュメントを `docs/` や repo ルートに置かない。残す価値が出たら、**常設へ昇格**する
> （設計判断なら `decisions/` に ADR、事実・地図なら `architecture/`）。それ以外は scratchpad で捨てる。

## 常設ドキュメントの鮮度維持（自動化の仕組み）

コード変更に対して常設ドキュメントを追随させるための**受動的でない**仕掛け:

- **編集時リマインド**：`Models.swift` / `Capture/**` を触ると `.claude/rules/*` が該当 architecture doc の
  同期を自動提示する（パス別注入）。
- **完了時の鮮度チェック**：`.claude/hooks/doc-freshness.sh`（Stop フック）が、コードは変わったのに対応 doc が
  未更新なら**1度だけ**リマインドする（stamp でループ防止・非強制。正確なら「更新不要」判断で完了可）。
- **同期の実行**：`/sync-docs` スキル、または `doc-scribe` サブエージェント（差分を読み常設 doc を最小差分で更新）。
  哲学の是非を見る `design-guardian` とは別軸＝**事実の鮮度**。

**手動で更新すべき対応表**（上記が拾わない領域も含む）:

- **プロダクトの方針・非目標を変えた** → `philosophy/` と、対応する `decisions/`（ADR）を更新。
- **データモデル/型/永続化を変えた** → `architecture/data-model.md`・`overview.md`。
- **取り込みパイプラインを変えた** → `architecture/capture-pipeline.md`。
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
