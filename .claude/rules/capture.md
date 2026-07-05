---
description: URL取り込み（Capture/）を編集するときの非交渉ルール。体言止め・オンデバイス・タグ上限。
paths:
  - "BucketList/Capture/**"
  - "ShareExtension/ShareComposeView.swift"
---

# ルール：取り込みパイプライン（Capture/）

正典：[設計原則§7・§8](../../docs/philosophy/02-設計原則.md) / [capture-pipeline](../../docs/architecture/capture-pipeline.md)

- **体言止め・意図を足さない**：生成タイトルは名詞句で止める。「〜する/〜したい」を付けない。
  LLM（`OnDeviceModel` の `@Guide`）とルールベース（`RuleBasedCandidate`）で**表現を統一**する。
- **オンデバイス完結・外部送信禁止**：入力は端末内取得メタデータ（LinkPresentation 中心）のみ。
  ページ本文・ユーザーテキストをサーバーへ送らない。バックエンドを足さない。
- **フォールバック必須**：LLM が使えない端末（多くのシミュレータ）でも `RuleBasedCandidate` が必ず候補を返す。
- **上限**：`TagValidator` はタグ最大3・実在キーのみ・重複除去。タイトルは30字ハードキャップ。
- **SSRF ガード**：`URLSafety`（http(s)のみ・localhost/内部IP排除）を通す。
- **「完全オフライン」と謳わない**：メタ取得は対象URLへの通信が発生する。表現は「推論はオンデバイス」。
- **ドキュメント同期**：取り込みの**段・データフロー・フォールバック順**を変えたら、
  `docs/architecture/capture-pipeline.md` を実態に合わせて更新する（`/sync-docs` か doc-scribe）。
