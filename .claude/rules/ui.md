---
description: UI（View/Theme/Components）を編集するときの非交渉ルール。標準iOS・1系統色・本物のglass。
paths:
  - "BucketList/Theme.swift"
  - "BucketList/Components.swift"
  - "BucketList/*View.swift"
  - "BucketList/*Sheet.swift"
---

# ルール：UI（View / Theme / Components）

正典：[設計原則§1–4](../../docs/philosophy/02-設計原則.md) / [ADR 0004](../../docs/decisions/0004-標準iOS-UIとフォント差し戻し.md)

- **標準 iOS・plain/familiar**：標準コンポーネント・標準ジェスチャを第一選択。奇抜な独自操作を作らない。
  フォントは system font（`Theme.Font` は SF にマップ済み）。カスタム書体を無断で復活させない。
- **色は1系統（green）の濃淡**で構造を表す（優先度 高/中/低 = green700/500/300）。`sun*`/`peach*` は限定装飾のみ。
  違いは**色数ではなく形・長さ**で見せる。優先度を赤黄青で塗り分けない。タグを虹色にしない。
- **本物の Liquid Glass**：フローティングのクロームは `View.glass(in:)`（iOS26+ で純正 `.glassEffect`）。
  iOS26 で `.ultraThinMaterial` を直書きしてガラス風を自作しない。
- **達成演出はトースト＋undo のみ**。confetti / キラキラを足さない。done は単一フラットリスト内でディム＋打ち消し線。
- **一括編集は Apple メール風**（編集→行の選択○ `RowSelectCircle`→下部ツールバー）。長押しメニューで再発明しない。
- 既存の `Components` プリミティブ・`FlowLayout`・チップ語彙を再利用する。
