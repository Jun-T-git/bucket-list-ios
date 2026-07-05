---
description: Wishes(iOS) の常設ドキュメント（docs/architecture・docs/workflows 等）が、いまのコードの実態と合っているか点検し、乖離があれば同期する。コードの構造・データモデル・取り込み・ビルド手順を変えた後や、Stop フックの鮮度リマインドを受けたときに使う。
allowed-tools: Read, Grep, Glob, Edit, Bash(git diff *), Bash(git status*), Bash(git log *), Task
---

# /sync-docs — 常設ドキュメントの鮮度同期

コード変更に対して、**最新に保つべき常設ドキュメント**が実態とズレていないか点検し、必要なら直す。
（判断基準と直してよい範囲は [docs/README.md](../../../docs/README.md#常設と一時ドキュメント) を参照。）

## 進め方

**差分が中〜大／複数領域にまたがる場合** は `doc-scribe` サブエージェントに委譲する（推奨）:
> Task(subagent_type: "doc-scribe") に「現在の差分を常設ドキュメントと突き合わせて同期して」と依頼。

**差分が小さく自明な場合** は自分で直接:

1. `git diff` / `git status` で変更ファイルを把握。
2. マッピングで該当する常設 doc を Read し、コードと突き合わせる:
   - `BucketList/Models.swift` → `docs/architecture/data-model.md`, `overview.md`
   - `BucketList/Capture/**`・`ShareExtension/ShareComposeView.swift` → `docs/architecture/capture-pipeline.md`
   - ビルド/検証・hooks・スキーム → `docs/workflows/build-and-verify.md`
3. 乖離があれば**周囲の文体を保ち最小差分**で Edit（事実＝型名/ファイル名/手順/データフローを合わせる）。

## やらないこと

- `docs/philosophy/*`（正典）・`docs/decisions/*` の**方針**は書き換えない。ズレていれば「ADR 起票が必要」と報告。
- 一時ドキュメント（調査メモ・計画）は repo に作らない・鮮度対象にしない（→ scratchpad）。

## 報告

同期した箇所（ファイルごとに何を・なぜ）と、要判断で残した点を簡潔に。乖離が無ければ「IN SYNC」。
